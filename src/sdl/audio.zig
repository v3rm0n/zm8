const std = @import("std");
const SDL = @import("sdl2");
const RingBuffer = std.RingBuffer;

const SDLAudio = @This();

allocator: std.mem.Allocator,
ring_buffer: *RingBuffer,
audio_device: SDL.AudioDevice,

pub fn init(
    allocator: std.mem.Allocator,
    audio_buffer_size: u16,
    audio_device_name: []const u8,
) !SDLAudio {
    std.log.info("Initialising audio device", .{});

    std.log.info("Capturing audio with preferred device: {s}", .{audio_device_name});

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
        .callback = SDLAudio.audioCallback,
        .userdata = @ptrCast(ring_buffer),
    };

    std.log.debug("Requesting audio spec {any}", .{audio_spec});

    const device_name: ?[*:0]const u8 = if (std.mem.eql(u8, "Default", audio_device_name)) null else try allocator.dupeZ(u8, audio_device_name);

    const result = try SDL.openAudioDevice(.{ .device_name = device_name, .desired_spec = audio_spec });

    std.log.debug("Obtained audio spec {any}", .{result.obtained_spec});

    ring_buffer.* = try RingBuffer.init(allocator, 8 * result.obtained_spec.buffer_size_in_frames);
    errdefer ring_buffer.deinit(allocator);

    std.log.debug("Unpausing audio", .{});
    result.device.pause(false);

    return .{
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

pub fn deinit(self: *SDLAudio) void {
    std.log.debug("Deiniting audio device", .{});
    self.audio_device.close();
    self.ring_buffer.deinit(self.allocator);
    self.allocator.destroy(self.ring_buffer);
}
