const std = @import("std");
const GUI = @import("gui.zig");
const USB = @import("usb.zig");
const SDL = @import("sdl2");

pub fn main() !void {
    if (!USB.listDevices()) {
        return;
    }
    const usb = try USB.init();
    defer usb.deinit();

    const gui = try GUI.init(false);
    defer gui.deinit();

    mainLoop: while (true) {
        while (SDL.pollEvent()) |ev| {
            switch (ev) {
                .quit => break :mainLoop,
                else => {},
            }
        }

        try usb.handleEvents();
    }
}
