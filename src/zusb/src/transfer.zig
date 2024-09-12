const c = @import("c.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const DeviceHandle = @import("device_handle.zig").DeviceHandle;
const PacketDescriptors = @import("packet_descriptor.zig").PacketDescriptors;
const PacketDescriptor = @import("packet_descriptor.zig").PacketDescriptor;
const RingBuffer = std.RingBuffer;

const err = @import("error.zig");

pub const Transfer = struct {
    allocator: *const Allocator,
    transfer: *c.libusb_transfer,
    callback: *const fn (*Transfer, *const PacketDescriptor) void,
    user_data: *RingBuffer,
    buf: []u8,

    pub fn deinit(self: *const Transfer) void {
        c.libusb_free_transfer(self.transfer);
        self.allocator.free(self.buf);
        self.allocator.destroy(self);
    }

    pub fn submit(self: *Transfer) err.Error!void {
        std.log.debug("Submitting isochronous transfer", .{});
        try err.failable(c.libusb_submit_transfer(self.transfer));
    }

    pub fn cancel(self: *Transfer) err.Error!void {
        try err.failable(c.libusb_cancel_transfer(self.transfer));
    }

    pub fn buffer(self: Transfer) []u8 {
        const length = std.math.cast(usize, self.transfer.length) orelse @panic("Buffer length too large");
        return self.transfer.buffer[0..length];
    }

    pub fn fillIsochronous(
        allocator: *const Allocator,
        handle: *DeviceHandle,
        endpoint: u8,
        packet_size: u16,
        num_packets: u16,
        callback: *const fn (*Transfer, *const PacketDescriptor) void,
        user_data: *RingBuffer,
        timeout: u64,
    ) !*Transfer {
        std.log.debug("Creating new isochronous transfer", .{});
        const opt_transfer: ?*c.libusb_transfer = c.libusb_alloc_transfer(0);

        if (opt_transfer) |transfer| {
            const buf = try allocator.alloc(u8, packet_size * num_packets);
            const self = try allocator.create(Transfer);
            self.* = .{
                .allocator = allocator,
                .transfer = transfer,
                .callback = callback,
                .user_data = user_data,
                .buf = buf,
            };

            transfer.*.dev_handle = handle.raw;
            transfer.*.endpoint = endpoint;
            transfer.*.type = c.LIBUSB_TRANSFER_TYPE_ISOCHRONOUS;
            transfer.*.buffer = buf.ptr;
            transfer.*.length = std.math.cast(c_int, buf.len) orelse @panic("Length too large");
            transfer.*.num_iso_packets = std.math.cast(c_int, num_packets) orelse @panic("Number of packets too large");
            transfer.*.callback = callbackRaw;
            transfer.*.user_data = @ptrCast(self);
            transfer.*.timeout = std.math.cast(c_uint, timeout) orelse @panic("Timeout too large");

            c.libusb_set_iso_packet_lengths(transfer, packet_size);

            return self;
        } else {
            return error.OutOfMemory;
        }
    }

    export fn callbackRaw(transfer: [*c]c.libusb_transfer) void {
        std.log.debug("Running isochronous callback", .{});
        const self: *Transfer = @alignCast(@ptrCast(transfer.*.user_data.?));
        const num_iso_packets: usize = @intCast(transfer.*.num_iso_packets);
        var isoPackets = PacketDescriptors.init(transfer.*.iso_packet_desc()[0..num_iso_packets]);
        while (isoPackets.next()) |pack| {
            if (pack.isCompleted()) {
                std.log.info("Isochronous transfer failed, status: {}", .{pack.status()});
                continue;
            }
            self.callback(self, &pack);
            self.submit() catch |e| std.log.err("Failed to resubmit isochronous transfer: {}", .{e});
        }
    }
};
