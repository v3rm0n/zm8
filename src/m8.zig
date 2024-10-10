const std = @import("std");
const Command = @import("command.zig");
const Slip = @import("slip.zig").Slip(1024);

pub const Key = enum(u8) {
    edit = 1,
    option = 1 << 1,
    right = 1 << 2,
    play = 1 << 3,
    shift = 1 << 4,
    down = 1 << 5,
    up = 1 << 6,
    left = 1 << 7,
    _,
};

pub const KeyAction = enum(u8) {
    down = 0,
    up = 1,
};

const M8 = @This();

allocator: std.mem.Allocator,
serial_writer: std.io.AnyWriter,
serial_reader: std.io.AnyReader,
slip: *Slip,

pub fn init(
    allocator: std.mem.Allocator,
    serial_writer: std.io.AnyWriter,
    serial_reader: std.io.AnyReader,
) !M8 {
    std.log.debug("Initialising M8", .{});
    const slip = try allocator.create(Slip);
    errdefer allocator.destroy(slip);
    slip.* = Slip.init();
    return .{
        .allocator = allocator,
        .serial_writer = serial_writer,
        .serial_reader = serial_reader,
        .slip = slip,
    };
}

pub fn readCommands(self: *M8) ![]*Command {
    var packages = try self.slip.readFromReader(self.allocator, self.serial_reader);
    defer packages.deinit();

    var list = std.ArrayList(*Command).init(self.allocator);
    defer list.deinit();

    while (packages.next()) |pkg| {
        try list.append(try Command.parseCommand(self.allocator, pkg));
    }
    return try list.toOwnedSlice();
}

pub fn resetDisplay(self: *M8) !void {
    std.log.info("Resetting display", .{});
    const reset = [_]u8{'R'};
    _ = try self.serial_writer.write(&reset);
}

pub fn enableAndResetDisplay(self: *M8) !void {
    std.log.info("Enabling and resetting display", .{});
    const reset = [_]u8{'E'};
    _ = try self.serial_writer.write(&reset);
    std.Thread.sleep(5 * 1000);
    try self.resetDisplay();
}

pub fn disconnect(self: *M8) !void {
    std.log.info("Disconnecting", .{});
    const reset = [_]u8{'D'};
    _ = try self.serial_writer.write(&reset);
}

pub fn handleKey(self: *M8, opt_key: ?Key, action: KeyAction) !void {
    if (opt_key) |key| {
        std.log.debug("Handling key {}", .{key});
        switch (key) {
            .edit, .option, .right, .play, .shift, .down, .up, .left => {
                const KeyState = struct {
                    var state: u8 = 0;
                };
                switch (action) {
                    .down => KeyState.state |= @intFromEnum(key),
                    .up => KeyState.state &= ~@intFromEnum(key),
                }
                _ = try self.sendController(KeyState.state);
            },
            else => {},
        }
    }
}

pub fn sendController(self: *M8, input: u8) !void {
    std.log.info("Sending controller, input={}", .{input});
    _ = try self.serial_writer.write(&[_]u8{ 'C', input });
}

pub fn sendKeyjazz(self: *M8, note: u8, velocity: u8) !void {
    std.log.info("Sending keyjazz. Note={}, velocity={}", .{ note, velocity });
    _ = try self.serial_writer.write(&[_]u8{ 'K', note, if (velocity > 0x7F) 0x7F else velocity });
}

pub fn deinit(self: *M8) void {
    std.log.debug("Deiniting M8", .{});
    self.disconnect() catch |err| {
        std.log.err("Failed to disconnect: {}", .{err});
    };
    self.allocator.destroy(self.slip);
}
