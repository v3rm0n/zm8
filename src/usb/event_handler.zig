const std = @import("std");
const zusb = @import("zusb");

const EventHandler = @This();

allocator: std.mem.Allocator,
usb_thread: *std.Thread,
context: *zusb.Context,
running: bool = true,

pub fn init(allocator: std.mem.Allocator, context: *zusb.Context) !*EventHandler {
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
    while (self.running) {
        try self.context.handleEvents();
    }
}

pub fn deinit(self: *EventHandler) void {
    self.running = false;
    self.usb_thread.join();
    self.allocator.destroy(self.usb_thread);
    self.allocator.destroy(self);
}
