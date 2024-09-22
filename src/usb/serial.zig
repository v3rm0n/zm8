const std = @import("std");
const zusb = @import("zusb");

const serial_endpoint_out = 0x03;
const serial_endpoint_in = 0x83;

const UsbSerial = @This();

allocator: std.mem.Allocator,
device_handle: *zusb.DeviceHandle,

pub fn init(
    allocator: std.mem.Allocator,
    device_handle: *zusb.DeviceHandle,
) !UsbSerial {
    try initInterface(device_handle);
    return .{
        .allocator = allocator,
        .device_handle = device_handle,
    };
}

fn initInterface(device_handle: *zusb.DeviceHandle) zusb.Error!void {
    std.log.info("Claiming interfaces", .{});
    try device_handle.claimInterface(0);
    try device_handle.claimInterface(1);

    std.log.info("Setting line state", .{});
    _ = try device_handle.writeControl(0x21, 0x22, 0x03, 0, null, 0);

    std.log.info("Set line encoding", .{});
    const encoding = [_](u8){ 0x00, 0xC2, 0x01, 0x00, 0x00, 0x00, 0x08 };
    _ = try device_handle.writeControl(0x21, 0x20, 0, 0, &encoding, 0);
    std.log.info("Interface initialisation finished", .{});
}

pub fn read(self: *const UsbSerial, buffer: []u8) zusb.Error!usize {
    return self.device_handle.readBulk(serial_endpoint_in, buffer, 10) catch |err| switch (err) {
        zusb.Error.Timeout => return 0,
        else => return err,
    };
}

pub fn reader(self: *UsbSerial) std.io.AnyReader {
    return .{ .context = self, .readFn = read };
}

pub fn write(self: *UsbSerial, buffer: []const u8) zusb.Error!usize {
    return try self.device_handle.writeBulk(serial_endpoint_out, buffer, 5);
}

pub fn writer(self: *UsbSerial) std.io.AnyWriter {
    return .{ .context = self, .writeFn = write };
}

pub fn deinit(self: *UsbSerial) void {
    std.log.debug("Deiniting Serial", .{});
    self.device_handle.releaseInterface(1) catch |err| std.log.err("Could not release interface: {}", .{err});
    self.device_handle.releaseInterface(0) catch |err| std.log.err("Could not release interface: {}", .{err});
}
