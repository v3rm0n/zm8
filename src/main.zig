const std = @import("std");
const M8 = @import("m8.zig");
const Sdl = @import("sdl.zig");
const usb = @import("usb/device.zig");
const serial = @import("serialport/device.zig");
const config = @import("config");
const builtin = @import("builtin");

const stdout = std.io.getStdOut().writer();

pub const os = if (builtin.os.tag != .emscripten and builtin.os.tag != .wasi) std.os else struct {
    pub const heap = struct {
        pub const page_allocator = std.heap.c_allocator;
    };
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("Memory leak");
    }

    if (builtin.os.tag == .emscripten) {
        try Sdl.startWebSerial(allocator);
        return;
    }

    std.log.debug("Processing arguments", .{});
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    var preferred_usb_device: ?[]u8 = null;
    if (args.len == 2 and std.mem.eql(u8, args[1], "--list")) {
        if (config.use_libusb) {
            try usb.listDevices();
        } else {
            try serial.listDevices();
        }
        return;
    }
    if (args.len == 3 and std.mem.eql(u8, args[1], "--dev")) {
        preferred_usb_device = args[2];
        std.log.info("Preferred device set to {s}", .{preferred_usb_device.?});
    }
    std.log.debug("Arguments processed", .{});
    if (config.use_libusb) {
        try Sdl.startUsb(allocator, preferred_usb_device);
    } else {
        try Sdl.startSerialPort(allocator, preferred_usb_device);
    }
}
