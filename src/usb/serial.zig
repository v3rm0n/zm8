const std = @import("std");
const zusb = @import("zusb");
const UsbSerialReadTransfer = @import("serial_read_transfer.zig");
const UsbSerialWriteTransfer = @import("serial_write_transfer.zig");

const UsbSerial = @This();

allocator: std.mem.Allocator,
device_handle: *zusb.DeviceHandle,
usb_reader: UsbSerialReadTransfer,
usb_writer: UsbSerialWriteTransfer,

pub fn init(
    allocator: std.mem.Allocator,
    device_handle: *zusb.DeviceHandle,
    buffer_size: usize,
) !UsbSerial {
    try initInterface(device_handle);

    const usb_reader = try UsbSerialReadTransfer.init(allocator, device_handle, buffer_size);
    errdefer usb_reader.deinit();

    const usb_writer = try UsbSerialWriteTransfer.init(allocator, device_handle, buffer_size);
    errdefer usb_writer.deinit();

    return .{
        .allocator = allocator,
        .device_handle = device_handle,
        .usb_reader = usb_reader,
        .usb_writer = usb_writer,
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

pub fn reader(self: *const UsbSerial) std.io.AnyReader {
    return .{ .context = self, .readFn = read };
}

pub fn read(ptr: *const anyopaque, buffer: []u8) zusb.Error!usize {
    const self: *UsbSerial = @constCast(@alignCast(@ptrCast(ptr)));
    return self.usb_reader.read(buffer);
}

pub fn writer(self: *const UsbSerial) std.io.AnyWriter {
    return .{ .context = self, .writeFn = write };
}

pub fn write(ptr: *const anyopaque, buffer: []const u8) zusb.Error!usize {
    const self: *UsbSerial = @constCast(@alignCast(@ptrCast(ptr)));
    return self.usb_writer.write(buffer);
}

pub fn deinit(self: *UsbSerial) void {
    std.log.debug("Deiniting Serial", .{});
    self.usb_writer.deinit();
    self.usb_reader.deinit();
    std.log.debug("Releasing interfaces {} and {}", .{ 1, 0 });
    self.device_handle.releaseInterface(1) catch |err| std.log.err("Could not release interface: {}", .{err});
    self.device_handle.releaseInterface(0) catch |err| std.log.err("Could not release interface: {}", .{err});
}
