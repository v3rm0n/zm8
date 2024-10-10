const std = @import("std");
const zusb = @import("zusb");
const RingBuffer = std.RingBuffer;
const SerialQueue = @import("serial.zig").SerialQueue;

const serial_endpoint_in = 0x83;

const UsbSerialTransfer = @This();

const Transfer = zusb.Transfer(SerialQueue);

allocator: std.mem.Allocator,
transfer: *Transfer,

//Wraps a writer and uses a continuous bulk transfer to read from a USB serial device.
pub fn init(
    allocator: std.mem.Allocator,
    device_handle: *zusb.DeviceHandle,
    buffer_size: usize,
    queue: *SerialQueue,
) !UsbSerialTransfer {
    var transfer = try Transfer.fillBulk(
        allocator,
        device_handle,
        serial_endpoint_in,
        buffer_size,
        readCallback,
        queue,
        1,
        .{},
    );
    try transfer.submit();
    return .{ .transfer = transfer, .allocator = allocator };
}

fn readCallback(transfer: *Transfer) void {
    if (transfer.transferStatus() != .Completed and transfer.transferStatus() != .Timeout) {
        return;
    }
    const user_data = transfer.user_data.?;
    _ = user_data.write(transfer.getData()) catch |e| std.log.err("Failed to write to serial writer: {}", .{e});
    transfer.submit() catch |e| std.log.err("Failed to resubmit bulk/interrupt transfer: {}", .{e});
}

pub fn deinit(self: @This()) void {
    if (self.transfer.active) {
        self.transfer.cancel() catch |e| std.log.err("Failed to cancel transfer: {}", .{e});
    }
    while (self.transfer.active) {
        std.log.debug("Waiting for pending serial transfer", .{});
        std.Thread.sleep(10 * 1000);
    }
    std.log.debug("Deiniting USB serial transfer", .{});
    self.transfer.deinit();
}
