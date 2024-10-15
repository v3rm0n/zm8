const SDL = @import("sdl2");
const std = @import("std");
const SDLFont = @import("font.zig");
const FxCube = @import("fx_cube.zig");

const stdout = std.io.getStdOut().writer();

var texture_width: usize = 320;
var texture_height: usize = 240;
var dirty: bool = true;
var background_color: SDL.Color = .black;

const UI = @This();

window: SDL.Window,
renderer: SDL.Renderer,
main_texture: SDL.Texture,
full_screen: bool,
font: SDLFont,

pub fn init(full_screen: bool, use_gpu: bool) !UI {
    std.log.debug("Initialising SDL UI", .{});

    const window = try SDL.createWindow(
        "zm8",
        SDL.WindowPosition.centered,
        SDL.WindowPosition.centered,
        texture_width * 2,
        texture_height * 2,
        .{
            .vis = .shown,
            .context = .opengl,
            .resizable = true,
            .dim = if (full_screen) .fullscreen else .default,
        },
    );

    const renderer_flags: SDL.RendererFlags = if (use_gpu) .{ .accelerated = true } else .{ .software = true };

    const renderer = try SDL.createRenderer(window, null, renderer_flags);
    try renderer.setLogicalSize(@intCast(texture_width), @intCast(texture_height));

    const main_texture = try SDL.createTexture(
        renderer,
        .argb8888,
        .target,
        texture_width,
        texture_height,
    );

    try renderer.setTarget(main_texture);

    try renderer.setColor(background_color);
    try renderer.clear();

    dirty = true;

    return .{
        .window = window,
        .renderer = renderer,
        .main_texture = main_texture,
        .full_screen = full_screen,
        .font = try SDLFont.init(renderer, false, false),
    };
}

pub fn adjustSize(self: *UI, width: usize, height: usize) !void {
    texture_height = height;
    texture_width = width;

    const window_size = self.window.getSize();
    if (window_size.height < texture_height * 2 or window_size.width < texture_width * 2) {
        try self.window.setSize(.{ .width = @as(c_int, @intCast(texture_width * 2)), .height = @as(c_int, @intCast(texture_height * 2)) });
    }
    self.main_texture.destroy();
    try self.renderer.setLogicalSize(@intCast(texture_width), @intCast(texture_height));
    self.main_texture = try SDL.createTexture(
        self.renderer,
        .argb8888,
        .target,
        texture_width,
        texture_height,
    );
    try self.renderer.setTarget(self.main_texture);
    try self.renderer.setColor(background_color);
    try self.renderer.clear();
    dirty = true;
}

pub fn toggleFullScreen(self: *UI) !void {
    self.full_screen = !self.full_screen;
    try self.window.setFullscreen(if (self.full_screen) .fullscreen else .default);
    _ = try SDL.showCursor(true);
}

pub fn setFont(self: *UI, v2: bool, large: bool) !void {
    self.font.deinit();
    self.font = try SDLFont.init(self.renderer, v2, large);
}

pub fn drawCharacter(
    self: *UI,
    character: u8,
    position: SDL.Point,
    foreground: SDL.Color,
    background: SDL.Color,
) !void {
    try self.font.draw(self.renderer, character, position, foreground, background);
    dirty = true;
}

pub fn drawRectangle(
    self: *UI,
    position: SDL.Point,
    width: c_int,
    height: c_int,
    color: SDL.Color,
) !void {
    const rectangle = SDL.Rectangle{
        .x = position.x,
        .y = position.y + self.font.inline_font.screen_offset_y,
        .width = width,
        .height = height,
    };

    if (rectangle.x == 0 and rectangle.y <= 0 and rectangle.width == texture_width and rectangle.height >= texture_height) {
        std.log.debug("Setting background color to {}", .{color});
        background_color = color;
    }

    try self.renderer.setColor(color);
    try self.renderer.fillRect(rectangle);
    dirty = true;
}

pub fn drawOscilloscope(
    self: *UI,
    waveform: []const u8,
    color: SDL.Color,
) !void {
    const waveform_area = if (waveform.len > 0)
        SDL.Rectangle{
            .x = @as(i32, @intCast(texture_width - waveform.len)),
            .y = 0,
            .width = @intCast(waveform.len),
            .height = self.font.inline_font.waveform_max_height,
        }
    else
        SDL.Rectangle{
            .x = 0,
            .y = 0,
            .width = @intCast(texture_width),
            .height = self.font.inline_font.waveform_max_height,
        };

    try self.renderer.setColor(background_color);
    try self.renderer.fillRect(waveform_area);

    var waveform_points: [480]SDL.Point = undefined;
    for (0..waveform.len) |i| {
        waveform_points[i] = .{
            .x = @as(i32, @intCast(i)) + waveform_area.x,
            .y = @min(
                self.font.inline_font.waveform_max_height,
                waveform[i],
            ),
        };
    }

    try self.renderer.setColor(color);
    try self.renderer.drawPoints(waveform_points[0..waveform.len]);

    dirty = true;
}

pub fn render(self: *UI) !void {
    if (dirty) {
        dirty = false;
        try self.renderer.setTarget(null);
        try self.renderer.setColor(background_color);
        try self.renderer.clear();
        try self.renderer.copy(self.main_texture, null, null);
        self.renderer.present();
        try self.renderer.setTarget(self.main_texture);
    }
}

pub fn deinit(self: UI) void {
    std.log.debug("Deinit SDL UI, dirty={}", .{dirty});
    self.window.destroy();
    self.renderer.destroy();
    self.main_texture.destroy();
    self.font.deinit();
}

fn drawCube(self: UI) FxCube {
    const cube = FxCube.init(self.render(), background_color, texture_width, texture_height);
    dirty = true;
    return cube;
}

fn screenshot(self: UI) !void {
    const texture_info = try self.main_texture.query();
    const surface = try SDL.createRgbSurfaceWithFormat(@intCast(texture_info.width), @intCast(texture_info.height), texture_info.format);
    defer surface.destroy();
    try self.renderer.readPixels(null, @enumFromInt(surface.ptr.format.*.format), @ptrCast(surface.ptr.pixels), @intCast(surface.ptr.pitch));
    std.fs.cwd().deleteFile("screenshot.bmp") catch {};
    const result = SDL.c.SDL_SaveBMP(surface.ptr, "screenshot.bmp");
    if (result != 0) {
        const err = SDL.getError();
        if (err) |sdl_error| {
            std.log.err("Failed to save screenshot {s}", .{sdl_error});
        }
    }
}
