const std = @import("std");
const serialport = @import("libserialport/libserialport.zig");

pub const m8_vid = 0x16c0;
pub const m8_pid = 0x048a;

const stdout = std.io.getStdOut().writer();

pub fn listDevices() !void {
    var ports = try serialport.listPorts();
    while (ports.next()) |port| {
        std.log.debug("Port: {s}", .{port.getName()});
        if (port.getTransport() != .usb) {
            return;
        }
        std.log.debug("Has USB transport", .{});
        const vidPid = try port.getUsbVidPid();
        if (vidPid.vid == m8_vid and vidPid.pid == m8_pid) {
            try stdout.print("Found M8 device: {s}\n", .{port.getName()});
        }
    }
}

pub fn openDevice(preferred_serial_device: ?[]const u8) !?serialport.Port {
    _ = preferred_serial_device;
    var ports = try serialport.listPorts();
    while (ports.next()) |port| {
        if (port.getTransport() != .usb) {
            continue;
        }
        const vidPid = try port.getUsbVidPid();
        if (vidPid.vid == m8_vid and vidPid.pid == m8_pid) {
            std.log.debug("Found M8 device: {s}", .{port.getName()});
            return try port.copy();
        }
    }
    return null;
}
