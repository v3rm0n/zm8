const std = @import("std");
const UI = @import("sdl/ui.zig");
const Command = @import("command.zig");
const SDL = @import("sdl2");
const M8 = @import("m8.zig");
const CommandHandler = @import("command_handler.zig");

const stdout = std.io.getStdOut().writer();

const SDLHandler = @This();

ui: *UI,

pub fn handler(self: *SDLHandler) CommandHandler {
    return .{
        .ptr = self,
        .startFn = start,
        .handleCommandFn = handleCommand,
    };
}

fn start(ptr: *anyopaque, m8: *M8) !void {
    const self: *SDLHandler = @ptrCast(@alignCast(ptr));
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
                                try self.ui.toggleFullScreen();
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
        try self.ui.render();
    }
    std.log.debug("End of main loop", .{});
}

fn handleCommand(ptr: *anyopaque, command: Command) !void {
    const self: *SDLHandler = @ptrCast(@alignCast(ptr));
    switch (command.data) {
        .system => |cmd| {
            try stdout.print("** Hardware info ** Device type: {}, Firmware ver {}.{}.{}\n", .{
                cmd.hardware,
                cmd.version.major,
                cmd.version.minor,
                cmd.version.patch,
            });
        },
        .rectangle => |cmd| {
            try self.ui.drawRectangle(
                .{ .x = cmd.position.x, .y = cmd.position.y },
                cmd.size.width,
                cmd.size.height,
                .{ .r = cmd.color.r, .g = cmd.color.g, .b = cmd.color.b },
            );
        },
        .character => |cmd| {
            try self.ui.drawCharacter(
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
            try self.ui.drawOscilloscope(cmd.waveform, .{ .r = cmd.color.r, .g = cmd.color.g, .b = cmd.color.b });
        },
    }
}

fn mapKey(key_code: SDL.Keycode) ?M8.Key {
    return switch (key_code) {
        .up => M8.Key.up,
        .down => M8.Key.down,
        .left => M8.Key.left,
        .right => M8.Key.right,
        .z => M8.Key.option,
        .x => M8.Key.edit,
        .space => M8.Key.play,
        .left_shift => M8.Key.shift,
        else => null,
    };
}
