const std = @import("std");
const zusb = @import("zusb");
const SDLAudio = @import("sdl/audio.zig");
const UsbAudio = @import("usb/audio.zig");
const UsbEventHandler = @import("usb/event_handler.zig");
const Slip = @import("slip.zig").Slip(1024);
const Command = @import("command.zig");
const CommandQueue = @import("command_queue.zig");
const dev = @import("usb/device.zig");

const stdout = std.io.getStdOut().writer();

const m8_vid = 0x16c0;
const m8_pid = 0x048a;

const serial_endpoint_out = 0x03;
const serial_endpoint_in = 0x83;

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
command_queue: *CommandQueue,
usb_thread: *UsbEventHandler,

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
    preferred_usb_device: ?[]u8,
    context: *zusb.Context,
) !M8 {
    std.log.debug("Initialising M8", .{});

    const device_handle = try allocator.create(zusb.DeviceHandle);
    device_handle.* = try dev.openDevice(context, preferred_usb_device, m8_vid, m8_pid);
    errdefer allocator.destroy(device_handle);

    return initWithDevice(
        allocator,
        context,
        device_handle,
        audio_buffer,
    );
}

pub fn initWithFile(
    allocator: std.mem.Allocator,
    audio_buffer: ?*std.RingBuffer,
    file_handle: std.fs.File.Handle,
    context: *zusb.Context,
) (dev.Error || zusb.Error)!M8 {
    const device_handle = try allocator.create(zusb.DeviceHandle);
    device_handle.* = try dev.openDeviceWithFile(context, file_handle);
    errdefer allocator.destroy(device_handle);

    return initWithDevice(
        allocator,
        context,
        device_handle,
        audio_buffer,
    );
}

fn initWithDevice(
    allocator: std.mem.Allocator,
    context: *zusb.Context,
    device_handle: *zusb.DeviceHandle,
    audio_buffer: ?*std.RingBuffer,
) !M8 {
    var serial = try UsbSerial.init(allocator, device_handle);
    errdefer serial.deinit();

    var audio: ?UsbAudio = null;
    if (audio_buffer) |rb| {
        audio = try UsbAudio.init(allocator, device_handle, rb);
    }
    errdefer if (audio) |*device| device.deinit();

    const slip = try allocator.create(Slip);
    errdefer allocator.destroy(slip);
    slip.* = try Slip.init();

    const queue = try allocator.create(CommandQueue);
    errdefer allocator.destroy(queue);
    queue.* = try CommandQueue.init(allocator);

    return .{
        .context = context,
        .device_handle = device_handle,
        .allocator = allocator,
        .audio = audio,
        .serial = serial,
        .slip = slip,
        .command_queue = queue,
        .usb_thread = try UsbEventHandler.init(allocator, context),
    };
}

pub fn start(self: *M8) !UsbSerial.UsbSerialTransfer {
    return try self.serial.read(1024, self, readCallback);
}

pub fn resetDisplay(self: *M8) zusb.Error!void {
    std.log.info("Resetting display", .{});
    const reset = [_]u8{'R'};
    try self.serial.write(&reset);
}

pub fn enableAndResetDisplay(self: *M8) zusb.Error!void {
    std.log.info("Enabling and resetting display", .{});
    const reset = [_]u8{'E'};
    try self.serial.write(&reset);
    std.Thread.sleep(5 * 1000);
    try self.resetDisplay();
}

pub fn disconnect(self: *M8) zusb.Error!void {
    std.log.info("Disconnecting", .{});
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

fn readCallback(self: *M8, buffer: []const u8) void {
    var packages = self.slip.readAll(self.allocator, buffer) catch return;
    defer packages.deinit();

    while (packages.next()) |pkg| {
        _ = self.slipPackage(pkg);
    }
}

fn slipPackage(self: *M8, buffer: []const u8) bool {
    const command = Command.parseCommand(self.allocator, buffer) catch |err| {
        std.log.err("Failed to parse command: {}", .{err});
        return false;
    };
    self.command_queue.push(command) catch |err| {
        std.log.err("Failed to push command to queue: {}", .{err});
        return false;
    };
    return true;
}

pub fn popCommand(self: *M8) !?*Command {
    return try self.command_queue.pop();
}

pub fn deinit(self: *M8) void {
    std.log.debug("Deiniting M8", .{});
    self.disconnect() catch |err| {
        std.log.err("Failed to disconnect: {}", .{err});
    };
    if (self.audio) |*audio| audio.deinit();
    self.serial.deinit();
    self.allocator.destroy(self.slip);
    self.device_handle.deinit();
    self.allocator.destroy(self.device_handle);
    self.command_queue.deinit();
    self.allocator.destroy(self.command_queue);
    self.usb_thread.deinit();
}
