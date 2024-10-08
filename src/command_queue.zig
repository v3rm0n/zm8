const std = @import("std");
const Command = @import("command.zig");
const CommandTag = @import("command.zig").CommandTag;

const CommandDoublyLinkedList = std.DoublyLinkedList(*Command);

const CommandQueue = @This();

allocator: std.mem.Allocator,
queue: CommandDoublyLinkedList,
mutex: std.Thread.Mutex,

pub fn init(allocator: std.mem.Allocator) !CommandQueue {
    return .{
        .allocator = allocator,
        .queue = CommandDoublyLinkedList{},
        .mutex = std.Thread.Mutex{},
    };
}

pub fn push(self: *CommandQueue, command: *Command) !void {
    const node = try self.allocator.create(CommandDoublyLinkedList.Node);
    node.* = .{ .data = command };
    self.mutex.lock();
    defer self.mutex.unlock();
    self.queue.append(node);
}

pub fn pop(self: *CommandQueue) !?*Command {
    self.mutex.lock();
    defer self.mutex.unlock();
    const node = self.queue.pop();
    if (node) |n| {
        defer self.allocator.destroy(n);
        return n.data;
    }
    return null;
}

pub fn deinit(self: *CommandQueue) void {
    while (self.queue.pop()) |node| {
        node.data.deinit();
        self.allocator.destroy(node);
    }
}

fn testCommand() !Command {
    return try Command.parseCommand(std.testing.allocator, &[_]u8{ 0xFC, 0xF0, 0xF1, 0xF2, 0xAA });
}

test "queue push and pop" {
    var queue = try CommandQueue.init(std.testing.allocator);
    defer queue.deinit();

    try std.testing.expect(try queue.pop() == null);

    var command = try testCommand();
    defer command.deinit();
    try queue.push(command);

    const command2 = try queue.pop();
    defer std.testing.allocator.destroy(command2.?);
    try std.testing.expect(command2 != null);

    try std.testing.expect(std.meta.activeTag(command2.?.data) == .oscilloscope);
    try std.testing.expect(command2.?.data.oscilloscope.color.r == 0xF0);
    try std.testing.expect(command2.?.data.oscilloscope.color.g == 0xF1);
    try std.testing.expect(command2.?.data.oscilloscope.color.b == 0xF2);
    try std.testing.expect(command2.?.data.oscilloscope.waveform.len == 1);
}

test "non empty queue will be freed automatically" {
    var queue = try CommandQueue.init(std.testing.allocator);
    defer queue.deinit();

    var command = try testCommand();
    defer command.deinit();

    try queue.push(command);
}

test "works with multiple threads" {
    const allocator = std.heap.page_allocator;

    var queue = try CommandQueue.init(allocator);
    defer queue.deinit();

    // Push commands from the main thread
    var data_buffer = [_]u8{ 0xFF, 0x01, 0x02, 0x03, 0x04, 0x01 };
    const command = try Command.parseCommand(std.testing.allocator, &data_buffer);
    defer command.deinit();
    for (1..5) |_| {
        try queue.push(command);
    }

    for (0..data_buffer.len) |i| {
        data_buffer[i] = 0xFF;
    }

    var thread = try std.Thread.spawn(.{}, workerThread, .{&queue});
    // Wait for the worker thread to finish
    thread.join();
}

fn workerThread(queue: *CommandQueue) !void {
    for (1..5) |_| {
        const command = try queue.pop();
        if (command) |cmd| {
            try std.testing.expect(cmd.data.system.fontMode == .large);
            try std.testing.expect(cmd.data.system.version.major == 0x02);
            try std.testing.expect(cmd.data.system.version.minor == 0x03);
        }
    }
}
