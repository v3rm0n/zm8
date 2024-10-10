const std = @import("std");
const M8 = @import("m8.zig");
const Sdl = @import("sdl.zig");
const dev = @import("usb/device.zig");

const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("Memory leak");
    }

    std.log.debug("Processing arguments", .{});
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    var preferred_usb_device: ?[]u8 = null;
    if (args.len == 2 and std.mem.eql(u8, args[1], "--list")) {
        try dev.listDevices();
        return;
    }
    if (args.len == 3 and std.mem.eql(u8, args[1], "--dev")) {
        preferred_usb_device = args[2];
        std.log.info("Preferred device set to {s}", .{preferred_usb_device.?});
    }
    std.log.debug("Arguments processed", .{});
    try Sdl.start(allocator, preferred_usb_device);
}
