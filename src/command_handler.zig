const Command = @import("command.zig");
const M8 = @import("m8.zig");

const CommandHandler = @This();

ptr: *anyopaque,
startFn: *const fn (ptr: *anyopaque, m8: *M8) anyerror!void,
handleCommandFn:  *const fn (ptr: *anyopaque, command: Command) anyerror!void,

pub fn start(self: CommandHandler, m8: *M8) !void {
    return self.startFn(self.ptr, m8);
}

pub fn handleCommand(self: CommandHandler, command: Command) !void {
    return self.handleCommandFn(self.ptr, command);
}
