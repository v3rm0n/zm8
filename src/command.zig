const std = @import("std");

const CommandError = error{OutOfRange};

const Command = @This();

pub const CommandTag = enum(u8) {
    Rectangle = 0xFE,
    Character = 0xFD,
    Oscilloscope = 0xFC,
    Joypad = 0xFB,
    System = 0xFF,
};

const CommandLimits = struct { min: usize, max: usize };

fn getCommandLimits(cmd: CommandTag) CommandLimits {
    return switch (cmd) {
        .Rectangle => .{ .min = 5, .max = 12 },
        .Character => .{ .min = 12, .max = 12 },
        .Oscilloscope => .{ .min = 1 + 3, .max = 1 + 3 + 480 },
        .Joypad => .{ .min = 3, .max = 3 },
        .System => .{ .min = 6, .max = 6 },
    };
}

tag: CommandTag,
data: []u8,

fn init(tag: CommandTag, data: []u8) !Command {
    const limits = getCommandLimits(tag);
    if (data.len < limits.min or data.len > limits.max) {
        return error.OutOfRange;
    }
    return .{ .tag = tag, .data = data[1..] };
}

pub fn parseCommand(buffer: []u8) !Command {
    const commandTag: CommandTag = @enumFromInt(buffer[0]);
    std.log.debug("Command tag {}", .{commandTag});
    return Command.init(commandTag, buffer);
}
