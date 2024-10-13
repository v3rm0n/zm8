const std = @import("std");
const zusb = @import("zusb");

const UsbSerialWriteTransfer = @This();
const Transfer = zusb.Transfer(std.io.AnyWriter);
const SerialQueue = std.fifo.LinearFifo(u8, .Dynamic);

const serial_endpoint_out = 0x03;
var pending_transfers_count: usize = 0;
device_handle: *zusb.DeviceHandle,

pub fn init(
    allocator: std.mem.Allocator,
    device_handle: *zusb.DeviceHandle,
) !UsbSerialWriteTransfer {
    return .{ .allocator = allocator, .device_handle = device_handle };
}

pub fn write(self: *UsbSerialWriteTransfer, buffer: []const u8) zusb.Error!usize {
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

pub fn deinit(self: UsbSerialWriteTransfer) void {
    _ = self;
    while (pending_transfers_count > 0) {
        std.log.debug("Pending transfer count {}", .{pending_transfers_count});
        std.Thread.sleep(100 * 1000);
    }
}
