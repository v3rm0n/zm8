const std = @import("std");
const c = @import("c.zig");

const Error = error{ Unknown, Arguments, Fail, Memory, Unsupported };

const Ports = @This();

const PortVidPid = struct {
    vid: u16,
    pid: u16,
};

const PortTransport = enum(u8) {
    native = c.SP_TRANSPORT_NATIVE,
    usb = c.SP_TRANSPORT_USB,
    bluetooth = c.SP_TRANSPORT_BLUETOOTH,
};

const PortMode = enum(u8) {
    read = c.SP_MODE_READ,
    write = c.SP_MODE_WRITE,
    readWrite = c.SP_MODE_READ_WRITE,
};

const PortParity = enum(i8) {
    invalid = c.SP_PARITY_INVALID,
    none = c.SP_PARITY_NONE,
    odd = c.SP_PARITY_ODD,
    even = c.SP_PARITY_EVEN,
    mark = c.SP_PARITY_MARK,
    space = c.SP_PARITY_SPACE,
};

pub const PortFlowControl = enum(c_uint) {
    none = c.SP_FLOWCONTROL_NONE,
    xonXoff = c.SP_FLOWCONTROL_XONXOFF,
    rtsCts = c.SP_FLOWCONTROL_RTSCTS,
    dtrDsr = c.SP_FLOWCONTROL_DTRDSR,
};

pub const Port = struct {
    raw: *c.struct_sp_port,

    pub fn deinit(self: Port) void {
        c.sp_free_port(self.raw);
    }

    pub fn getName(self: *const Port) [*:0]const u8 {
        return c.sp_get_port_name(self.raw);
    }

    pub fn getTransport(self: *const Port) PortTransport {
        return @enumFromInt(c.sp_get_port_transport(self.raw));
    }

    pub fn getUsbVidPid(self: *const Port) !PortVidPid {
        var vid: c_int = undefined;
        var pid: c_int = undefined;
        _ = try failable(c.sp_get_port_usb_vid_pid(self.raw, &vid, &pid));
        return .{ .vid = @intCast(vid), .pid = @intCast(pid) };
    }

    pub fn copy(self: Port) !Port {
        var port_ptr: ?*c.struct_sp_port = undefined;
        _ = try failable(c.sp_copy_port(self.raw, &port_ptr));
        return .{ .raw = port_ptr.? };
    }

    pub fn open(self: Port, mode: PortMode) !void {
        _ = try failable(c.sp_open(self.raw, @intFromEnum(mode)));
    }

    pub fn close(self: Port) !void {
        _ = try failable(c.sp_close(self.raw));
    }

    pub fn setBaudRate(self: Port, baud: u32) !void {
        _ = try failable(c.sp_set_baudrate(self.raw, @intCast(baud)));
    }

    pub fn setBits(self: Port, bits: u8) !void {
        _ = try failable(c.sp_set_bits(self.raw, @intCast(bits)));
    }

    pub fn setParity(self: Port, parity: PortParity) !void {
        _ = try failable(c.sp_set_parity(self.raw, @intFromEnum(parity)));
    }

    pub fn setStopBits(self: Port, bits: u8) !void {
        _ = try failable(c.sp_set_stopbits(self.raw, @intCast(bits)));
    }

    pub fn setFlowControl(self: Port, flow: PortFlowControl) !void {
        _ = try failable(c.sp_set_flowcontrol(self.raw, @intFromEnum(flow)));
    }

    pub fn blockingWrite(self: Port, data: []const u8, timeout_ms: usize) !usize {
        return @intCast(try failable(c.sp_blocking_write(self.raw, data.ptr, data.len, @intCast(timeout_ms))));
    }

    pub fn read(self: Port, buf: []u8) !usize {
        return @intCast(try failable(c.sp_nonblocking_read(self.raw, buf.ptr, buf.len)));
    }
};

pub const PortsIterator = struct {
    raw_list: [*c]?*c.struct_sp_port,
    index: usize = 0,

    pub fn init() !PortsIterator {
        var list_ptr: [*c]?*c.struct_sp_port = undefined;
        _ = try failable(c.sp_list_ports(&list_ptr));
        return .{ .raw_list = list_ptr };
    }

    pub fn deinit(self: PortsIterator) void {
        c.sp_free_port_list(self.raw_list);
    }

    pub fn next(self: *PortsIterator) ?Port {
        const port = self.raw_list[self.index];
        if (port) |p| {
            self.index += 1;
            return .{ .raw = p };
        }
        return null;
    }
};

pub fn listPorts() !PortsIterator {
    return try PortsIterator.init();
}

pub fn libserialResult(result: c.enum_sp_return) Error {
    return switch (result) {
        c.SP_ERR_ARG => Error.Arguments,
        c.SP_ERR_FAIL => Error.Fail,
        c.SP_ERR_MEM => Error.Memory,
        c.SP_ERR_SUPP => Error.Unsupported,
        else => return Error.Unknown,
    };
}

pub fn failable(result: c.enum_sp_return) Error!c_int {
    if (result < 0) {
        const message = c.sp_last_error_message();
        defer c.sp_free_error_message(message);
        std.log.err("Error from libserialport: {s}({})", .{ message, result });
        return libserialResult(result);
    }
    return result;
}
