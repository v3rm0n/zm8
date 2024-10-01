const std = @import("std");

const SlipByte = enum(u8) {
    end = 0xC0,
    esc = 0xDB,
    esc_end = 0xDC,
    esc_esc = 0xDD,
    _,
};

const slip_error = error{ BufferOverflow, UnknownEscapedByte };

const SlipState = enum { normal, escaped };

const SlipPackages = struct {
    packages: []const []const u8,

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        for (self.packages) |pkg| {
            allocator.free(pkg);
        }
        allocator.free(self.packages);
    }

    pub fn size(self: @This()) usize {
        return self.packages.len;
    }

    pub fn iterator(self: @This()) SlipPackagesIterator {
        return .{ .packages = self.packages };
    }
};

const SlipPackagesIterator = struct {
    packages: []const []const u8,
    index: usize = 0,
    pub fn next(self: *SlipPackagesIterator) ?[]const u8 {
        const index = self.index;
        for (self.packages[index..]) |pkg| {
            self.index += 1;
            return pkg;
        }
        return null;
    }
};

pub fn Slip(
    comptime buffer_size: usize,
) type {
    const BufferType = std.BoundedArray(u8, buffer_size);

    return struct {
        const Self = @This();

        buffer: BufferType,
        state: SlipState,

        pub fn init() !Self {
            return .{
                .buffer = try BufferType.init(0),
                .state = SlipState.normal,
            };
        }

        pub fn readAll(self: *Self, allocator: std.mem.Allocator, bytes: []const u8) !SlipPackages {
            var list = std.ArrayList([]u8).init(allocator);
            defer list.deinit();

            for (bytes) |byte| {
                const maybe_package = try self.read(@enumFromInt(byte));
                if (maybe_package) |pkg| {
                    const pkg_copy = try allocator.alloc(u8, pkg.len);
                    @memcpy(pkg_copy, pkg);
                    try list.append(pkg_copy);
                }
            }

            return .{ .packages = try list.toOwnedSlice() };
        }

        fn read(self: *Self, byte: SlipByte) slip_error!?[]u8 {
            switch (self.state) {
                .normal => switch (byte) {
                    .end => {
                        defer self.reset();
                        return self.buffer.slice();
                    },
                    .esc => self.state = .escaped,
                    else => try self.byteToBuffer(byte),
                },
                .escaped => {
                    switch (byte) {
                        .esc_end => try self.byteToBuffer(.end),
                        .esc_esc => try self.byteToBuffer(.esc),
                        else => {
                            defer self.reset();
                            return slip_error.UnknownEscapedByte;
                        },
                    }
                    self.state = .normal;
                },
            }
            return null;
        }

        fn reset(slip: *Self) void {
            slip.state = .normal;
            slip.buffer.clear();
        }

        fn byteToBuffer(slip: *Self, byte: SlipByte) slip_error!void {
            slip.buffer.append(@intFromEnum(byte)) catch {
                defer slip.reset();
                return slip_error.BufferOverflow;
            };
            slip.state = .normal;
        }
    };
}

fn testSlip(input: []const u8, expected: []const u8) !void {
    const TestSlip = Slip(1024);
    var slip = try TestSlip.init();
    const packages = try slip.readAll(std.testing.allocator, input);
    defer packages.deinit(std.testing.allocator);
    var iterator = packages.iterator();
    while (iterator.next()) |pkg| {
        try std.testing.expect(pkg.len == expected.len);
        try std.testing.expect(std.mem.eql(u8, pkg, expected));
    }
}

test "normal string is parsed successfully" {
    const input: []const u8 = "Hello World" ++ [_]u8{0xC0};
    try testSlip(input, "Hello World");
}

test "escaped string containing end byte is parsed successfully" {
    const input: []const u8 = &[_]u8{ 0xDB, 0xDC, 0xC0 };
    try testSlip(input, &[_]u8{0xC0});
}

test "escaped string containing esc byte is parsed successfully" {
    const input: []const u8 = &[_]u8{ 0xDB, 0xDD, 0xC0 };
    try testSlip(input, &[_]u8{0xDB});
}
