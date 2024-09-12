const c = @import("c.zig");

const Transfer = @import("transfer.zig").Transfer;

const err = @import("error.zig");

pub const PacketDescriptors = struct {
    iter: []c.struct_libusb_iso_packet_descriptor,
    i: usize,

    pub fn init(iter: []c.struct_libusb_iso_packet_descriptor) PacketDescriptors {
        return .{ .iter = iter, .i = 0 };
    }

    pub fn next(self: *PacketDescriptors) ?PacketDescriptor {
        if (self.i < self.iter.len) {
            defer self.i += 1;
            return PacketDescriptor{ .descriptor = &self.iter[self.i], .idx = self.i };
        } else {
            return null;
        }
    }
};

pub const PacketDescriptor = struct {
    descriptor: *c.struct_libusb_iso_packet_descriptor,
    idx: usize,

    pub fn buffer(self: *const PacketDescriptor, transfer: *Transfer) []u8 {
        const c_buffer = c.libusb_get_iso_packet_buffer_simple(transfer.transfer, @intCast(self.idx));
        return c_buffer[0..self.descriptor.actual_length];
    }

    pub fn isCompleted(self: *const PacketDescriptor) bool {
        return self.descriptor.status == c.LIBUSB_TRANSFER_COMPLETED;
    }

    pub fn status(self: *const PacketDescriptor) err.Error {
        return err.errorFromLibusb(@intCast(self.descriptor.status));
    }
};
