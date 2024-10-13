const std = @import("std");

extern "c" fn webserial_read(buffer: [*]u8, length: usize) usize;

extern "c" fn webserial_write(buffer: [*]const u8, length: usize) usize;

const WebSerial = @This();

pub fn init() WebSerial {
    return .{};
}

fn readWebSerial(ptr: *const anyopaque, buffer: []u8) !usize {
    _ = ptr;
    return webserial_read(buffer.ptr, buffer.len);
}

fn writeWebSerial(ptr: *const anyopaque, buffer: []const u8) !usize {
    _ = ptr;
    return webserial_write(buffer.ptr, buffer.len);
}

pub fn reader(self: *const WebSerial) std.io.AnyReader {
    return .{
        .context = self,
        .readFn = readWebSerial,
    };
}

pub fn writer(self: *const WebSerial) std.io.AnyWriter {
    return .{
        .context = self,
        .writeFn = writeWebSerial,
    };
}
