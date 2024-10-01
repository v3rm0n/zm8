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

    var transferList = try TransferList.initCapacity(allocator, number_of_transfers);
    errdefer transferList.deinit();

    for (0..number_of_transfers) |_| {
        try transferList.append(try startUsbTransfer(allocator, usb_device, ring_buffer));
    }

    std.log.debug("Transfers created and submitted", .{});

    return .{
        .allocator = allocator,
        .usb_device = usb_device,
        .transfers = transferList,
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
    if (transfer.transferStatus() != zusb.TransferStatus.Completed) {
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

fn hasPendingTransfers(self: *UsbAudio) bool {
    for (0..number_of_transfers) |i| {
        if (self.transfers.items[i].isActive()) {
            return true;
        }
    }
    return false;
}

pub fn deinit(self: *UsbAudio) void {
    std.log.debug("Deiniting USB audio", .{});
    for (0..number_of_transfers) |i| {
        self.transfers.items[i].cancel() catch |err| std.log.err("Could not cancel transfer: {}", .{err});
    }
    while (self.hasPendingTransfers()) {
        self.usb_device.ctx.handleEvents() catch |err| std.log.err("Could not handle events: {}", .{err});
    }
    for (0..number_of_transfers) |i| {
        self.transfers.items[i].deinit();
    }
    self.usb_device.releaseInterface(audio_interface_out) catch |err| std.log.err("Could not release interface: {}", .{err});
    self.transfers.deinit();
}
