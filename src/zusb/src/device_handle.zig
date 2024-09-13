const c = @import("c.zig");
const std = @import("std");
const Context = @import("context.zig").Context;
const Device = @import("device.zig").Device;
const fromLibusb = @import("constructor.zig").fromLibusb;

const err = @import("error.zig");

pub const DeviceHandle = struct {
    ctx: *Context,
    raw: *c.libusb_device_handle,
    interfaces: u256,

    pub fn deinit(self: *DeviceHandle) void {
        std.log.info("Deiniting device handle. Interfaces {}", .{self.interfaces});

        var iface: u9 = 0;
        while (iface < 256) : (iface += 1) {
            if ((self.interfaces & (@as(u256, 1) << @truncate(iface))) != 0) {
                std.log.info("Releasing interface {}", .{iface});
                _ = c.libusb_release_interface(self.raw, @as(c_int, iface));
            }
        }
        std.log.debug("Closing device handle", .{});
        c.libusb_close(self.raw);
    }

    pub fn claimInterface(self: *DeviceHandle, iface: u8) err.Error!void {
        std.log.info("Claiming interface {}", .{iface});
        if (c.libusb_kernel_driver_active(self.raw, @as(c_int, iface)) == 1) {
            std.log.info("Detaching kernel driver from interface {}", .{iface});
            try err.failable(c.libusb_detach_kernel_driver(self.raw, @as(c_int, iface)));
        }
        try err.failable(c.libusb_claim_interface(self.raw, @as(c_int, iface)));
        self.interfaces |= @as(u256, 1) << iface;
    }

    pub fn releaseInterface(self: *DeviceHandle, iface: u8) err.Error!void {
        std.log.info("Releasing interface {}", .{iface});
        try err.failable(c.libusb_release_interface(self.raw, @as(c_int, iface)));
        self.interfaces &= ~(@as(u256, 1) << iface);
    }

    pub fn device(self: DeviceHandle) Device {
        return fromLibusb(Device, .{ self.ctx, c.libusb_get_device(self.raw).? });
    }

    pub fn setInterfaceAltSetting(self: DeviceHandle, iface: u8, setting: u8) err.Error!void {
        std.log.info("Setting interface {} alt setting {}", .{ iface, setting });
        try err.failable(c.libusb_set_interface_alt_setting(self.raw, @as(c_int, iface), @as(c_int, setting)));
    }

    pub fn writeControl(
        self: DeviceHandle,
        requestType: u8,
        request: u8,
        value: u16,
        index: u16,
        buf: ?[]const u8,
        timeout_ms: u64,
    ) (error{Overflow} || err.Error)!usize {
        if (requestType & c.LIBUSB_ENDPOINT_DIR_MASK != c.LIBUSB_ENDPOINT_OUT) {
            return error.InvalidParam;
        }

        const res = if (buf != null)
            c.libusb_control_transfer(
                self.raw,
                requestType,
                request,
                value,
                index,
                @ptrFromInt(@intFromPtr(buf.?.ptr)),
                std.math.cast(u16, buf.?.len) orelse return error.Overflow,
                std.math.cast(c_uint, timeout_ms) orelse return error.Overflow,
            )
        else
            c.libusb_control_transfer(
                self.raw,
                requestType,
                request,
                value,
                index,
                null,
                0,
                std.math.cast(c_uint, timeout_ms) orelse return error.Overflow,
            );

        if (res < 0) {
            return err.errorFromLibusb(res);
        } else {
            return @intCast(res);
        }
    }

    pub fn readBulk(
        self: DeviceHandle,
        endpoint: u8,
        buf: []u8,
        timeout_ms: u64,
    ) (error{Overflow} || err.Error)!usize {
        if (endpoint & c.LIBUSB_ENDPOINT_DIR_MASK != c.LIBUSB_ENDPOINT_IN) {
            return error.InvalidParam;
        }

        var transferred: c_int = undefined;

        const ret = c.libusb_bulk_transfer(
            self.raw,
            endpoint,
            buf.ptr,
            std.math.cast(c_int, buf.len) orelse return error.Overflow,
            &transferred,
            std.math.cast(c_uint, timeout_ms) orelse return error.Overflow,
        );

        if (ret == 0 or (ret == c.LIBUSB_ERROR_TIMEOUT and transferred > 0)) {
            return @intCast(transferred);
        } else {
            return err.errorFromLibusb(ret);
        }
    }

    pub fn writeBulk(
        self: DeviceHandle,
        endpoint: u8,
        buf: []const u8,
        timeout_ms: u64,
    ) (error{Overflow} || err.Error)!usize {
        if (endpoint & c.LIBUSB_ENDPOINT_DIR_MASK != c.LIBUSB_ENDPOINT_OUT) {
            return error.InvalidParam;
        }

        var transferred: c_int = undefined;

        const ret = c.libusb_bulk_transfer(
            self.raw,
            endpoint,
            @ptrFromInt(@intFromPtr(buf.ptr)),
            std.math.cast(c_int, buf.len) orelse return error.Overflow,
            &transferred,
            std.math.cast(c_uint, timeout_ms) orelse return error.Overflow,
        );

        if (ret == 0 or (ret == c.LIBUSB_ERROR_TIMEOUT and transferred > 0)) {
            return @intCast(transferred);
        } else {
            return err.errorFromLibusb(ret);
        }
    }
};
