const std = @import("std");
const zusb = @import("zusb");

const stdout = std.io.getStdOut().writer();

pub const m8_vid = 0x16c0;
pub const m8_pid = 0x048a;

const Error = error{ InvalidFileHandle, CanNotOpenDevice };

pub fn listDevices() !void {
    var context = zusb.Context.init() catch |err| {
        std.log.err("Libusb init failed {}\n", .{err});
        return err;
    };
    defer context.deinit();

    const devices = context.devices() catch |err| {
        std.log.err("Getting device list failed {}\n", .{err});
        return err;
    };
    defer devices.deinit();

    std.log.info("Devices: {}\n", .{devices.len});

    var device_list = devices.devices();

    while (device_list.next()) |device| {
        const descriptor = device.deviceDescriptor() catch |err| {
            std.log.err("Getting device descriptor failed {}\n", .{err});
            return err;
        };

        if (descriptor.vendorId() == m8_vid and descriptor.productId() == m8_pid) {
            try stdout.print("Found M8 device: {}:{}\n", .{ device.portNumber(), device.busNumber() });
        }
    }
}

pub fn openDevice(
    context: *zusb.Context,
    preferred_usb_device: ?[]const u8,
) !zusb.DeviceHandle {
    return if (preferred_usb_device) |dev|
        try openPreferredDevice(context, dev, m8_vid, m8_pid)
    else
        context.openDeviceWithVidPid(m8_vid, m8_pid) catch |err| {
            std.log.err("Can not open device {}", .{err});
            return Error.CanNotOpenDevice;
        } orelse return Error.CanNotOpenDevice;
}

pub fn openDeviceWithFile(
    context: zusb.Context,
    file_handle: std.fs.File.Handle,
) (Error || zusb.Error)!zusb.DeviceHandle {
    if (file_handle <= 0) {
        return Error.InvalidFileHandle;
    }
    try zusb.disableDeviceDiscovery();
    return try context.openDeviceWithFd(file_handle);
}

fn openPreferredDevice(
    context: *zusb.Context,
    preferred_device: []const u8,
    vid: u16,
    pid: u16,
) !zusb.DeviceHandle {
    std.log.debug("Opening with preferred device {s}", .{preferred_device});

    var split = std.mem.splitSequence(u8, preferred_device, ":");
    const port = try std.fmt.parseInt(u8, split.first(), 10);
    const bus = try std.fmt.parseInt(u8, split.next().?, 10);

    const devices = context.devices() catch |err| {
        std.log.err("Getting device list failed {}\n", .{err});
        return err;
    };
    defer devices.deinit();

    var device_list = devices.devices();

    while (device_list.next()) |device| {
        const descriptor = device.deviceDescriptor() catch |err| {
            std.log.err("Getting device descriptor failed {}\n", .{err});
            return err;
        };

        if (descriptor.vendorId() == vid and descriptor.productId() == pid) {
            if (device.portNumber() == port and device.busNumber() == bus) {
                try stdout.print("Found preferred M8 device: {}:{}\n", .{ device.portNumber(), device.busNumber() });
                return try device.open();
            }
        }
    }
    try stdout.print("Preferred device not found, using the first available device\n", .{});
    return try context.openDeviceWithVidPid(vid, pid) orelse return Error.CanNotOpenDevice;
}
