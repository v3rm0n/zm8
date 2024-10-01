const std = @import("std");
const SDLUI = @import("sdl/ui.zig");
const M8 = @import("m8.zig");
const SDL = @import("sdl2");
const SDLAudio = @import("sdl/audio.zig");
const Slip = @import("slip.zig");
const Command = @import("command.zig");
const SDLHandler = @import("sdl_handler.zig");
const Config = @import("config.zig");

const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("Memory leak");
    }

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    var preferred_usb_device: ?[]u8 = null;
    if (args.len == 2 and std.mem.eql(u8, args[1], "--list")) {
        try M8.listDevices();
        return;
    }
    if (args.len == 3 and std.mem.eql(u8, args[1], "--dev")) {
        preferred_usb_device = args[2];
        std.log.info("Preferred device set to {s}", .{preferred_usb_device.?});
    }
    startWithSDL(allocator, preferred_usb_device) catch |err| {
        std.log.err("Error from SDL execution: {}", .{err});
    };
}

fn startWithSDL(allocator: std.mem.Allocator, preferred_usb_device: ?[]u8) !void {
    const config_file = try std.fs.cwd().openFile("config.ini", .{});
    defer config_file.close();

    const config = try Config.init(allocator, config_file.reader());
    defer config.deinit(allocator);

    var ui = try SDLUI.init(allocator, config.graphics.fullscreen, config.graphics.use_gpu);
    defer ui.deinit();

    var audio_device: ?SDLAudio = null;
    if (config.audio.audio_enabled) {
        audio_device = try SDLAudio.init(allocator, config.audio.audio_buffer_size, config.audio.audio_device_name);
    }
    defer if (audio_device) |*dev| dev.deinit();

    var sdl_handler = SDLHandler{ .ui = &ui };
    const handler = sdl_handler.handler();

    var m8 = try M8.init(
        allocator,
        if (audio_device) |dev| dev.audio_buffer else null,
        &handler,
        preferred_usb_device,
    );

    defer m8.deinit();

    const start = try m8.start();
    defer start.deinit();

    std.log.debug("Enable display", .{});
    try m8.enableAndResetDisplay();

    try handler.start(&m8);
}
