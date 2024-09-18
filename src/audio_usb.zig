const std = @import("std");
const zusb = @import("zusb");
const RingBuffer = std.RingBuffer;

const audio_interface_out = 4;
const isochronous_endpoint_in = 0x85;
const number_of_transfers = 64;
const packet_size = 180;
const number_of_packets = 2;

const AudioUsb = @This();
const Transfer = zusb.Transfer(RingBuffer);
const TransferList = std.ArrayList(*Transfer);

allocator: std.mem.Allocator,
usb_device: *zusb.DeviceHandle,
transfers: TransferList,

pub fn init(
    allocator: std.mem.Allocator,
    usb_device: *zusb.DeviceHandle,
    ring_buffer: *RingBuffer,
) !AudioUsb {
    std.log.info("Initialising audio", .{});

    try usb_device.claimInterface(audio_interface_out);
    try usb_device.setInterfaceAltSetting(audio_interface_out, 1);

    var transferList = try TransferList.initCapacity(allocator, number_of_transfers);

    for (0..number_of_transfers) |_| {
        try transferList.append(try startUsbTransfer(allocator, usb_device, ring_buffer));
    }

    std.log.debug("Transfers created and submitted", .{});

    return AudioUsb{
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
        AudioUsb.transferCallback,
        ring_buffer,
        0,
    );
    try transfer.submit();
    return transfer;
}

fn transferCallback(ring_buffer: *RingBuffer, buffer: []const u8) void {
    ring_buffer.writeSlice(buffer) catch return;
}

fn hasPendingTransfers(self: *AudioUsb) bool {
    for (0..number_of_transfers) |i| {
        if (self.transfers.items[i].isActive()) {
            return true;
        }
    }
    return false;
}

pub fn deinit(self: *AudioUsb) void {
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
