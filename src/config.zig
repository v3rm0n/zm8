const ini = @import("ini");
const std = @import("std");

const IniMap = std.StringHashMapUnmanaged([]const u8);
const IniMaps = std.StringHashMapUnmanaged(IniMap);

const Config = @This();

const Graphics = struct {
    fullscreen: bool = true,
    use_gpu: bool = true,
    idle_ms: u32 = 100,
    wait_for_device: bool = false,
    wait_packets: u32 = 128,
};

const Audio = struct {
    audio_enabled: bool = true,
    audio_buffer_size: u32 = 4096,
    audio_device_name: []const u8 = "Default",
};

const Keyboard = struct {
    key_up: u32 = 82,
    key_left: u32 = 80,
    key_down: u32 = 81,
    key_right: u32 = 79,
    key_select: u32 = 225,
    key_select_alt: u32 = 5,
    key_start: u32 = 44,
    key_start_alt: u32 = 4,
    key_opt: u32 = 29,
    key_opt_alt: u32 = 226,
    key_edit: u32 = 27,
    key_edit_alt: u32 = 22,
    key_delete: u32 = 76,
    key_reset: u32 = 21,
};

const Gamepad = struct {
    gamepad_up: u32 = 11,
    gamepad_left: u32 = 13,
    gamepad_down: u32 = 12,
    gamepad_right: u32 = 14,
    gamepad_select: u32 = 4,
    gamepad_start: u32 = 6,
    gamepad_opt: u32 = 1,
    gamepad_edit: u32 = 0,
    gamepad_quit: u32 = 8,
    gamepad_reset: u32 = 7,

    gamepad_analog_threshold: u32 = 32766,
    gamepad_analog_invert: bool = false,
    gamepad_analog_axis_updown: i32 = 1,
    gamepad_analog_axis_leftright: i32 = 0,
    gamepad_analog_axis_start: i32 = 5,
    gamepad_analog_axis_select: i32 = 4,
    gamepad_analog_axis_opt: i32 = -1,
    gamepad_analog_axis_edit: i32 = -1,
};

graphics: Graphics,
audio: Audio,
keyboard: Keyboard,
gamepad: Gamepad,

pub fn init(
    allocator: std.mem.Allocator,
    reader: anytype,
) !Config {
    var parser = ini.parse(allocator, reader, ";#");
    defer parser.deinit();

    var config = Config{
        .graphics = .{},
        .audio = .{},
        .keyboard = .{},
        .gamepad = .{},
    };

    var ini_maps = IniMaps{};
    inline for (@typeInfo(Config).@"struct".fields) |field| {
        try ini_maps.put(allocator, field.name, IniMap{});
    }

    var section: ?[]const u8 = null;

    while (try parser.next()) |record| {
        switch (record) {
            .section => |heading| {
                if (section) |sec| {
                    allocator.free(sec);
                }
                section = try allocator.dupe(u8, heading);
            },
            .property => |kv| {
                if (section) |sec| {
                    var section_map = ini_maps.getPtr(sec) orelse {
                        std.log.err("Unknown section: {s}", .{sec});
                        continue;
                    };
                    try section_map.put(allocator, try allocator.dupe(u8, kv.key), try allocator.dupe(u8, kv.value));
                }
            },
            else => {},
        }
    }
    inline for (@typeInfo(Config).@"struct".fields) |field| {
        try iterateFields(field.type, &@field(&config, field.name), ini_maps.get(field.name));
    }
    return config;
}

fn iterateFields(comptime T: type, config_ptr: *T, ini_map: ?IniMap) !void {
    if (ini_map) |map| {
        const type_info = @typeInfo(T);
        switch (type_info) {
            .@"struct" => |struct_info| {
                inline for (struct_info.fields) |field| {
                    if (map.get(field.name)) |value| {
                        if (field.type == bool) {
                            if (std.mem.eql(u8, value, "true")) {
                                @field(config_ptr, field.name) = true;
                            } else if (std.mem.eql(u8, value, "false")) {
                                @field(config_ptr, field.name) = false;
                            }
                        } else if (field.type == u32) {
                            @field(config_ptr, field.name) = try std.fmt.parseInt(u32, value, 10);
                        } else if (field.type == i32) {
                            @field(config_ptr, field.name) = try std.fmt.parseInt(i32, value, 10);
                        } else if (field.type == []const u8) {
                            @field(config_ptr, field.name) = value;
                        }
                    }
                }
            },
            else => {
                return std.err.InvalidType;
            },
        }
    }
}

test "parses ini file" {
    const ini_content =
        \\Empty line to start
        \\[graphics]
        \\fullscreen=true
        \\use_gpu=false
        \\idle_ms=50
        \\;some comment
        \\[audio]
        \\audio_enabled=true
        \\audio_buffer_size=2048
        \\audio_device_name=Headphones
    ;
    const reader = @constCast(&std.io.fixedBufferStream(ini_content)).reader();
    const config = try Config.init(std.heap.page_allocator, reader);
    try std.testing.expect(config.graphics.fullscreen == true);
    try std.testing.expect(config.graphics.use_gpu == false);
}
