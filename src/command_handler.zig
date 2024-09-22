const std = @import("std");
const UI = @import("sdl/ui.zig");
const Command = @import("command.zig");

const stdout = std.io.getStdOut().writer();

const Self = @This();

ui: *UI,

pub fn handleCommand(self: *const Self, command: Command) !void {
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
