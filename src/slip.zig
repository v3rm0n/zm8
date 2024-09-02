const std = @import("std");

const SLIP_SPECIAL_BYTE_END = 0xC0;
const SLIP_SPECIAL_BYTE_ESC = 0xDB;

const SLIP_ESCAPED_BYTE_END = 0xDC;
const SLIP_ESCAPED_BYTE_ESC = 0xDD;

const Handler = *const fn (buffer: []u8, size: u8) bool;

const SlipError = error{ BufferOverflow, UnknownEscapedByte, InvalidPacket };

const SlipState = enum { Normal, Escaped };

const Slip = @This();

buffer: []u8,
size: u8 = 0,
handler: Handler,
state: SlipState = SlipState.Normal,

pub fn init(buffer: []u8, comptime handler: Handler) Slip {
    return Slip{ .buffer = buffer, .handler = handler };
}

pub fn read(slip: *Slip, byte: u8) SlipError!void {
    switch (slip.state) {
        SlipState.Normal => switch (byte) {
            SLIP_SPECIAL_BYTE_END => {
                defer slip.reset();
                if (!slip.handler(slip.buffer, slip.size)) {
                    return SlipError.InvalidPacket;
                }
            },
            SLIP_SPECIAL_BYTE_ESC => slip.state = SlipState.Escaped,
            else => try slip.byteToBuffer(byte),
        },
        SlipState.Escaped => {
            switch (byte) {
                SLIP_ESCAPED_BYTE_END => try slip.byteToBuffer(SLIP_SPECIAL_BYTE_END),
                SLIP_ESCAPED_BYTE_ESC => try slip.byteToBuffer(SLIP_SPECIAL_BYTE_ESC),
                else => {
                    defer slip.reset();
                    return SlipError.UnknownEscapedByte;
                },
            }
            slip.state = SlipState.Normal;
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

const _TestHandler = struct {
    fn testHandler(testBuffer: []u8, testBufferSize: u8) bool {
        std.testing.expect(testBufferSize == _testExpected.len) catch {
            std.debug.print("Length does not match {}!={}", .{ testBufferSize, _testExpected.len });
            return false;
        };
        std.testing.expect(std.mem.eql(u8, testBuffer[0..testBufferSize], _testExpected)) catch {
            std.debug.print("Content does not match {any}!={any}", .{ testBuffer[0..testBufferSize], _testExpected });
            return false;
        };
        return true;
    }
};

fn testSlip(input: []const u8, expected: []const u8) !void {
    const buffer = try std.testing.allocator.alloc(u8, 1024);
    defer std.testing.allocator.free(buffer);
    _testExpected = expected;

    var slip = Slip.init(buffer, _TestHandler.testHandler);
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
