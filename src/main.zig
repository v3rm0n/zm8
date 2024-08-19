const std = @import("std");
const GUI = @import("gui.zig");
const USB = @import("usb.zig");
const SDL = @import("sdl2");

pub fn main() !void {
    if (!USB.listDevices()) {
        return;
    }
    const usb = try USB.init();
    defer usb.destroy();

    const gui = try GUI.init(true);
    defer gui.destroy();

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
