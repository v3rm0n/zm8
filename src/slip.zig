const std = @import("std");

const SLIP_SPECIAL_BYTE_END = 0xC0;
const SLIP_SPECIAL_BYTE_ESC = 0xDB;

const SLIP_ESCAPED_BYTE_END = 0xDC;
const SLIP_ESCAPED_BYTE_ESC = 0xDD;

const Handler = *const fn (buffer: []u8, user_data: *const anyopaque) bool;

const SlipError = error{ BufferOverflow, UnknownEscapedByte, InvalidPacket };

const SlipState = enum { Normal, Escaped };

const Slip = @This();

allocator: std.mem.Allocator,
buffer: []u8,
size: usize = 0,
handler: Handler,
state: SlipState = SlipState.Normal,
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

pub fn readAll(self: *Slip, bytes: []u8) SlipError!void {
    for (bytes) |byte| {
        try self.read(byte);
    }
}

pub fn read(self: *Slip, byte: u8) SlipError!void {
    switch (self.state) {
        SlipState.Normal => switch (byte) {
            SLIP_SPECIAL_BYTE_END => {
                defer self.reset();
                if (!self.handler(self.buffer[0..self.size], self.user_data)) {
                    return SlipError.InvalidPacket;
                }
            },
            SLIP_SPECIAL_BYTE_ESC => self.state = SlipState.Escaped,
            else => try self.byteToBuffer(byte),
        },
        SlipState.Escaped => {
            switch (byte) {
                SLIP_ESCAPED_BYTE_END => try self.byteToBuffer(SLIP_SPECIAL_BYTE_END),
                SLIP_ESCAPED_BYTE_ESC => try self.byteToBuffer(SLIP_SPECIAL_BYTE_ESC),
                else => {
                    defer self.reset();
                    return SlipError.UnknownEscapedByte;
                },
            }
            self.state = SlipState.Normal;
        },
    }
}

fn reset(slip: *Slip) void {
    slip.state = SlipState.Normal;
    slip.size = 0;
}

fn byteToBuffer(slip: *Slip, byte: u8) SlipError!void {
    if (slip.size >= slip.buffer.len) {
        defer slip.reset();
        return SlipError.BufferOverflow;
    } else {
        slip.buffer[slip.size] = byte;
        slip.size += 1;
        slip.state = SlipState.Normal;
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
    for (input) |elem| {
        try slip.read(elem);
    }
}

test "normal string is parsed successfully" {
    const input: []const u8 = "Hello World" ++ [_]u8{SLIP_SPECIAL_BYTE_END};
    try testSlip(input, "Hello World");
    _testExpected = undefined;
}

test "escaped string containing end byte is parsed successfully" {
    const input: []const u8 = &[_]u8{ SLIP_SPECIAL_BYTE_ESC, SLIP_ESCAPED_BYTE_END, SLIP_SPECIAL_BYTE_END };
    try testSlip(input, &[_]u8{SLIP_SPECIAL_BYTE_END});
    _testExpected = undefined;
}

test "escaped string containing esc byte is parsed successfully" {
    const input: []const u8 = &[_]u8{ SLIP_SPECIAL_BYTE_ESC, SLIP_ESCAPED_BYTE_ESC, SLIP_SPECIAL_BYTE_END };
    try testSlip(input, &[_]u8{SLIP_SPECIAL_BYTE_ESC});
    _testExpected = undefined;
}
