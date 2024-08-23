const c = @import("c.zig");
const err = @import("error.zig");

pub fn disableDeviceDiscovery() err.Error!void {
    try err.failable(c.libusb_set_option(null, c.LIBUSB_OPTION_NO_DEVICE_DISCOVERY));
}
