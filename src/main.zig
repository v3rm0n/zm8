const std = @import("std");
const GUI = @import("gui.zig");
const M8 = @import("m8.zig");
const SDL = @import("sdl2");
const AudioDevice = @import("audio_device.zig");
const Slip = @import("slip.zig");
const Command = @import("command.zig");

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
    start(allocator, preferred_usb_device) catch |err| {
        std.log.err("Error: {}", .{err});
    };
}

fn start(allocator: std.mem.Allocator, preferred_usb_device: ?[]u8) !void {
    var gui = try GUI.init(allocator, false);
    defer gui.deinit();

    var audio_device = try AudioDevice.init(allocator, 4096, null);
    defer audio_device.deinit();

    var m8 = try M8.init(allocator, audio_device, preferred_usb_device);
    defer m8.deinit();

    const serial_buffer = try allocator.alloc(u8, 1024);
    defer allocator.free(serial_buffer);

    var slip = try Slip.init(allocator, 1024, slipHandler, &gui);
    defer slip.deinit();

    std.log.debug("Enable display", .{});
    try m8.enableAndResetDisplay();

    std.log.info("Starting main loop", .{});
    mainLoop: while (true) {
        while (SDL.pollEvent()) |ev| {
            switch (ev) {
                .quit => break :mainLoop,
                .key_down => |key_ev| {
                    if (key_ev.keycode == SDL.Keycode.escape) {
                        try m8.resetDisplay();
                    }
                },
                else => {},
            }
        }

        const read_length = try m8.readSerial(serial_buffer);
        try slip.readAll(serial_buffer[0..read_length]);
        try m8.handleEvents();
        try gui.render();
    }
}

fn slipHandler(buffer: []u8, user_data: *const anyopaque) bool {
    const gui: *GUI = @ptrCast(@constCast(@alignCast(user_data)));
    const command = Command.parseCommand(buffer) catch |err| {
        std.log.err("Failed to parse command: {}", .{err});
        return false;
    };
    gui.handleCommand(command) catch |err| {
        std.log.err("Failed to handle command: {}", .{err});
        return false;
    };
    return true;
}
