const std = @import("std");
const zusb = @import("zusb");
const UsbSerialTransfer = @import("serial_transfer.zig");
const RingBuffer = std.RingBuffer;

const serial_endpoint_out = 0x03;
const serial_endpoint_in = 0x83;

const UsbSerial = @This();

const Transfer = zusb.Transfer(std.io.AnyWriter);

var pending_transfers_count: usize = 0;

allocator: std.mem.Allocator,
device_handle: *zusb.DeviceHandle,
usb_reader: UsbSerialTransfer,

pub fn init(
    allocator: std.mem.Allocator,
    device_handle: *zusb.DeviceHandle,
    buffer_size: usize,
    read_writer: std.io.AnyWriter,
) !UsbSerial {
    try initInterface(device_handle);

    const usb_reader = try UsbSerialTransfer.init(allocator, device_handle, buffer_size, read_writer);

    return .{
        .allocator = allocator,
        .device_handle = device_handle,
        .usb_reader = usb_reader,
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

pub fn writer(self: *const UsbSerial) std.io.AnyWriter {
    return .{ .context = self, .writeFn = write };
}

pub fn write(
    ptr: *const anyopaque,
    buffer: []const u8,
) zusb.Error!usize {
    const self: *UsbSerial = @constCast(@alignCast(@ptrCast(ptr)));
    var transfer = try Transfer.fillBulk(
        self.allocator,
        self.device_handle,
        serial_endpoint_out,
        buffer.len,
        writeCallback,
        null,
        50,
        .{},
    );
    transfer.setData(buffer);
    pending_transfers_count += 1;
    try transfer.submit();
    return buffer.len;
}

fn writeCallback(transfer: *Transfer) void {
    defer transfer.deinit();
    pending_transfers_count -= 1;
}

pub fn deinit(self: *UsbSerial) void {
    std.log.debug("Deiniting Serial", .{});
    self.usb_reader.deinit();
    while (pending_transfers_count > 0) {
        std.log.debug("Pending transfer count {}", .{pending_transfers_count});
        std.Thread.sleep(100 * 1000);
    }
    std.log.debug("Releasing interfaces {} and {}", .{ 1, 0 });
    self.device_handle.releaseInterface(1) catch |err| std.log.err("Could not release interface: {}", .{err});
    self.device_handle.releaseInterface(0) catch |err| std.log.err("Could not release interface: {}", .{err});
}
