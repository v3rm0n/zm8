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

const Audio = @This();
const TransferList = std.ArrayList(*Transfer);

allocator: *const std.mem.Allocator,
device_handle: *zusb.DeviceHandle,
transfers: TransferList,
ring_buffer: *RingBuffer,

pub fn init(
    allocator: *const std.mem.Allocator,
    device_handle: *zusb.DeviceHandle,
    audio_buffer_size: u16,
    audio_device_name: ?[*:0]const u8,
) !Audio {
    std.log.info("Initialising audio", .{});

    std.log.info("Capturing audio with preferred device: {s}", .{audio_device_name orelse "default"});

    if (!SDL.wasInit(.{ .audio = true }).audio) {
        std.log.info("Audio subsystem has not been inited, initing", .{});
        try SDL.initSubSystem(.{ .audio = true });
    }

    var ring_buffer = try allocator.create(RingBuffer);
    errdefer allocator.destroy(ring_buffer);

    const audio_spec = SDL.AudioSpecRequest{
        .sample_rate = 44100,
        .buffer_format = SDL.AudioFormat.s16,
        .channel_count = 2,
        .buffer_size_in_frames = audio_buffer_size,
        .callback = Audio.audioCallback,
        .userdata = @ptrCast(ring_buffer),
    };

    const result = try SDL.openAudioDevice(.{ .device_name = audio_device_name, .desired_spec = audio_spec });

    std.log.debug("Creating ring buffer with size {}", .{4 * result.obtained_spec.buffer_size_in_frames});

    ring_buffer.* = try RingBuffer.init(allocator.*, 4 * result.obtained_spec.buffer_size_in_frames);
    errdefer ring_buffer.deinit(allocator.*);

    result.device.pause(false);

    try device_handle.claimInterface(INTERFACE);
    try device_handle.setInterfaceAltSetting(INTERFACE, 1);

    var transferList = try TransferList.initCapacity(allocator.*, NUM_TRANSFERS);

    for (0..NUM_TRANSFERS) |_| {
        try transferList.append(try startUsbTransfer(allocator, device_handle, ring_buffer));
    }

    std.log.debug("Transfers created and submitted", .{});

    return Audio{ .allocator = allocator, .device_handle = device_handle, .ring_buffer = ring_buffer, .transfers = transferList };
}

fn startUsbTransfer(allocator: *const std.mem.Allocator, device_handle: *zusb.DeviceHandle, ring_buffer: *RingBuffer) !*Transfer {
    const transfer = try Transfer.fillIsochronous(
        allocator,
        device_handle,
        ENDPOINT_ISO_IN,
        PACKET_SIZE,
        NUM_PACKETS,
        Audio.transferCallback,
        ring_buffer,
        0,
    );
    try transfer.submit();
    return transfer;
}

fn transferCallback(transfer: *zusb.Transfer, packet_descriptor: *const zusb.PacketDescriptor) void {
    std.log.info("Transfer callback", .{});
    transfer.user_data.writeSlice(packet_descriptor.buffer(transfer)) catch |err| std.log.err("Could not write to buffer {any}", .{err});
}

fn audioCallback(user_data: ?*anyopaque, stream: [*c]u8, length: c_int) callconv(.C) void {
    std.log.debug("Audio callback", .{});
    const ring_buffer: *RingBuffer = @ptrCast(@alignCast(user_data orelse @panic("No user data provided!")));
    const ulength: usize = @intCast(length);
    const read_length = ring_buffer.len();
    ring_buffer.readFirst(stream[0..ulength], @min(read_length, ulength)) catch |err| {
        std.log.err("Could not read from ring buffer: {}\n read length {}", .{ err, ulength });
    };

    if (read_length < ulength) {
        @memset(stream[read_length..(ulength - read_length)], 0);
    }
}

pub fn deinit(self: *Audio) void {
    for (0..NUM_PACKETS) |i| {
        self.transfers.items[i].deinit();
    }
    self.device_handle.releaseInterface(INTERFACE) catch |err| std.log.err("Could not release interface: {}\n", .{err});
    self.ring_buffer.deinit(self.allocator.*);
    self.allocator.destroy(self.ring_buffer);
}
