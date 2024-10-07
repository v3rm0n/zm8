const std = @import("std");

const CommandError = error{OutOfRange};

const Command = @This();

pub const M8Model = enum { V1, V2 };

pub const CommandTag = enum(u8) {
    joypad = 0xFB, //251
    oscilloscope = 0xFC, //252
    character = 0xFD, //253
    rectangle = 0xFE, //254
    system = 0xFF, //255
};

pub const CommandData = union(CommandTag) {
    joypad: struct {},
    oscilloscope: struct {
        color: Color,
        waveform: []const u8,
    },
    character: struct {
        character: u8,
        position: Position,
        foreground: Color,
        background: Color,
    },
    rectangle: struct {
        position: Position,
        size: Size,
        color: Color,
    },
    system: struct {
        hardware: HardwareType,
        version: Version,
        fontMode: FontMode,
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

pub const FontMode = enum(u8) {
    small = 0,
    large = 1,
};

allocator: std.mem.Allocator,
data: CommandData,

pub fn parseCommand(allocator: std.mem.Allocator, buffer: []const u8) !Command {
    const commandTag: CommandTag = @enumFromInt(buffer[0]);
    return Command.init(allocator, commandTag, buffer);
}

fn init(allocator: std.mem.Allocator, tag: CommandTag, data: []const u8) !Command {
    const limits = getCommandLimits(tag);
    if (data.len < limits.min or data.len > limits.max) {
        return error.OutOfRange;
    }
    return switch (tag) {
        .rectangle => .{
            .allocator = allocator,
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
            .allocator = allocator,
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
            .allocator = allocator,
            .data = .{
                .oscilloscope = .{
                    .color = .{
                        .r = data[1],
                        .g = data[2],
                        .b = data[3],
                    },
                    .waveform = try allocator.dupe(u8, data[4..]),
                },
            },
        },
        .joypad => .{
            .allocator = allocator,
            .data = .{
                .joypad = .{},
            },
        },
        .system => .{
            .allocator = allocator,
            .data = .{
                .system = .{
                    .hardware = @enumFromInt(data[1]),
                    .version = .{
                        .major = data[2],
                        .minor = data[3],
                        .patch = data[4],
                    },
                    .fontMode = @enumFromInt(data[5]),
                },
            },
        },
    };
}

pub fn deinit(self: Command) void {
    switch (self.data) {
        .oscilloscope => self.allocator.free(self.data.oscilloscope.waveform),
        else => return,
    }
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

fn decodeU16(data: []const u8, start: usize) u16 {
    return @as(u16, data[start]) | (@as(u16, data[start + 1]) << 8);
}
