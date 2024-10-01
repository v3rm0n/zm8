const std = @import("std");
const zusb = @import("zusb");
const SDLAudio = @import("sdl/audio.zig");
const UsbAudio = @import("usb/audio.zig");
const Slip = @import("slip.zig").Slip(1024);
const Command = @import("command.zig");
const CommandHandler = @import("command_handler.zig");

const stdout = std.io.getStdOut().writer();

const m8_vid = 0x16c0;
const m8_pid = 0x048a;

const serial_endpoint_out = 0x03;
const serial_endpoint_in = 0x83;

const Error = error{ InvalidFileHandle, CanNotOpenDevice };

pub const Key = enum(u8) {
    edit = 1,
    option = 1 << 1,
    right = 1 << 2,
    play = 1 << 3,
    shift = 1 << 4,
    down = 1 << 5,
    up = 1 << 6,
    left = 1 << 7,
    _,
};

pub const KeyAction = enum(u8) {
    down = 0,
    up = 1,
};

const M8 = @This();
const UsbSerial = @import("usb/serial.zig").init(M8);

allocator: std.mem.Allocator,
context: *zusb.Context,
device_handle: *zusb.DeviceHandle,
audio: ?UsbAudio,
serial: UsbSerial,
slip: *Slip,
command_handler: *const CommandHandler,

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

pub fn init(
    allocator: std.mem.Allocator,
    audio_buffer: ?*std.RingBuffer,
    command_handler: *const CommandHandler,
    preferred_usb_device: ?[]u8,
) !M8 {
    std.log.debug("Initialising M8", .{});
    var context = try allocator.create(zusb.Context);
    errdefer allocator.destroy(context);
    context.* = zusb.Context.init() catch |err| {
        std.log.err("Libusb init failed {}\n", .{err});
        return err;
    };

    // try context.setLogLevel(zusb.LogLevel.Debug);

    const device_handle = try allocator.create(zusb.DeviceHandle);
    errdefer allocator.destroy(device_handle);
    device_handle.* = if (preferred_usb_device) |dev|
        try openPreferredDevice(context, dev)
    else
        context.openDeviceWithVidPid(m8_vid, m8_pid) catch |err| {
            std.log.err("Can not open device {}", .{err});
            return Error.CanNotOpenDevice;
        } orelse return Error.CanNotOpenDevice;

    return initWithDevice(
        allocator,
        context,
        device_handle,
        audio_buffer,
        command_handler,
    );
}

pub fn initWithFile(
    allocator: std.mem.Allocator,
    audio_buffer: ?*std.RingBuffer,
    command_handler: *const CommandHandler,
    file_handle: std.fs.File.Handle,
) (Error || zusb.Error)!M8 {
    if (file_handle <= 0) {
        return Error.InvalidFileHandle;
    }
    try zusb.disableDeviceDiscovery();

    var context = try allocator.create(zusb.Context);
    errdefer allocator.destroy(context);
    context.* = zusb.Context.init() catch |err| {
        std.log.err("Libusb init failed {}\n", .{err});
        return err;
    };

    const device_handle = try allocator.create(zusb.DeviceHandle);
    errdefer allocator.destroy(device_handle);
    device_handle.* = try context.openDeviceWithFd(file_handle);

    return initWithDevice(
        allocator,
        context,
        device_handle,
        audio_buffer,
        command_handler,
    );
}

fn initWithDevice(
    allocator: std.mem.Allocator,
    context: *zusb.Context,
    device_handle: *zusb.DeviceHandle,
    audio_buffer: ?*std.RingBuffer,
    command_handler: *const CommandHandler,
) !M8 {
    var serial = try UsbSerial.init(allocator, device_handle);
    errdefer serial.deinit();

    var audio: ?UsbAudio = null;
    if (audio_buffer) |rb| {
        audio = try UsbAudio.init(allocator, device_handle, rb);
    }
    errdefer if (audio) |*dev| dev.deinit();

    const slip = try allocator.create(Slip);
    errdefer allocator.destroy(slip);
    slip.* = try Slip.init();

    return .{
        .context = context,
        .device_handle = device_handle,
        .allocator = allocator,
        .audio = audio,
        .serial = serial,
        .slip = slip,
        .command_handler = command_handler,
    };
}

