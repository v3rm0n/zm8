const std = @import("std");
const zusb = @import("zusb");
const RingBuffer = std.RingBuffer;

const serial_endpoint_in = 0x83;

const UsbSerialTransfer = @This();

const Transfer = zusb.Transfer(std.io.AnyWriter);

allocator: std.mem.Allocator,
transfer: *Transfer,

//Wraps a writer and uses a continuous bulk transfer to read from a USB serial device.
pub fn init(
    allocator: std.mem.Allocator,
    device_handle: *zusb.DeviceHandle,
    buffer_size: usize,
    writer: std.io.AnyWriter,
) !UsbSerialTransfer {
    const heap_writer = try allocator.create(std.io.AnyWriter);
    errdefer allocator.destroy(heap_writer);
    heap_writer.* = writer;

    var transfer = try Transfer.fillBulk(
        allocator,
        device_handle,
        serial_endpoint_in,
        buffer_size,
        readCallback,
        heap_writer,
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
    self.allocator.destroy(self.transfer.user_data.?);
    std.log.debug("Deiniting USB serial transfer", .{});
    self.transfer.deinit();
}
