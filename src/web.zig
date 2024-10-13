const std = @import("std");
const builtin = @import("builtin");
const SDL = @import("sdl2");
const SDLUI = @import("sdl/ui.zig");
const M8 = @import("m8.zig");
const Sdl = @import("sdl.zig");
const WebSerial = @import("webserial/serial.zig");

pub const os = if (builtin.os.tag != .emscripten and builtin.os.tag != .wasi) std.os else struct {
    pub const heap = struct {
        pub const page_allocator = std.heap.c_allocator;
    };
};

pub fn main() !void {
    var gp = std.heap.GeneralPurposeAllocator(.{
        .safety = true,
    }){};
    defer _ = gp.deinit();
    const allocator = gp.allocator();

    std.debug.print("STARTED!\n", .{});

    try SDL.init(.{ .video = true });
    defer SDL.quit();

    var ui = try SDLUI.init(false, true);
    defer ui.deinit();

    const serial = WebSerial.init();

    var m8 = try M8.init(allocator, serial.writer(), serial.reader());
    defer m8.deinit();

    std.log.debug("Enable display", .{});
    try m8.enableAndResetDisplay();

    try Sdl.startMainLoop(allocator, &ui, &m8, 10);
}
