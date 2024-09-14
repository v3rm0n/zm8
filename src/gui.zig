const SDL = @import("sdl2");
const std = @import("std");
const Command = @import("command.zig");
const CommandTag = @import("command.zig").CommandTag;

const stdout = std.io.getStdOut().writer();

const texture_width = 320;
const texture_height = 240;

const M8Model = enum { V1, V2 };

const M8HardwareType = enum(u8) {
    Headless,
    BetaM8,
    ProductionM8,
    ProductionM8Model2,
};

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
    _ = gui;
    std.log.debug("Handling command {}", .{command});
    switch (command.tag) {
        CommandTag.System => {
            const hardware_type: M8HardwareType = @enumFromInt(command.data[1]);
            try stdout.print("** Hardware info ** Device type: {}, Firmware ver {}.{}.{}\n", .{
                hardware_type,
                command.data[2],
                command.data[3],
                command.data[4],
            });
            if (hardware_type == M8HardwareType.ProductionM8Model2) {
                m8_model = M8Model.V2;
            } else {
                m8_model = M8Model.V1;
            }
        },
        CommandTag.Rectangle => {
            std.log.debug("Rectangle command", .{});
            drawRectangle();
        },
        CommandTag.Character => {
            std.log.debug("Character command", .{});
            drawCharacter();
        },
        CommandTag.Joypad => {
            std.log.debug("Joypad command", .{});
        },
        CommandTag.Oscilloscope => {
            std.log.debug("Oscilloscope command", .{});
        },
    }
}

pub fn drawCharacter() void {}

pub fn drawRectangle() void {}

pub fn render(gui: *GUI) void {
    if (gui.dirty) {
        gui.dirty = 0;
        gui.renderer.setTarget(null);
        gui.renderer.setColorRGBA(gui.background_color);
        gui.renderer.clear();
        gui.renderer.copy(gui.main_texture, null, null);
        gui.renderer.present();
        gui.renderer.setTarget(gui.main_texture);
    }
}

pub fn deinit(gui: GUI) void {
    std.log.debug("Deinit GUI", .{});
    gui.window.destroy();
    gui.renderer.destroy();
    gui.main_texture.destroy();
    SDL.quit();
}
