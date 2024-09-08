const std = @import("std");
const zusb = @import("zusb/zusb.zig");

const stdout = std.io.getStdOut().writer();

const M8_VID = 0x16c0;
const M8_PID = 0x048a;

const EP_OUT_ADDRESS = 0x03;
const EP_IN_ADDRESS = 0x83;

const Error = error{ InvalidFileHandle, CanNotOpenDevice };

const Self = @This();

allocator: std.mem.Allocator,
context: *zusb.Context,
device_handle: *zusb.DeviceHandle,

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

        if (descriptor.vendorId() == M8_VID and descriptor.productId() == M8_PID) {
            try stdout.print("Found M8 device: {}:{}\n", .{ device.portNumber(), device.busNumber() });
        }
    }
}

pub fn init(allocator: std.mem.Allocator, preferred_device: ?[]u8) !Self {
    var context = try zusb.Context.init();
    var device_handle = if (preferred_device) |dev| try openPreferredDevice(&context, dev) else try context.openDeviceWithVidPid(M8_VID, M8_PID) orelse return Error.CanNotOpenDevice;
    std.log.info("Interfaces {}", .{device_handle.interfaces});
    try initInterface(&device_handle);
    std.log.info("Interfaces {}", .{device_handle.interfaces});
    const heap_handle = try allocator.create(zusb.DeviceHandle);
    heap_handle.* = device_handle;
    const heap_context = try allocator.create(zusb.Context);
    heap_context.* = context;
    return .{ .context = heap_context, .device_handle = heap_handle, .allocator = allocator };
}

pub fn openPreferredDevice(context: *zusb.Context, preferred_device: []u8) !zusb.DeviceHandle {
    std.log.debug("Opening with preferred device {s}\n", .{preferred_device});

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

        if (descriptor.vendorId() == M8_VID and descriptor.productId() == M8_PID) {
            if (device.portNumber() == port and device.busNumber() == bus) {
                try stdout.print("Found preferred M8 device: {}:{}\n", .{ device.portNumber(), device.busNumber() });
                return try device.open();
            }
        }
    }
    try stdout.print("Preferred device not found, using the first available device", .{});
    return try context.openDeviceWithVidPid(M8_VID, M8_PID) orelse return Error.CanNotOpenDevice;
}

pub fn initWithFile(file_handle: std.fs.File.Handle) (Error || zusb.Error)!Self {
    if (file_handle <= 0) {
        return Error.InvalidFileHandle;
    }
    try zusb.disableDeviceDiscovery();
    var context = try zusb.Context.init();
    var device_handle = try context.openDeviceWithFd(file_handle);
    try initInterface(&device_handle);
    return Self{ .context = &context, .device_handle = &device_handle };
}

fn initInterface(device_handle: *zusb.DeviceHandle) zusb.Error!void {
    std.debug.print("Claiming interfaces\n", .{});
    try device_handle.claimInterface(0);
    try device_handle.claimInterface(1);

    std.debug.print("Setting line state\n", .{});
    _ = try device_handle.writeControl(0x21, 0x22, 0x03, 0, null, 0);

    std.debug.print("Set line encoding\n", .{});
    const encoding = [_](u8){ 0x00, 0xC2, 0x01, 0x00, 0x00, 0x00, 0x08 };
    _ = try device_handle.writeControl(0x21, 0x20, 0, 0, &encoding, 0);
    std.debug.print("Interface initialisation finished\n", .{});
}

pub fn readSerial(self: *Self, buffer: []u8) zusb.Error!usize {
    return try self.device_handle.readBulk(EP_IN_ADDRESS, buffer, 100);
}

pub fn writeSerial(self: *Self, buffer: []u8) zusb.Error!usize {
    return try self.device_handle.writeBulk(EP_OUT_ADDRESS, buffer, 5);
}

pub fn resetDisplay(self: *Self) zusb.Error!void {
    std.log.info("Resetting display", .{});
    const reset = [_]u8{'R'};
    try self.writeSerial(reset);
}

pub fn enableAndResetDisplay(self: *Self) zusb.Error!void {
    std.log.info("Resetting display", .{});
    const reset = [_]u8{'E'};
    try self.writeSerial(reset);
}

pub fn disconnect(self: *Self) zusb.Error!void {
    std.log.info("Resetting display", .{});
    const reset = [_]u8{'D'};
    try self.writeSerial(reset);
}

pub fn sendController(self: *Self, input: u8) zusb.Error!void {
    std.log.info("Sending controller, input={}", .{input});
    try self.writeSerial([_]u8{ 'C', input });
}

pub fn sendKeyjazz(self: *Self, note: u8, velocity: u8) zusb.Error!void {
    std.log.info("Sending keyjazz. Note={}, velocity={}", .{ note, velocity });
    try self.writeSerial([_]u8{ 'K', note, if (velocity > 0x7F) 0x7F else velocity });
}

pub fn deinit(self: *Self) void {
    self.device_handle.deinit();
    self.context.deinit();
    self.allocator.destroy(self.device_handle);
    self.allocator.destroy(self.context);
}

pub fn handleEvents(usb: Self) !void {
    try usb.context.handleEvents();
}
