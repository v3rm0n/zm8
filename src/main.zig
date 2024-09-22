const std = @import("std");
const SDLUI = @import("sdl/ui.zig");
const M8 = @import("m8.zig");
const SDL = @import("sdl2");
const SDLAudio = @import("sdl/audio.zig");
const Slip = @import("slip.zig");
const Command = @import("command.zig");
const CommandHandler = @import("command_handler.zig");
const Config = @import("config.zig");

const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("Memory leak");
    }

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    var preferred_usb_device: ?[]u8 = null;
    if (args.len == 2 and std.mem.eql(u8, args[1], "--list")) {
        try M8.listDevices();
        return;
    }
    if (args.len == 3 and std.mem.eql(u8, args[1], "--dev")) {
        preferred_usb_device = args[2];
        std.log.info("Preferred device set to {s}", .{preferred_usb_device.?});
    }
    startWithSDL(allocator, preferred_usb_device) catch |err| {
        std.log.err("Error: {}", .{err});
    };
}

fn startWithSDL(allocator: std.mem.Allocator, preferred_usb_device: ?[]u8) !void {
    const config_file = try std.fs.cwd().openFile("config.ini", .{});
    defer config_file.close();

    const config = try Config.init(allocator, config_file.reader());
    defer config.deinit(allocator);

    var ui = try SDLUI.init(allocator, config.graphics.fullscreen, config.graphics.use_gpu);
    defer ui.deinit();

    var audio_device: ?SDLAudio = null;
    if (config.audio.audio_enabled) {
        audio_device = try SDLAudio.init(allocator, config.audio.audio_buffer_size, config.audio.audio_device_name);
    }
    defer if (audio_device) |*dev| dev.deinit();

    var m8 = try M8.init(
        allocator,
        if (audio_device) |dev| dev.ring_buffer else null,
        &.{ .ui = &ui },
        preferred_usb_device,
    );
    defer m8.deinit();

    std.log.debug("Enable display", .{});
    try m8.enableAndResetDisplay();

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
                        .r => try m8.resetDisplay(),
                        .@"return" => {
                            if (key_ev.modifiers.get(SDL.KeyModifierBit.left_alt)) {
                                try ui.toggleFullScreen();
                            }
                        },
                        else => try m8.handleKey(mapKey(key_ev.keycode), M8.KeyAction.down),
                    }
                },
                .key_up => |key_ev| {
                    switch (key_ev.keycode) {
                        else => try m8.handleKey(mapKey(key_ev.keycode), M8.KeyAction.up),
                    }
                },
                else => {},
            }
        }

        try m8.handleEvents();
        try ui.render();
    }
}

fn mapKey(key_code: SDL.Keycode) ?M8.Key {
    return switch (key_code) {
        .up => M8.Key.up,
        .down => M8.Key.down,
        .left => M8.Key.left,
        .right => M8.Key.right,
        else => null,
    };
}
