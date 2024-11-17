const std = @import("std");
const serialport = @import("libserialport/libserialport.zig");
const device = @import("device.zig");

const Serial = @This();

const Error = error{
    CouldNotOpenDevice,
};

port: serialport.Port,

pub fn init(
    allocator: std.mem.Allocator,
    preferred_serial_device: ?[]const u8,
) !Serial {
    _ = allocator;
    const port = try device.openDevice(preferred_serial_device) orelse return Error.CouldNotOpenDevice;

    try port.open(.readWrite);
    try port.setBaudRate(115200);
    try port.setBits(8);
    try port.setParity(.none);
    try port.setStopBits(1);
    try port.setFlowControl(.none);

    return .{ .port = port };
}

pub fn deinit(self: Serial) void {
    self.port.close() catch |err| {
        std.debug.print("Error closing serial port: {}\n", .{err});
    };
    self.port.deinit();
}

pub fn reader(self: *const Serial) std.io.AnyReader {
    return .{ .context = self, .readFn = read };
}

pub fn read(
    ptr: *const anyopaque,
    buffer: []u8,
) !usize {
    const self: *Serial = @constCast(@alignCast(@ptrCast(ptr)));
    return try self.port.read(buffer);
}

pub fn writer(self: *const Serial) std.io.AnyWriter {
    return .{ .context = self, .writeFn = write };
}

pub fn write(
    ptr: *const anyopaque,
    buffer: []const u8,
) !usize {
    const self: *Serial = @constCast(@alignCast(@ptrCast(ptr)));
    return try self.port.blockingWrite(buffer, 5);
}