pub fn start(self: *M8) !UsbSerial.UsbSerialTransfer {
    return try self.serial.read(1024, self, readCallback);
}

fn openPreferredDevice(context: *zusb.Context, preferred_device: []u8) !zusb.DeviceHandle {
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

        if (descriptor.vendorId() == m8_vid and descriptor.productId() == m8_pid) {
            if (device.portNumber() == port and device.busNumber() == bus) {
                try stdout.print("Found preferred M8 device: {}:{}\n", .{ device.portNumber(), device.busNumber() });
                return try device.open();
            }
        }
    }
    try stdout.print("Preferred device not found, using the first available device\n", .{});
    return try context.openDeviceWithVidPid(m8_vid, m8_pid) orelse return Error.CanNotOpenDevice;
}

pub fn resetDisplay(self: *M8) zusb.Error!void {
    std.log.info("Resetting display", .{});
    const reset = [_]u8{'R'};
    try self.serial.write(&reset);
}

pub fn enableAndResetDisplay(self: *M8) zusb.Error!void {
    std.log.info("Resetting display", .{});
    const reset = [_]u8{'E'};
    try self.serial.write(&reset);
}

pub fn disconnect(self: *M8) zusb.Error!void {
    std.log.info("Resetting display", .{});
    const reset = [_]u8{'D'};
    try self.serial.write(&reset);
}

pub fn handleKey(self: *M8, opt_key: ?Key, action: KeyAction) !void {
    if (opt_key) |key| {
        std.log.debug("Handling key {}", .{key});
        switch (key) {
            .edit, .option, .right, .play, .shift, .down, .up, .left => {
                const KeyState = struct {
                    var state: u8 = 0;
                };
                switch (action) {
                    .down => KeyState.state |= @intFromEnum(key),
                    .up => KeyState.state &= ~@intFromEnum(key),
                }
                _ = try self.sendController(KeyState.state);
            },
            else => {},
        }
    }
}

pub fn sendController(self: *M8, input: u8) zusb.Error!void {
    std.log.info("Sending controller, input={}", .{input});
    try self.serial.write(&[_]u8{ 'C', input });
}

pub fn sendKeyjazz(self: *M8, note: u8, velocity: u8) zusb.Error!void {
    std.log.info("Sending keyjazz. Note={}, velocity={}", .{ note, velocity });
    try self.serial.write(&[_]u8{ 'K', note, if (velocity > 0x7F) 0x7F else velocity });
}

pub fn handleEvents(self: *M8) !void {
    try self.context.handleEvents();
}

fn readCallback(self: *M8, buffer: []const u8) void {
    const packages = self.slip.readAll(self.allocator, buffer) catch return;
    defer packages.deinit(self.allocator);
    var iterator = packages.iterator();

    while (iterator.next()) |pkg| {
        _ = self.slipPackage(pkg);
    }
}

fn slipPackage(self: *M8, buffer: []const u8) bool {
    const command = Command.parseCommand(buffer) catch |err| {
        std.log.err("Failed to parse command: {}", .{err});
        return false;
    };
    self.command_handler.handleCommand(command) catch |err| {
        std.log.err("Failed to handle command: {}", .{err});
        return false;
    };
    return true;
}

pub fn deinit(self: *M8) void {
    std.log.debug("Deiniting M8", .{});
    if (self.audio) |*audio| audio.deinit();
    self.serial.deinit();
    self.allocator.destroy(self.slip);
    self.device_handle.deinit();
    self.allocator.destroy(self.device_handle);
    self.context.deinit();
    self.allocator.destroy(self.context);
}
