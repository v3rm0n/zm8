const std = @import("std");
const zusb = @import("zusb");
const RingBuffer = std.RingBuffer;

const serial_endpoint_in = 0x83;

const UsbSerialReadTransfer = @This();

const Transfer = zusb.Transfer(SerialQueue);
const SerialQueue = std.fifo.LinearFifo(u8, .Dynamic);

allocator: std.mem.Allocator,
transfer: *Transfer,
queue: *SerialQueue,

//Wraps a writer and uses a continuous bulk transfer to read from a USB serial device.
pub fn init(
    allocator: std.mem.Allocator,
    device_handle: *zusb.DeviceHandle,
    buffer_size: usize,
) !UsbSerialReadTransfer {
    const queue = try allocator.create(SerialQueue);
    queue.* = SerialQueue.init(allocator);

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
    return .{ .transfer = transfer, .allocator = allocator, .queue = queue };
}

pub fn read(self: UsbSerialReadTransfer, buffer: []u8) usize {
    return self.queue.read(buffer);
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
    self.queue.deinit();
    self.allocator.destroy(self.queue);
}
