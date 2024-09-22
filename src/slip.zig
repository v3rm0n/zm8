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

const Slip = @This();

allocator: std.mem.Allocator,
buffer: []u8,
size: usize = 0,
state: SlipState = SlipState.normal,

pub fn init(
    allocator: std.mem.Allocator,
    buffer_size: usize,
) !Slip {
    const buffer = try allocator.alloc(u8, buffer_size);
    errdefer allocator.free(buffer);
    return .{
        .allocator = allocator,
        .buffer = buffer,
    };
}

pub fn deinit(self: *Slip) void {
    self.allocator.free(self.buffer);
}

pub fn readAll(self: *Slip, bytes: []const u8) !SlipPackages {
    var list = std.ArrayList([]u8).init(self.allocator);
    defer list.deinit();

    for (bytes) |byte| {
        const maybe_package = try self.read(@enumFromInt(byte));
        if (maybe_package) |pkg| {
            const pkg_copy = try self.allocator.alloc(u8, pkg.len);
            @memcpy(pkg_copy, pkg);
            try list.append(pkg_copy);
        }
    }

    return .{ .packages = try list.toOwnedSlice() };
}

fn read(self: *Slip, byte: SlipByte) slip_error!?[]u8 {
    switch (self.state) {
        .normal => switch (byte) {
            .end => {
                defer self.reset();
                return self.buffer[0..self.size];
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

fn reset(slip: *Slip) void {
    slip.state = .normal;
    slip.size = 0;
}

fn byteToBuffer(slip: *Slip, byte: SlipByte) slip_error!void {
    if (slip.size >= slip.buffer.len) {
        defer slip.reset();
        return slip_error.BufferOverflow;
    } else {
        slip.buffer[slip.size] = @intFromEnum(byte);
        slip.size += 1;
        slip.state = .normal;
    }
}

fn testSlip(input: []const u8, expected: []const u8) !void {
    var slip = try Slip.init(std.testing.allocator, 1024);
    defer slip.deinit();
    const packages = (try slip.readAll(input));
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
