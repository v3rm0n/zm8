const SDL = @import("sdl2");
const std = @import("std");
const SDLFont = @import("font.zig");

const stdout = std.io.getStdOut().writer();

const texture_width = 320;
const texture_height = 240;

var dirty: bool = true;
var background_color: SDL.Color = SDL.Color.black;

const UI = @This();

allocator: std.mem.Allocator,
window: SDL.Window,
renderer: SDL.Renderer,
main_texture: SDL.Texture,
full_screen: bool,
font: SDLFont,

pub fn init(allocator: std.mem.Allocator, full_screen: bool, use_gpu: bool) !UI {
    std.log.debug("Initialising SDL UI", .{});
    try SDL.init(SDL.InitFlags.everything);

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

    try renderer.setColor(background_color);
    try renderer.clear();

    dirty = true;

    return .{
        .allocator = allocator,
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
        background_color = color;
    }

    try self.renderer.setColor(color);
    try self.renderer.fillRect(rectangle);
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
        try self.renderer.setColor(background_color);
        try self.renderer.fillRect(waveform_rectangle);
        try self.renderer.setColor(color);

        var waveform_points = try self.allocator.alloc(SDL.Point, waveform.len);
        defer self.allocator.free(waveform_points);

        for (0..waveform.len) |i| {
            waveform_points[i] = SDL.Point{
                .x = @as(i32, @intCast(i)) + waveform_rectangle.x,
                .y = @min(
                    self.font.inline_font.waveform_max_height,
                    waveform[i],
                ),
            };
        }

        try self.renderer.drawPoints(waveform_points);

        waveform_clear = waveform.len == 0;

        dirty = true;
    }
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
    std.log.debug("Deinit SDL UI", .{});
    self.window.destroy();
    self.renderer.destroy();
    self.main_texture.destroy();
    self.font.deinit();
    SDL.quit();
}
