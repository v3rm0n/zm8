const std = @import("std");
const UI = @import("sdl/ui.zig");
const Command = @import("command.zig");
const SDL = @import("sdl2");
const M8 = @import("m8.zig");
const Config = @import("config.zig");
const SDLUI = @import("sdl/ui.zig");
const SDLAudio = @import("sdl/audio.zig");
const zusb = @import("zusb");

const stdout = std.io.getStdOut().writer();

const SDLHandler = @This();

ui: *UI,

pub fn start(allocator: std.mem.Allocator, preferred_usb_device: ?[]u8) !void {
    std.log.debug("Starting with SDL UI", .{});
    const config = readConfig(allocator) catch |err| blk: {
        std.log.err("Failed to read config file: {}\n", .{err});
        break :blk Config.default(allocator);
    };
    defer config.deinit();

    try SDL.init(SDL.InitFlags.everything);
    defer SDL.quit();

    var ui = try SDLUI.init(config.graphics.fullscreen, config.graphics.use_gpu);
    defer ui.deinit();

    var audio_device: ?SDLAudio = null;
    if (config.audio.audio_enabled) {
        audio_device = try SDLAudio.init(allocator, config.audio.audio_buffer_size, config.audio.audio_device_name);
    }
    defer if (audio_device) |*dev| dev.deinit();
    const audio_buffer = if (audio_device) |dev| dev.audio_buffer else null;

    var usb_context = try zusb.Context.init();
    defer usb_context.deinit();

    var m8 = try M8.init(
        allocator,
        audio_buffer,
        preferred_usb_device,
        &usb_context,
    );
    defer m8.deinit();

    const m8_start = try m8.start();
    defer m8_start.deinit();

    std.log.debug("Enable display", .{});
    try m8.enableAndResetDisplay();

    try startMainLoop(&ui, &m8, config.graphics.idle_ms);
}

fn readConfig(allocator: std.mem.Allocator) !Config {
    const config_file = try std.fs.cwd().openFile("config.ini", .{});
    defer config_file.close();

    return try Config.init(allocator, config_file.reader());
}

fn startMainLoop(ui: *SDLUI, m8: *M8, idle_ms: u32) !void {
    std.log.info("Starting main loop", .{});
    mainLoop: while (true) {
        while (SDL.pollEvent()) |ev| {
            switch (ev) {
                .quit => break :mainLoop,
                .key_down => |key_ev| {
                    if (key_ev.is_repeat) {
                        break;
                    }
                    switch (key_ev.keycode) {
                        .f4 => {
                            if (key_ev.modifiers.get(.left_alt)) {
                                break :mainLoop;
                            }
                        },
                        .r => try m8.resetDisplay(),
                        .@"return" => {
                            if (key_ev.modifiers.get(.left_alt)) {
                                try ui.toggleFullScreen();
                            }
                        },
                        else => try m8.handleKey(mapKey(key_ev.keycode), .down),
                    }
                },
                .key_up => |key_ev| {
                    switch (key_ev.keycode) {
                        else => try m8.handleKey(mapKey(key_ev.keycode), .up),
                    }
                },
                else => {},
            }
        }

        while (try m8.popCommand()) |command| {
            defer command.deinit();
            try handleCommand(ui, command);
        }

        try ui.render();
        SDL.delay(idle_ms);
    }
    std.log.debug("End of main loop", .{});
}

fn handleCommand(ui: *SDLUI, command: *Command) !void {
    switch (command.data) {
        .system => |cmd| {
            try stdout.print("** Hardware info ** Device type: {}, Firmware ver {}.{}.{}\n", .{
                cmd.hardware,
                cmd.version.major,
                cmd.version.minor,
                cmd.version.patch,
            });
            if (cmd.hardware == .ProductionM8Model2) {
                try ui.adjustSize(480, 320);
            } else {
                try ui.adjustSize(320, 240);
            }
            try ui.setFont(cmd.hardware == .ProductionM8Model2, cmd.fontMode == .large);
        },
        .rectangle => |cmd| {
            try ui.drawRectangle(
                .{ .x = cmd.position.x, .y = cmd.position.y },
                cmd.size.width,
                cmd.size.height,
                .{ .r = cmd.color.r, .g = cmd.color.g, .b = cmd.color.b },
            );
        },
        .character => |cmd| {
            try ui.drawCharacter(
                cmd.character,
                .{ .x = cmd.position.x, .y = cmd.position.y },
                .{ .r = cmd.foreground.r, .g = cmd.foreground.g, .b = cmd.foreground.b },
                .{ .r = cmd.background.r, .g = cmd.background.g, .b = cmd.background.b },
            );
        },
        .joypad => {
            std.log.debug("Joypad command", .{});
        },
        .oscilloscope => |cmd| {
            try ui.drawOscilloscope(cmd.waveform, .{ .r = cmd.color.r, .g = cmd.color.g, .b = cmd.color.b });
        },
    }
}

//TODO: handle config.ini
fn mapKey(key_code: SDL.Keycode) ?M8.Key {
    return switch (key_code) {
        .up => .up,
        .down => .down,
        .left => .left,
        .right => .right,
        .z => .option,
        .x => .edit,
        .space => .play,
        .left_shift => .shift,
        else => null,
    };
}
