const c = @import("c.zig");
const DeviceHandle = @import("device_handle.zig").DeviceHandle;
const DeviceList = @import("device_list.zig").DeviceList;
const fromLibusb = @import("constructor.zig").fromLibusb;

const err = @import("error.zig");

pub const Option = enum(c_int) { LogLevel = 0, UseUsbdk = 1, NoDeviceDiscovery = 2, LogCb = 3, Max = 4 };

pub const Context = struct {
    raw: *c.libusb_context,

    pub fn init() err.Error!Context {
        var ctx: ?*c.libusb_context = null;
        try err.failable(c.libusb_init(&ctx));

        return Context{ .raw = ctx.? };
    }

    pub fn deinit(self: *Context) void {
        @import("std").log.debug("Deinit context", .{});
        _ = c.libusb_exit(self.raw);
        self.* = undefined;
    }

    pub fn devices(self: *Context) err.Error!DeviceList {
        return DeviceList.init(self);
    }

    pub fn handleEvents(self: Context) err.Error!void {
        try err.failable(c.libusb_handle_events_completed(self.raw, null));
    }

    pub fn openDeviceWithFd(self: *Context, fd: isize) err.Error!DeviceHandle {
        var device_handle: *c.libusb_device_handle = undefined;
        try err.failable(c.libusb_wrap_sys_device(self.raw, fd, &device_handle));
        return fromLibusb(DeviceHandle, .{ self, device_handle });
    }

    pub fn openDeviceWithVidPid(
        self: *Context,
        vendor_id: u16,
        product_id: u16,
    ) err.Error!?DeviceHandle {
        if (c.libusb_open_device_with_vid_pid(self.raw, vendor_id, product_id)) |handle| {
            return fromLibusb(DeviceHandle, .{ self, handle });
        } else {
            return null;
        }
    }
};
