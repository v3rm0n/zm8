const std = @import("std");
const zusb = @import("zusb");
const RingBuffer = std.RingBuffer;

const audio_interface_out = 4;
const isochronous_endpoint_in = 0x85;
const number_of_transfers = 64;
const packet_size = 180;
const number_of_packets = 2;

const UsbAudio = @This();
const Transfer = zusb.Transfer(RingBuffer);
const TransferList = std.ArrayList(*Transfer);

allocator: std.mem.Allocator,
usb_device: *zusb.DeviceHandle,
transfers: TransferList,

pub fn init(
    allocator: std.mem.Allocator,
    usb_device: *zusb.DeviceHandle,
    ring_buffer: *RingBuffer,
) !UsbAudio {
    std.log.info("Initialising audio", .{});

    try usb_device.claimInterface(audio_interface_out);
    try usb_device.setInterfaceAltSetting(audio_interface_out, 1);

    var transfer_list = try TransferList.initCapacity(allocator, number_of_transfers);
    errdefer transfer_list.deinit();

    for (0..number_of_transfers) |_| {
        try transfer_list.append(try startUsbTransfer(allocator, usb_device, ring_buffer));
    }

    std.log.debug("Transfers created and submitted", .{});

    return .{
        .allocator = allocator,
        .usb_device = usb_device,
        .transfers = transfer_list,
    };
}

fn startUsbTransfer(
    allocator: std.mem.Allocator,
    usb_device: *zusb.DeviceHandle,
    ring_buffer: *RingBuffer,
) !*Transfer {
    const transfer = try Transfer.fillIsochronous(
        allocator,
        usb_device,
        isochronous_endpoint_in,
        packet_size,
        number_of_packets,
        transferCallback,
        ring_buffer,
        0,
        .{},
    );
    try transfer.submit();
    return transfer;
}

fn transferCallback(transfer: *Transfer) void {
    if (transfer.transferStatus() != .Completed) {
        return;
    }
    var isoPackets = transfer.isoPackets();
    while (isoPackets.next()) |pack| {
        if (!pack.isCompleted()) {
            std.log.info("Isochronous transfer failed, status: {}", .{pack.status()});
            continue;
        }
        var ring_buffer = transfer.user_data.?;

        ring_buffer.writeSlice(pack.buffer()) catch |e| {
            std.log.err("Failed to call isochronous transfer callback: {}", .{e});
        };
    }
    transfer.submit() catch |e| std.log.err("Failed to resubmit bulk/interrupt transfer: {}", .{e});
}

fn pendingTransfers(self: *UsbAudio) u8 {
    var count: u8 = 0;
    for (self.transfers.items) |transfer| {
        if (transfer.isActive()) {
            count += 1;
        }
    }
    return count;
}

pub fn deinit(self: *UsbAudio) void {
    std.log.debug("Deiniting USB audio", .{});
    for (self.transfers.items) |transfer| {
        transfer.cancel() catch |err| std.log.err("Could not cancel transfer: {}", .{err});
    }
    while (self.pendingTransfers() > 0) {
        std.log.debug("Waiting for pending transfers: {}", .{self.pendingTransfers()});
        std.Thread.sleep(100 * 1000);
    }
    std.log.debug("Deiniting transfers", .{});
    for (self.transfers.items) |transfer| {
        transfer.deinit();
    }
    std.log.debug("Releasing interface {}", .{audio_interface_out});
    self.usb_device.releaseInterface(audio_interface_out) catch |err| std.log.err("Could not release interface: {}", .{err});
    self.transfers.deinit();
}
