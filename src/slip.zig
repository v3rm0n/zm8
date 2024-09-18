const std = @import("std");

const SlipByte = enum(u8) {
    end = 0xC0,
    esc = 0xDB,
    esc_end = 0xDC,
    esc_esc = 0xDD,
    _,
};

const Handler = *const fn (buffer: []u8, user_data: *const anyopaque) bool;

const slip_error = error{ BufferOverflow, UnknownEscapedByte, InvalidPacket };

const SlipState = enum { normal, escaped };

const Slip = @This();

allocator: std.mem.Allocator,
buffer: []u8,
size: usize = 0,
handler: Handler,
state: SlipState = SlipState.normal,
user_data: *const anyopaque,

pub fn init(
    allocator: std.mem.Allocator,
    buffer_size: usize,
    comptime handler: Handler,
    user_data: *const anyopaque,
) !Slip {
    const buffer = try allocator.alloc(u8, buffer_size);
    errdefer allocator.free(buffer);
    return Slip{ .allocator = allocator, .buffer = buffer, .handler = handler, .user_data = user_data };
}

pub fn deinit(self: *Slip) void {
    self.allocator.free(self.buffer);
}

pub fn readAll(self: *Slip, bytes: []const u8) slip_error!void {
    for (bytes) |byte| {
        try self.read(@enumFromInt(byte));
    }
}

fn read(self: *Slip, byte: SlipByte) slip_error!void {
    switch (self.state) {
        .normal => switch (byte) {
            .end => {
                defer self.reset();
                if (!self.handler(self.buffer[0..self.size], self.user_data)) {
                    return slip_error.InvalidPacket;
                }
            },
            .esc => self.state = .escaped,
            else => try self.byteToBuffer(byte),
        },
        .escaped => {
            switch (byte) {
                .esc_end => try self.byteToBuffer(.end),
                .esc_esc => try self.byteToBuffer(.esc),
                else => {
                    defer self.reset();
                    return slip_error.UnknownEscapedByte;
                },
            }
            self.state = .normal;
        },
    }
}

fn reset(slip: *Slip) void {
    slip.state = .normal;
    slip.size = 0;
}

fn byteToBuffer(slip: *Slip, byte: SlipByte) slip_error!void {
    if (slip.size >= slip.buffer.len) {
        defer slip.reset();
        return slip_error.BufferOverflow;
    } else {
        slip.buffer[slip.size] = @intFromEnum(byte);
        slip.size += 1;
        slip.state = .normal;
    }
}

var _testExpected: []const u8 = undefined;
var _testUserData = "Test";

const _TestHandler = struct {
    fn testHandler(testBuffer: []u8, user_data: *const anyopaque) bool {
        std.testing.expect(@as([*]u8, @ptrCast(@constCast(user_data))) == _testUserData) catch {
            std.debug.print("User data does not match {any}!={any}", .{ @as([*]u8, @ptrCast(@constCast(user_data))), _testUserData });
            return false;
        };
        std.testing.expect(testBuffer.len == _testExpected.len) catch {
            std.debug.print("Length does not match {}!={}", .{ testBuffer.len, _testExpected.len });
            return false;
        };
        std.testing.expect(std.mem.eql(u8, testBuffer, _testExpected)) catch {
            std.debug.print("Content does not match {any}!={any}", .{ testBuffer, _testExpected });
            return false;
        };
        return true;
    }
};

fn testSlip(input: []const u8, expected: []const u8) !void {
    _testExpected = expected;

    var slip = try Slip.init(std.testing.allocator, 1024, _TestHandler.testHandler, _testUserData);
    defer slip.deinit();
    try slip.readAll(input);
}

test "normal string is parsed successfully" {
    const input: []const u8 = "Hello World" ++ [_]u8{0xC0};
    try testSlip(input, "Hello World");
    _testExpected = undefined;
}

test "escaped string containing end byte is parsed successfully" {
    const input: []const u8 = &[_]u8{ 0xDB, 0xDC, 0xC0 };
    try testSlip(input, &[_]u8{0xC0});
    _testExpected = undefined;
}

test "escaped string containing esc byte is parsed successfully" {
    const input: []const u8 = &[_]u8{ 0xDB, 0xDD, 0xC0 };
    try testSlip(input, &[_]u8{0xDB});
    _testExpected = undefined;
}
