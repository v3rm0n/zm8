const SDL = @import("sdl2");
const std = @import("std");
const Command = @import("command.zig");
const HardwareType = @import("command.zig").HardwareType;
const Position = @import("command.zig").Position;
const Color = @import("command.zig").Color;
const Size = @import("command.zig").Size;
const M8Model = @import("command.zig").M8Model;
const Font = @import("font.zig");

const stdout = std.io.getStdOut().writer();

const texture_width = 320;
const texture_height = 240;

var dirty: bool = true;
var background_color: SDL.Color = SDL.Color.black;
var m8_model: M8Model = M8Model.V1;

const GUI = @This();

allocator: std.mem.Allocator,
window: SDL.Window,
renderer: SDL.Renderer,
main_texture: SDL.Texture,
full_screen: bool,
font: Font,

pub fn init(allocator: std.mem.Allocator, full_screen: bool) !GUI {
    std.log.debug("Initialising GUI", .{});
    try SDL.init(SDL.InitFlags.everything);

    const window = try SDL.createWindow(
        "zm8",
        .{ .centered = {} },
        .{ .centered = {} },
        texture_width * 2,
        texture_height * 2,
        .{ .vis = .shown, .context = .opengl, .resizable = true, .dim = if (full_screen) .fullscreen else .default },
    );

    const renderer = try SDL.createRenderer(window, null, .{ .accelerated = true });
    try renderer.setLogicalSize(texture_width, texture_height);

    const main_texture = try SDL.createTexture(renderer, SDL.PixelFormatEnum.argb8888, SDL.Texture.Access.target, texture_width, texture_height);
    try renderer.setTarget(main_texture);

    try renderer.setColor(background_color);
    try renderer.clear();

    dirty = true;

    return GUI{
        .allocator = allocator,
        .window = window,
        .renderer = renderer,
        .main_texture = main_texture,
        .full_screen = full_screen,
        .font = try Font.init(renderer, m8_model),
    };
}

pub fn toggleFullScreen(gui: *GUI) void {
    gui.full_screen = !gui.full_screen;
    gui.window.setFullscreen(.{ .fullscreen = gui.full_screen });
    SDL.showCursor(true);
}

pub fn handleCommand(gui: *GUI, command: Command) !void {
    switch (command.data) {
        .system => |cmd| {
            try stdout.print("** Hardware info ** Device type: {}, Firmware ver {}.{}.{}\n", .{
                cmd.hardware,
                cmd.version.major,
                cmd.version.minor,
                cmd.version.patch,
            });
            if (cmd.hardware == HardwareType.ProductionM8Model2) {
                setModel(M8Model.V2);
            } else {
                setModel(M8Model.V1);
            }
        },
        .rectangle => |cmd| {
            try gui.drawRectangle(cmd.position, cmd.size, cmd.color);
        },
        .character => |cmd| {
            try gui.drawCharacter(cmd.character, cmd.position, cmd.foreground, cmd.background);
        },
        .joypad => {
            std.log.debug("Joypad command", .{});
        },
        .oscilloscope => |cmd| {
            try gui.drawOscilloscope(cmd.waveform, cmd.color);
        },
    }
}

fn setModel(model: M8Model) void {
    m8_model = model;
}

fn drawCharacter(
    self: *GUI,
    character: u8,
    position: Position,
    foreground: Color,
    background: Color,
) !void {
    try self.font.draw(self.renderer, character, position, foreground, background);
    dirty = true;
}

fn drawRectangle(
    gui: *GUI,
    position: Position,
    size: Size,
    color: Color,
) !void {
    const rectangle = SDL.Rectangle{
        .x = position.x,
        .y = position.y,
        .width = size.width,
        .height = size.height,
    };

    if (position.x == 0 and position.y == 0 and size.width == texture_width and size.height == texture_height) {
        std.log.debug("Setting background color", .{});
        background_color = SDL.Color{
            .r = color.r,
            .g = color.g,
            .b = color.b,
            .a = 0xFF,
        };
    }

    try gui.renderer.setColorRGBA(color.r, color.g, color.b, 0xFF);
    try gui.renderer.fillRect(rectangle);
    dirty = true;
}

var waveform_clear = false;
var previous_waveform_len: usize = 0;

fn drawOscilloscope(
    gui: *GUI,
    waveform: []u8,
    color: Color,
) !void {
    if (!(waveform_clear and waveform.len == 0)) {
        const waveform_rectangle = if (waveform.len > 0)
            SDL.Rectangle{
                .x = texture_width - @as(i32, @intCast(waveform.len)),
                .y = 0,
                .width = @intCast(waveform.len),
                .height = gui.font.inline_font.waveform_max_height,
            }
        else
            SDL.Rectangle{
                .x = texture_width - @as(i32, @intCast(previous_waveform_len)),
                .y = 0,
                .width = @intCast(previous_waveform_len),
                .height = gui.font.inline_font.waveform_max_height + 1,
            };
        try gui.renderer.setColorRGBA(background_color.r, background_color.g, background_color.b, background_color.a);
        try gui.renderer.fillRect(waveform_rectangle);
        try gui.renderer.setColorRGBA(color.r, color.g, color.b, 0xFF);

        var waveform_points = try gui.allocator.alloc(SDL.Point, waveform.len);
        defer gui.allocator.free(waveform_points);

        for (0..waveform.len) |i| {
            waveform_points[i] = SDL.Point{
                .x = @as(i32, @intCast(i)) + waveform_rectangle.x,
                .y = @min(
                    gui.font.inline_font.waveform_max_height,
                    waveform[i],
                ),
            };
        }

        try gui.renderer.drawPoints(waveform_points);

        waveform_clear = waveform.len == 0;

        dirty = true;
    }
}

pub fn render(gui: *GUI) !void {
    if (dirty) {
        dirty = false;
        try gui.renderer.setTarget(null);
        try gui.renderer.setColor(background_color);
        try gui.renderer.clear();
        try gui.renderer.copy(gui.main_texture, null, null);
        gui.renderer.present();
        try gui.renderer.setTarget(gui.main_texture);
    }
}

pub fn deinit(gui: GUI) void {
    std.log.debug("Deinit GUI", .{});
    gui.window.destroy();
    gui.renderer.destroy();
    gui.main_texture.destroy();
    gui.font.deinit();
    SDL.quit();
}
