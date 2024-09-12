const std = @import("std");
const GUI = @import("gui.zig");
const M8 = @import("m8.zig");
const SDL = @import("sdl2");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("Memory leak");
    }

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    var preferred_device: ?[]u8 = null;
    if (args.len == 2 and std.mem.eql(u8, args[1], "--list")) {
        try M8.listDevices();
        return;
    }
    if (args.len == 3 and std.mem.eql(u8, args[1], "--dev")) {
        preferred_device = args[2];
        std.log.info("Preferred device set to {s}", .{preferred_device.?});
    }

    var m8 = try M8.init(allocator, preferred_device);
    defer m8.deinit();

    const gui = try GUI.init(false);
    defer gui.deinit();

    const serial_buffer = try allocator.alloc(u8, 1024);
    defer allocator.free(serial_buffer);

    std.log.info("Starting main loop", .{});
    mainLoop: while (true) {
        while (SDL.pollEvent()) |ev| {
            switch (ev) {
                .quit => break :mainLoop,
                else => {},
            }
        }

        SDL.delay(100);
    }
}
