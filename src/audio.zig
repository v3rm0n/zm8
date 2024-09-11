const std = @import("std");
const zusb = @import("zusb/zusb.zig");
const SDL = @import("sdl2");
const RingBuffer = std.RingBuffer;

const INTERFACE = 4;
const ENDPOINT_ISO_IN = 0x85;
const NUM_TRANSFERS = 64;
const PACKET_SIZE = 180;
const NUM_PACKETS = 2;

const Audio = @This();

allocator: std.mem.Allocator,
device_handle: *zusb.DeviceHandle,
ring_buffer: *RingBuffer,

pub fn init(
    allocator: std.mem.Allocator,
    buffer_size: usize,
    device_handle: *zusb.DeviceHandle,
) !Audio {
    std.log.info("Initialising audio", .{});
    var ringBuffer = try allocator.create(RingBuffer);
    errdefer allocator.destroy(ringBuffer);

    ringBuffer.* = try RingBuffer.init(allocator, buffer_size);
    errdefer ringBuffer.deinit(allocator);

    return Audio{
        .allocator = allocator,
        .device_handle = device_handle,
        .ring_buffer = ringBuffer,
    };
}

pub fn start(
    self: *Audio,
    audio_buffer_size: u16,
    audio_device_name: ?[*:0]const u8,
) !void {
    std.log.info("Capturing audio with preferred device: {s}", .{audio_device_name orelse "default"});

    if (!SDL.wasInit(.{ .audio = true }).audio) {
        try SDL.initSubSystem(.{ .audio = true });
    }

    const audio_spec = SDL.AudioSpecRequest{
        .sample_rate = 44100,
        .buffer_format = SDL.AudioFormat.s16,
        .channel_count = 2,
        .buffer_size_in_frames = audio_buffer_size,
        .callback = Audio.audioCallback,
        .userdata = @ptrCast(self.ring_buffer),
    };

    const result = try SDL.openAudioDevice(.{ .device_name = audio_device_name, .desired_spec = audio_spec });

    result.device.pause(false);
    try self.startUsbTransfer();
}

const Transfer = zusb.Transfer(RingBuffer);

fn startUsbTransfer(self: *Audio) !void {
    std.log.info("Starting USB transfer", .{});
    try self.device_handle.claimInterface(INTERFACE);
    try self.device_handle.setInterfaceAltSetting(INTERFACE, 1);

    const buffer = try self.allocator.alloc(u8, NUM_PACKETS * NUM_PACKETS);
    _ = buffer;
    Transfer.testFn();
    //try transfer.submit();
    //return transfer;
}

fn transferCallback(transfer: *Transfer) void {
    std.log.info("Transfer callback", .{});
    const isoPackets = transfer.transfer.iso_packet_desc();
    while (isoPackets.next()) |pack| {
        if (pack.isCompleted()) {
            std.log.info("Isochronous transfer failed, status {}: {}", .{pack.status()});
            continue;
        }
        transfer.user_data.writeSlice(pack.buffer);
        transfer.submit() catch transfer.allocator.free(transfer.transfer.buffer);
    }
}

fn audioCallback(user_data: ?*anyopaque, stream: [*c]u8, length: c_int) callconv(.C) void {
    const ring_buffer: *RingBuffer = @ptrCast(@alignCast(user_data.?));
    const ulength: usize = @intCast(length);
    const output = stream[0..ulength];
    const read_length = ring_buffer.len();
    ring_buffer.readFirst(output, ulength) catch |err| {
        std.log.err("Could not read from ring buffer: {}\n read length {}", .{ err, ulength });
    };

    if (read_length < ulength) {
        @memset(stream[read_length..(ulength - read_length)], 0);
    }
}

fn deinit(self: *Audio) zusb.Error!void {
    self.device_handle.releaseInterface(INTERFACE) catch |err| std.log.err("Could not release interface: {}\n", .{err});
    self.ring_buffer.deinit(self.allocator);
    self.allocator.free(self.ring_buffer);
}
