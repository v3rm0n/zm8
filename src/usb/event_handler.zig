const std = @import("std");
const zusb = @import("zusb");

const EventHandler = @This();

allocator: std.mem.Allocator,
usb_thread: *std.Thread,
context: *zusb.Context,
running: bool = true,

pub fn init(allocator: std.mem.Allocator, context: *zusb.Context) !*EventHandler {
    std.log.debug("Creating USB event handler", .{});
    const self = try allocator.create(EventHandler);
    const usb_thread = try allocator.create(std.Thread);
    usb_thread.* = try std.Thread.spawn(.{ .allocator = allocator }, usbThread, .{self});
    self.* = .{
        .allocator = allocator,
        .usb_thread = usb_thread,
        .context = context,
    };
    return self;
}

fn usbThread(self: *EventHandler) !void {
    std.log.debug("USB thread started", .{});
    while (self.running) {
        try self.context.handleEvents();
    }
    std.log.debug("USB thread finished", .{});
}

pub fn deinit(self: *EventHandler) void {
    std.log.debug("Deiniting USB event handler", .{});
    self.running = false;
    self.usb_thread.join();
    self.allocator.destroy(self.usb_thread);
    self.allocator.destroy(self);
}
