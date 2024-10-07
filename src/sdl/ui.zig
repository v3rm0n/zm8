const SDL = @import("sdl2");
const std = @import("std");
const SDLFont = @import("font.zig");

const stdout = std.io.getStdOut().writer();

const texture_width = 320;
const texture_height = 240;

var dirty: bool = true;

const UI = @This();

window: SDL.Window,
renderer: SDL.Renderer,
main_texture: SDL.Texture,
full_screen: bool,
font: SDLFont,
background_color: SDL.Color = .black,

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
    try renderer.setLogicalSize(texture_width, texture_height);

    const main_texture = try SDL.createTexture(
        renderer,
        SDL.PixelFormatEnum.argb8888,
        SDL.Texture.Access.target,
        texture_width,
        texture_height,
    );

    try renderer.setTarget(main_texture);

    try renderer.setColor(.black);
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

pub fn toggleFullScreen(self: *UI) !void {
    self.full_screen = !self.full_screen;
    try self.window.setFullscreen(if (self.full_screen) .fullscreen else .default);
    _ = try SDL.showCursor(true);
}

pub fn setFont(self: *UI, v2: bool, large: bool) !void {
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
    width: u16,
    height: u16,
    color: SDL.Color,
) !void {
    const y = position.y + self.font.inline_font.screen_offset_y;
    const rectangle = SDL.Rectangle{
        .x = position.x,
        .y = y,
        .width = width,
        .height = height,
    };

    if (rectangle.x == 0 and rectangle.y <= 0 and rectangle.width == texture_width and rectangle.height >= texture_height) {
        std.log.debug("Setting background color", .{});
        self.setBackground(color);
    }

    try self.renderer.setColor(color);
    try self.renderer.fillRect(rectangle);
    dirty = true;
}

fn setBackground(self: *UI, color: SDL.Color) void {
    self.background_color = color;
    dirty = true;
}

var waveform_clear = false;
var previous_waveform_len: usize = 0;

pub fn drawOscilloscope(
    self: *UI,
    waveform: []const u8,
    color: SDL.Color,
) !void {
    if (!(waveform_clear and waveform.len == 0)) {
        const waveform_rectangle = if (waveform.len > 0)
            SDL.Rectangle{
                .x = texture_width - @as(i32, @intCast(waveform.len)),
                .y = 0,
                .width = @intCast(waveform.len),
                .height = self.font.inline_font.waveform_max_height,
            }
        else
            SDL.Rectangle{
                .x = texture_width - @as(i32, @intCast(previous_waveform_len)),
                .y = 0,
                .width = @intCast(previous_waveform_len),
                .height = self.font.inline_font.waveform_max_height + 1,
            };

        try self.renderer.setColor(self.background_color);
        try self.renderer.fillRect(waveform_rectangle);
        try self.renderer.setColor(color);

        var waveform_points: [480]SDL.Point = undefined;

        for (0..waveform.len) |i| {
            waveform_points[i] = SDL.Point{
                .x = @as(i32, @intCast(i)) + waveform_rectangle.x,
                .y = @min(
                    self.font.inline_font.waveform_max_height,
                    waveform[i],
                ),
            };
        }

        try self.renderer.drawPoints(waveform_points[0..waveform.len]);

        waveform_clear = waveform.len == 0;

        dirty = true;
    }
}

pub fn render(self: *UI) !void {
    if (dirty) {
        dirty = false;
        try self.renderer.setTarget(null);
        try self.renderer.setColor(self.background_color);
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

test "draws characters" {
    try SDL.init(.{ .video = true });
    defer SDL.quit();

    var ui = try UI.init(false, true);
    try ui.setFont(false, false);
    defer ui.deinit();
    var location: SDL.Point = .{ .x = 0, .y = 0 };
    try ui.drawCharacter('H', location, .red, .green);
    location.x += ui.font.inline_font.glyph_x + 1;
    try ui.drawCharacter('e', location, .red, .green);
    location.x += ui.font.inline_font.glyph_x + 1;
    try ui.drawCharacter('l', location, .red, .green);
    location.x += ui.font.inline_font.glyph_x + 1;
    try ui.drawCharacter('l', location, .red, .green);
    location.x += ui.font.inline_font.glyph_x + 1;
    try ui.drawCharacter('o', location, .red, .green);
    try ui.render();
}

test "draws rectangles" {
    try SDL.init(.{ .video = true });
    defer SDL.quit();
    var ui = try UI.init(false, true);
    defer ui.deinit();
    try ui.drawRectangle(.{ .x = 100, .y = 100 }, 100, 100, .red);
    try ui.render();
}

test "draws oscilloscope" {
    try SDL.init(.{ .video = true });
    defer SDL.quit();
    var ui = try UI.init(false, true);
    defer ui.deinit();
    try ui.drawOscilloscope(
        &[_]u8{ 10, 10, 11, 11, 12, 13, 14, 15, 16, 16, 13, 13, 12, 12, 10, 9, 8, 7, 7, 7, 8, 9, 11, 14, 17, 19, 20, 20, 18, 15, 13, 12, 11, 10, 9, 10, 11, 13, 14, 14, 14, 13, 11, 9, 8, 7, 8, 9, 10, 12, 15, 17, 19, 19, 19, 18, 16, 14, 13, 12, 11, 10, 10, 10, 11, 11, 11, 10, 9, 8, 8, 9, 10, 12, 14, 16, 18, 20, 20, 19, 18, 16, 13, 11, 10, 9, 9, 9, 9, 10, 11, 12, 13, 13, 12, 10, 9, 9, 9, 10, 12, 13, 15, 17, 19, 20, 20, 19, 17, 15, 13, 11, 10, 8, 7, 6, 7, 8, 9, 10, 11, 12, 12, 13, 14, 15, 16, 16, 16, 16, 16, 16, 16, 16, 14, 13, 11, 10, 9, 9, 8, 8, 9, 10, 11, 12, 12, 13, 13, 13, 13, 13, 14, 14, 14, 15, 16, 17, 18, 18, 17, 15, 13, 10, 8, 6, 5, 5, 5, 6, 8, 11, 13, 15, 17, 18, 18, 17, 16, 15, 14, 13, 12, 13, 14, 14, 14, 13, 13, 11, 10, 8, 8, 7, 7, 7, 9, 11, 13, 15, 16, 17, 17, 16, 15, 15, 14, 14, 14, 14, 15, 15, 15, 14, 12, 10, 8, 6, 5, 5, 5, 6, 9, 12, 15, 17, 20, 21, 20, 18, 16, 14, 12, 11, 11, 10, 11, 12, 13, 13, 13, 12, 11, 9, 8, 8, 8, 8, 9, 10, 13, 16, 18, 19, 19, 17, 16, 15, 14, 14, 13, 12, 11, 11, 11, 11, 10, 10, 9, 7, 7, 7, 8, 9, 11, 13, 16, 18, 19, 20, 19, 18, 16, 14, 12, 11, 10, 9, 9, 9, 10, 11, 12, 12, 12, 11, 10, 10, 9, 10, 11, 12, 13, 15, 17, 18, 19, 19, 18, 17, 16, 14, 12, 10, 9, 7, 7, 8, 8, 9 },
        .red,
    );
    try ui.render();
}
