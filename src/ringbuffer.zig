const std = @import("std");

const RingBuffer = @This();

const RingBufferError = error{ RingBufferFull, RingBufferEmpty };

buffer: []u8,

size: usize = 0,
read: usize = 0,
write: usize = 0,

pub fn init(buffer: []u8) !RingBuffer {
    return RingBuffer{ .buffer = buffer };
}

pub fn isEmpty(ringBuffer: *RingBuffer) bool {
    return ringBuffer.size == 0;
}

pub fn isFull(ringBuffer: *RingBuffer) bool {
    return ringBuffer.size == ringBuffer.buffer.len;
}

pub fn push(ringBuffer: *RingBuffer, buf: []const u8) RingBufferError!usize {
    if (ringBuffer.isFull()) {
        return RingBufferError.RingBufferFull;
    }
    const free_space = ringBuffer.buffer.len - ringBuffer.size;
    const space_to_end = ringBuffer.buffer.len - ringBuffer.write;
    const writable_bytes = if (buf.len <= free_space) buf.len else free_space;
    const buffer_write_start = ringBuffer.buffer[ringBuffer.write..];
    if (writable_bytes <= space_to_end) {
        @memcpy(buffer_write_start[0..writable_bytes], buf[0..writable_bytes]);
    } else {
        @memcpy(buffer_write_start[0..], buf[0..space_to_end]);
        @memcpy(ringBuffer.buffer[0..(writable_bytes - space_to_end)], buf[space_to_end .. space_to_end + (writable_bytes - space_to_end)]);
    }
    ringBuffer.write = (ringBuffer.write + writable_bytes) % ringBuffer.buffer.len;
    ringBuffer.size += writable_bytes;
    return writable_bytes;
}

pub fn pop(ringBuffer: *RingBuffer, buf: []u8) RingBufferError!usize {
    if (ringBuffer.isEmpty()) {
        return RingBufferError.RingBufferEmpty;
    }
    const space_to_end = ringBuffer.buffer.len - ringBuffer.read;
    const readable_bytes = if (buf.len <= ringBuffer.size) buf.len else ringBuffer.size;
    if (readable_bytes <= space_to_end) {
        @memcpy(buf[0..readable_bytes], ringBuffer.buffer[ringBuffer.read..(ringBuffer.read + readable_bytes)]);
    } else {
        @memcpy(buf[0..space_to_end], ringBuffer.buffer[ringBuffer.read..]);
        @memcpy(buf[space_to_end..], ringBuffer.buffer[0..(readable_bytes - space_to_end)]);
    }
    ringBuffer.read = (ringBuffer.read + readable_bytes) % ringBuffer.buffer.len;
    ringBuffer.size -= readable_bytes;
    return readable_bytes;
}

test "acts as a normal buffer when max size is not reached" {
    const result = try std.testing.allocator.alloc(u8, 5);
    defer std.testing.allocator.free(result);

    const buffer = try std.testing.allocator.alloc(u8, 5);
    defer std.testing.allocator.free(buffer);

    var ringBuffer = try RingBuffer.init(buffer);

    const input: []const u8 = "Hello";
    try std.testing.expectEqual(5, try ringBuffer.push(input));
    _ = try ringBuffer.pop(result);

    try std.testing.expect(std.mem.eql(u8, "Hello", result));
}

test "can't push to a full buffer" {
    const buffer = try std.testing.allocator.alloc(u8, 5);
    defer std.testing.allocator.free(buffer);

    var ringBuffer = try RingBuffer.init(buffer);

    const input: []const u8 = "Hello";
    try std.testing.expectEqual(5, try ringBuffer.push(input));

    try std.testing.expect(ringBuffer.isFull());

    const resultError = ringBuffer.push(input);

    try std.testing.expectError(RingBufferError.RingBufferFull, resultError);
}

test "can't pop from an empty buffer" {
    const result = try std.testing.allocator.alloc(u8, 5);
    defer std.testing.allocator.free(result);

    const buffer = try std.testing.allocator.alloc(u8, 5);
    defer std.testing.allocator.free(buffer);

    var ringBuffer = try RingBuffer.init(buffer);

    try std.testing.expect(ringBuffer.isEmpty());

    const resultError = ringBuffer.pop(result);

    try std.testing.expectError(RingBufferError.RingBufferEmpty, resultError);
}

test "loops around if buffer is full" {
    const result = try std.testing.allocator.alloc(u8, 5);
    defer std.testing.allocator.free(result);

    const buffer = try std.testing.allocator.alloc(u8, 6);
    defer std.testing.allocator.free(buffer);

    var ringBuffer = try RingBuffer.init(buffer);

    const input1: []const u8 = "Hello";
    try std.testing.expectEqual(5, try ringBuffer.push(input1));
    try std.testing.expectEqual(5, try ringBuffer.pop(result));
    try std.testing.expect(std.mem.eql(u8, "Hello", result));

    try std.testing.expect(ringBuffer.isEmpty());

    const input2: []const u8 = "world";
    try std.testing.expectEqual(5, try ringBuffer.push(input2));
    try std.testing.expectEqual(5, try ringBuffer.pop(result));
    try std.testing.expect(std.mem.eql(u8, "world", result));

    try std.testing.expect(ringBuffer.isEmpty());
}
