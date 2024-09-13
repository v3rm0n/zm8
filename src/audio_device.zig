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

const AudioDevice = @This();

allocator: std.mem.Allocator,
ring_buffer: *RingBuffer,
audio_device: SDL.AudioDevice,

pub fn init(
    allocator: std.mem.Allocator,
    audio_buffer_size: u16,
    audio_device_name: ?[*:0]const u8,
) !AudioDevice {
    std.log.info("Initialising audio device", .{});

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
        .callback = AudioDevice.audioCallback,
        .userdata = @ptrCast(ring_buffer),
    };

    const result = try SDL.openAudioDevice(.{ .device_name = audio_device_name, .desired_spec = audio_spec });

    ring_buffer.* = try RingBuffer.init(allocator, 8 * result.obtained_spec.buffer_size_in_frames);
    errdefer ring_buffer.deinit(allocator);

    result.device.pause(false);

    return AudioDevice{
        .allocator = allocator,
        .ring_buffer = ring_buffer,
        .audio_device = result.device,
    };
}

fn audioCallback(user_data: ?*anyopaque, stream: [*c]u8, length: c_int) callconv(.C) void {
    const ring_buffer: *RingBuffer = @ptrCast(@alignCast(user_data orelse @panic("No user data provided!")));
    const ulength: usize = @intCast(length);
    const read_length = ring_buffer.len();
    const to_read = @min(read_length, ulength);
    ring_buffer.readFirst(stream[0..ulength], to_read) catch |err| {
        std.log.err("Could not read from ring buffer: {}\n read length {}", .{ err, ulength });
    };

    if (to_read < ulength) {
        @memset(stream[to_read..ulength], 0);
    }
}

pub fn deinit(self: *AudioDevice) void {
    std.log.debug("Deiniting audio", .{});
    self.audio_device.close();
    self.ring_buffer.deinit(self.allocator);
    self.allocator.destroy(self.ring_buffer);
}
