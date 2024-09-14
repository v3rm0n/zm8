const std = @import("std");
const zusb = @import("zusb/zusb.zig");
const SDL = @import("sdl2");
const RingBuffer = std.RingBuffer;
const Transfer = zusb.Transfer;

const INTERFACE = 4;
const ENDPOINT_ISO_IN = 0x85;
const NUM_TRANSFERS = 64;
const PACKET_SIZE = 180;
const NUM_PACKETS = 2;

const AudioUsb = @This();
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

    try usb_device.claimInterface(INTERFACE);
    try usb_device.setInterfaceAltSetting(INTERFACE, 1);

    var transferList = try TransferList.initCapacity(allocator, NUM_TRANSFERS);

    for (0..NUM_TRANSFERS) |_| {
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
        ENDPOINT_ISO_IN,
        PACKET_SIZE,
        NUM_PACKETS,
        AudioUsb.transferCallback,
        ring_buffer,
        0,
    );
    try transfer.submit();
    return transfer;
}

fn transferCallback(transfer: *zusb.Transfer, packet_descriptor: *const zusb.PacketDescriptor) void {
    const buffer = packet_descriptor.buffer(transfer);
    transfer.user_data.writeSlice(buffer) catch return;
}

fn hasPendingTransfers(self: *AudioUsb) bool {
    for (0..NUM_TRANSFERS) |i| {
        if (self.transfers.items[i].isActive()) {
            return true;
        }
    }
    return false;
}

pub fn deinit(self: *AudioUsb) void {
    std.log.debug("Deiniting USB audio", .{});
    for (0..NUM_TRANSFERS) |i| {
        self.transfers.items[i].cancel() catch |err| std.log.err("Could not cancel transfer: {}", .{err});
    }
    while (self.hasPendingTransfers()) {
        self.usb_device.ctx.handleEvents() catch |err| std.log.err("Could not handle events: {}", .{err});
    }
    for (0..NUM_TRANSFERS) |i| {
        self.transfers.items[i].deinit();
    }
    self.usb_device.releaseInterface(INTERFACE) catch |err| std.log.err("Could not release interface: {}", .{err});
    self.transfers.deinit();
}
