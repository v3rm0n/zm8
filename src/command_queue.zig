const std = @import("std");
const Slip = @import("slip.zig").Slip(1024);
const Command = @import("command.zig");

const CommandQueue = std.fifo.LinearFifo(*Command, .Dynamic);
const SlipCommandQueue = @This();

allocator: std.mem.Allocator,
slip: *Slip,
queue: *CommandQueue,

pub fn init(allocator: std.mem.Allocator) !SlipCommandQueue {
    const slip = try allocator.create(Slip);
    errdefer allocator.destroy(slip);
    slip.* = try Slip.init();

    const queue = try allocator.create(CommandQueue);
    errdefer allocator.destroy(queue);
    queue.* = CommandQueue.init(allocator);

    return .{
        .allocator = allocator,
        .slip = slip,
        .queue = queue,
    };
}

pub fn deinit(self: SlipCommandQueue) void {
    while (self.queue.readItem()) |command| {
        command.deinit();
    }
    self.allocator.destroy(self.slip);
    self.queue.deinit();
    self.allocator.destroy(self.queue);
}

pub fn readItem(self: SlipCommandQueue) ?*Command {
    return self.queue.readItem();
}

pub fn writer(self: *const @This()) std.io.AnyWriter {
    return .{
        .context = self,
        .writeFn = write,
    };
}

fn write(ptr: *const anyopaque, buffer: []const u8) !usize {
    const self: *SlipCommandQueue = @constCast(@alignCast(@ptrCast(ptr)));
    var packages = try self.slip.readAll(self.allocator, buffer);
    defer packages.deinit();

    while (packages.next()) |pkg| {
        try self.queue.writeItem(try Command.parseCommand(self.allocator, pkg));
    }
    return buffer.len;
}
