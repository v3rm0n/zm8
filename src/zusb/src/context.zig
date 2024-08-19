const c = @import("c.zig");
const DeviceHandle = @import("device_handle.zig").DeviceHandle;
const DeviceList = @import("device_list.zig").DeviceList;
const fromLibusb = @import("constructor.zig").fromLibusb;

const err = @import("error.zig");

pub const Context = struct {
    raw: *c.libusb_context,
    var completed: c_int = undefined;

    pub fn init() err.Error!Context {
        var ctx: ?*c.libusb_context = null;
        try err.failable(c.libusb_init(&ctx));

        return Context{ .raw = ctx.? };
    }

    pub fn deinit(self: Context) void {
        _ = c.libusb_exit(self.raw);
    }

    pub fn devices(self: *const Context) err.Error!DeviceList {
        return DeviceList.init(self);
    }

    pub fn handleEvents(self: Context) err.Error!void {
        var timeval = c.struct_timeval{ .tv_sec = 0, .tv_usec = 0 };
        try err.failable(c.libusb_handle_events_timeout_completed(self.raw, &timeval, &completed));
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
