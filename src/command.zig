const std = @import("std");

const CommandError = error{OutOfRange};

const Command = @This();

pub const M8Model = enum { V1, V2 };

pub const CommandTag = enum(u8) {
    rectangle = 0xFE,
    character = 0xFD,
    oscilloscope = 0xFC,
    joypad = 0xFB,
    system = 0xFF,
};

pub const CommandData = union(CommandTag) {
    rectangle: struct {
        position: Position,
        size: Size,
        color: Color,
    },
    character: struct {
        character: u8,
        position: Position,
        foreground: Color,
        background: Color,
    },
    oscilloscope: struct {
        color: Color,
        waveform: []const u8,
    },
    joypad: struct {},
    system: struct {
        hardware: HardwareType,
        version: Version,
    },
};

const CommandLimits = struct { min: usize, max: usize };

fn getCommandLimits(cmd: CommandTag) CommandLimits {
    return switch (cmd) {
        .rectangle => .{ .min = 5, .max = 12 },
        .character => .{ .min = 12, .max = 12 },
        .oscilloscope => .{ .min = 1 + 3, .max = 1 + 3 + 480 },
        .joypad => .{ .min = 3, .max = 3 },
        .system => .{ .min = 6, .max = 6 },
    };
}

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn eql(self: Color, other: ?Color) bool {
        if (other) |value| {
            return self.r == value.r and self.g == value.g and self.b == value.b;
        }
        return false;
    }
};

pub const Position = struct {
    x: u16,
    y: u16,
};

pub const Size = struct {
    width: u16,
    height: u16,
};

pub const Version = struct {
    major: u8,
    minor: u8,
    patch: u8,
};

pub const HardwareType = enum(u8) {
    Headless,
    BetaM8,
    ProductionM8,
    ProductionM8Model2,
};

data: CommandData,

fn init(tag: CommandTag, data: []const u8) !Command {
    const limits = getCommandLimits(tag);
    if (data.len < limits.min or data.len > limits.max) {
        return error.OutOfRange;
    }
    return switch (tag) {
        .rectangle => .{
            .data = .{
                .rectangle = .{
                    .position = .{
                        .x = decodeU16(data, 1),
                        .y = decodeU16(data, 3),
                    },
                    .size = rectangleSize(data),
                    .color = rectangleColor(data),
                },
            },
        },
        .character => .{
            .data = .{
                .character = .{
                    .character = data[1],
                    .position = .{
                        .x = decodeU16(data, 2),
                        .y = decodeU16(data, 4),
                    },
                    .foreground = .{
                        .r = data[6],
                        .g = data[7],
                        .b = data[8],
                    },
                    .background = .{
                        .r = data[9],
                        .g = data[10],
                        .b = data[11],
                    },
                },
            },
        },
        .oscilloscope => .{
            .data = .{
                .oscilloscope = .{
                    .color = .{
                        .r = data[1],
                        .g = data[2],
                        .b = data[3],
                    },
                    .waveform = data[4..],
                },
            },
        },
        .joypad => .{
            .data = .{
                .joypad = .{},
            },
        },
        .system => .{
            .data = .{
                .system = .{
                    .hardware = @enumFromInt(data[1]),
                    .version = .{
                        .minor = data[2],
                        .major = data[3],
                        .patch = data[4],
                    },
                },
            },
        },
    };
}

fn rectangleSize(data: []const u8) Size {
    return switch (data.len) {
        5, 8 => .{
            .width = 1,
            .height = 1,
        },
        else => .{
            .width = decodeU16(data, 5),
            .height = decodeU16(data, 7),
        },
    };
}

fn rectangleColor(data: []const u8) Color {
    return switch (data.len) {
        5, 9 => .{
            .r = 0,
            .g = 0,
            .b = 0,
        },
        8 => .{
            .r = data[5],
            .g = data[6],
            .b = data[7],
        },
        else => .{
            .r = data[9],
            .g = data[10],
            .b = data[11],
        },
    };
}

pub fn parseCommand(buffer: []const u8) !Command {
    std.log.debug("YO {}", .{buffer[0]});
    const commandTag: CommandTag = @enumFromInt(buffer[0]);
    return Command.init(commandTag, buffer);
}

fn decodeU16(data: []const u8, start: usize) u16 {
    return @as(u16, data[start]) | (@as(u16, data[start + 1]) << 8);
}
