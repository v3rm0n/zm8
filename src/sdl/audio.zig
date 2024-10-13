const std = @import("std");
const SDL = @import("sdl2");
const RingBuffer = std.RingBuffer;

const SDLAudio = @This();

const Error = error{
    NoAudioDevicesFound,
};

allocator: std.mem.Allocator,
audio_device_in: SDL.AudioDevice,
audio_device_out: *SDL.AudioDevice,

pub fn init(
    allocator: std.mem.Allocator,
    audio_buffer_size: u16,
    audio_device_name: []const u8,
) !SDLAudio {
    std.log.info("Initialising audio device", .{});

    std.Thread.sleep(500 * 1000);

    std.log.info("Capturing audio with preferred device: {s}", .{audio_device_name});

    if (!SDL.wasInit(.{ .audio = true }).audio) {
        std.log.info("Audio subsystem has not been inited, initing", .{});
        try SDL.initSubSystem(.{ .audio = true });
    }

    const devices: usize = @intCast(SDL.c.SDL_GetNumAudioDevices(1));
    var m8_audio_device_id: ?usize = null;

    for (0..devices) |i| {
        const device_name = std.mem.span(SDL.c.SDL_GetAudioDeviceName(@intCast(i), 1));
        std.log.debug("Audio capture device({}): {s}", .{ i, device_name });
        if (std.mem.eql(u8, "M8", device_name)) {
            std.log.debug("Found M8 audio device {}", .{i});
            m8_audio_device_id = i;
        }
    }
    if (devices < 1 or m8_audio_device_id == null) {
        return Error.NoAudioDevicesFound;
    }

    const devices2: usize = @intCast(SDL.c.SDL_GetNumAudioDevices(0));

    for (0..devices2) |i| {
        const device_name = std.mem.span(SDL.c.SDL_GetAudioDeviceName(@intCast(i), 0));
        std.log.debug("Audio playback device({}): {s}", .{ i, device_name });
    }

    const audio_spec_out = SDL.AudioSpecRequest{
        .sample_rate = 44100,
        .buffer_format = .s16,
        .channel_count = 2,
        .buffer_size_in_frames = audio_buffer_size,
        .callback = null,
        .userdata = null,
    };

    const device_name: ?[*:0]const u8 = if (std.mem.eql(u8, "Default", audio_device_name)) null else audio_device_name[0.. :0];
    std.log.debug("Requesting audio out spec {any}", .{audio_spec_out});
    const audio_out = try SDL.openAudioDevice(.{
        .device_name = device_name,
        .desired_spec = audio_spec_out,
    });
    std.log.debug("Obtained audio device {} spec {any}", .{ audio_out.device, audio_out.obtained_spec });

    const heap_audio = try allocator.create(SDL.AudioDevice);
    errdefer allocator.destroy(heap_audio);
    heap_audio.* = audio_out.device;

    const audio_spec_in = SDL.AudioSpecRequest{
        .sample_rate = 44100,
        .buffer_format = .s16,
        .channel_count = 2,
        .buffer_size_in_frames = audio_buffer_size,
        .callback = audioCallback,
        .userdata = @constCast(@ptrCast(heap_audio)),
    };

    std.log.debug("Requesting audio in spec {any}", .{audio_spec_in});
    const audio_in = try SDL.openAudioDevice(.{
        .device_name = "M8",
        .is_capture = true,
        .desired_spec = audio_spec_in,
    });
    std.log.debug("Obtained audio device {} spec {any}", .{ audio_in.device, audio_in.obtained_spec });

    std.log.debug("Unpausing audio", .{});
    audio_in.device.pause(false);
    audio_out.device.pause(false);

    return .{
        .allocator = allocator,
        .audio_device_in = audio_in.device,
        .audio_device_out = heap_audio,
    };
}

fn audioCallback(user_data: ?*anyopaque, stream: [*c]u8, length: c_int) callconv(.C) void {
    const audio_device: *SDL.AudioDevice = @ptrCast(@alignCast(user_data orelse @panic("No user data provided!")));
    audio_device.queueAudio(stream[0..@as(usize, @intCast(length))]) catch |err| {
        std.log.err("Failed to queue audio: {}", .{err});
    };
}

pub fn deinit(self: *SDLAudio) void {
    std.log.debug("Deiniting audio device", .{});
    self.audio_device_in.pause(true);
    self.audio_device_out.pause(true);
    self.audio_device_in.close();
    self.audio_device_out.close();
    self.allocator.destroy(self.audio_device_out);
}
