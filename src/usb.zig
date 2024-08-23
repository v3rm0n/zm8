const std = @import("std");
const zusb = @import("zusb/zusb.zig");

const M8_VID = 0x16c0;
const M8_PID = 0x048a;

const EP_OUT_ADDRESS = 0x03;
const EP_IN_ADDRESS = 0x83;

const ACM_CTRL_DTR = 0x01;
const ACM_CTRL_RTS = 0x02;

const Error = error{ InvalidFileHandle, CanNotOpenDevice };

const USB = @This();

context: *const zusb.Context,
device_handle: *const zusb.DeviceHandle,

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

    var device_list = devices.devices();

    while (device_list.next()) |device| {
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

pub fn init() (Error || zusb.Error)!USB {
    var context = try zusb.Context.init();
    var device_handle = try context.openDeviceWithVidPid(M8_VID, M8_PID) orelse return Error.CanNotOpenDevice;
    try initInterface(&device_handle);
    return USB{ .context = &context, .device_handle = &device_handle };
}

pub fn initWithFile(file_handle: std.fs.File.Handle) (Error || zusb.Error)!USB {
    if (file_handle <= 0) {
        return Error.InvalidFileHandle;
    }
    try zusb.disableDeviceDiscovery();
    var context = try zusb.Context.init();
    var device_handle = try context.openDeviceWithFd(file_handle);
    try initInterface(&device_handle);
    return USB{ .context = &context, .device_handle = &device_handle };
}

fn initInterface(device_handle: *zusb.DeviceHandle) zusb.Error!void {
    try device_handle.claimInterface(0);
    try device_handle.claimInterface(1);

    std.debug.print("Setting line state\n", .{});
    try device_handle.writeControl(0x21, 0x22, ACM_CTRL_DTR or ACM_CTRL_RTS, 0, null, 0);

    std.debug.print("Set line encoding\n", .{});
    const encoding = [_](u8){ 0x00, 0xC2, 0x01, 0x00, 0x00, 0x00, 0x08 };
    try device_handle.writeControl(0x21, 0x20, 0, 0, encoding, 0);
}

pub fn readSerial(self: *USB, buffer: []u8) void {
    self.device_handle.readBulk(EP_IN_ADDRESS, buffer, 1);
}

pub fn writeSerial(self: *USB, buffer: []u8) void {
    self.device_handle.writeBulk(EP_OUT_ADDRESS, buffer, 1);
}

pub fn deinit(usb: USB) void {
    usb.device_handle.deinit();
    usb.context.deinit();
}

pub fn handleEvents(usb: USB) !void {
    try usb.context.handleEvents();
}
