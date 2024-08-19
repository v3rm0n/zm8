const std = @import("std");
const zusb = @import("zusb/zusb.zig");

const M8_VID = 0x16c0;
const M8_PID = 0x048a;

const USB = @This();

context: *const zusb.Context,

pub fn init() !USB {
    const context = try zusb.Context.init();
    return USB{ .context = &context };
}

pub fn destroy(usb: USB) void {
    usb.context.deinit();
}

pub fn listDevices() bool {
    const context = zusb.Context.init() catch |err| {
        std.debug.print("Libusb init failed {}", .{err});
        return false;
    };
    defer context.deinit();

    const devices = context.devices() catch |err| {
        std.debug.print("Getting device list failed {}", .{err});
        return false;
    };
    defer devices.deinit();

    std.debug.print("Devices: {}", .{devices.len});

    var deviceList = devices.devices();

    while (deviceList.next()) |device| {
        const descriptor = device.deviceDescriptor() catch |err| {
            std.debug.print("Getting device descriptor failed {}", .{err});
            return false;
        };

        if (descriptor.vendorId() == M8_VID and descriptor.productId() == M8_PID) {
            std.debug.print("Found M8 device: {}:{}\n", .{ device.portNumber(), device.busNumber() });
        }
    }

    return true;
}

pub fn handleEvents(usb: USB) !void {
    try usb.context.handleEvents();
}
