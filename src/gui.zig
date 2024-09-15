const SDL = @import("sdl2");
const std = @import("std");
const Command = @import("command.zig");
const HardwareType = @import("command.zig").HardwareType;
const Position = @import("command.zig").Position;
const Color = @import("command.zig").Color;
const Size = @import("command.zig").Size;

const stdout = std.io.getStdOut().writer();

const texture_width = 320;
const texture_height = 240;

const M8Model = enum { V1, V2 };

var dirty: bool = true;
var background_color: SDL.Color = SDL.Color.black;
var m8_model: M8Model = M8Model.V1;

const GUI = @This();

window: SDL.Window,
renderer: SDL.Renderer,
main_texture: SDL.Texture,
full_screen: bool,

pub fn init(full_screen: bool) !GUI {
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

    return GUI{ .window = window, .renderer = renderer, .main_texture = main_texture, .full_screen = full_screen };
}

pub fn toggleFullScreen(gui: *GUI) void {
    gui.full_screen = !gui.full_screen;
    gui.window.setFullscreen(.{ .fullscreen = gui.full_screen });
    SDL.showCursor(true);
}

pub fn handleCommand(gui: *GUI, command: Command) !void {
    std.log.debug("Handling command {}", .{command});
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
            std.log.debug("Rectangle command", .{});
            try gui.drawRectangle(cmd.position, cmd.size, cmd.color);
        },
        .character => |cmd| {
            std.log.debug("Character command", .{});
            try gui.drawCharacter(cmd.character, cmd.position, cmd.foreground, cmd.background);
        },
        .joypad => {
            std.log.debug("Joypad command", .{});
        },
        .oscilloscope => |cmd| {
            std.log.debug("Oscilloscope command", .{});
            try gui.drawOscilloscope(cmd.waveform, cmd.color);
        },
    }
}

fn setModel(model: M8Model) void {
    m8_model = model;
}

fn drawCharacter(
    gui: *GUI,
    character: u16,
    position: Position,
    foreground: Color,
    background: Color,
) !void {
    _ = gui;
    _ = character;
    _ = position;
    _ = foreground;
    _ = background;
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

fn drawOscilloscope(
    gui: *GUI,
    waveform: []u8,
    color: Color,
) !void {
    _ = gui;
    _ = waveform;
    _ = color;
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
    SDL.quit();
}
