const std = @import("std");
const zusb = @import("zusb");
const RingBuffer = std.RingBuffer;

var pending_transfers_count: usize = 0;

const serial_endpoint_out = 0x03;
const serial_endpoint_in = 0x83;

pub fn init(comptime T: type) type {
    return struct {
        const UsbSerial = @This();

        const UserData = struct {
            serial: *UsbSerial,
            user_data: *T,
            callback: *const fn (self: *T, buffer: []const u8) void,
        };

        const Transfer = zusb.Transfer(UserData);

        pub const UsbSerialTransfer = struct {
            transfer: *Transfer,

            pub fn deinit(self: @This()) void {
                self.transfer.deinit();
            }
        };

        allocator: std.mem.Allocator,
        device_handle: *zusb.DeviceHandle,

        pub fn init(
            allocator: std.mem.Allocator,
            device_handle: *zusb.DeviceHandle,
        ) !UsbSerial {
            try initInterface(device_handle);

            return .{
                .allocator = allocator,
                .device_handle = device_handle,
            };
        }

        fn initInterface(device_handle: *zusb.DeviceHandle) zusb.Error!void {
            std.log.info("Claiming interfaces", .{});
            try device_handle.claimInterface(0);
            try device_handle.claimInterface(1);

            std.log.info("Setting line state", .{});
            _ = try device_handle.writeControl(0x21, 0x22, 0x03, 0, null, 0);

            std.log.info("Set line encoding", .{});
            const encoding = [_](u8){ 0x00, 0xC2, 0x01, 0x00, 0x00, 0x00, 0x08 };
            _ = try device_handle.writeControl(0x21, 0x20, 0, 0, &encoding, 0);
            std.log.info("Interface initialisation finished", .{});
        }

        pub fn read(
            self: *UsbSerial,
            buffer_size: usize,
            user_data: *T,
            callback: *const fn (self: *T, buffer: []const u8) void,
        ) zusb.Error!UsbSerialTransfer {
            const user_data_data = try self.allocator.create(UserData);
            user_data_data.* = UserData{ .serial = self, .user_data = user_data, .callback = callback };
            var transfer = try Transfer.fillBulk(
                self.allocator,
                self.device_handle,
                serial_endpoint_in,
                buffer_size,
                readCallback,
                user_data_data,
                50,
                .{},
            );
            try transfer.submit();
            return .{ .transfer = transfer };
        }

        fn readCallback(transfer: *Transfer) void {
            const user_data = transfer.user_data.?;
            if (transfer.transferStatus() != zusb.TransferStatus.Completed) {
                defer transfer.deinit();
                defer transfer.allocator.destroy(user_data);
                return;
            }

            user_data.callback(user_data.user_data, transfer.getData());
            transfer.submit() catch |e| std.log.err("Failed to resubmit bulk/interrupt transfer: {}", .{e});
        }

        pub fn write(
            self: *UsbSerial,
            buffer: []const u8,
        ) zusb.Error!void {
            var transfer = try Transfer.fillBulk(
                self.allocator,
                self.device_handle,
                serial_endpoint_out,
                buffer.len,
                writeCallback,
                null,
                50,
                .{},
            );
            transfer.setData(buffer);
            pending_transfers_count += 1;
            try transfer.submit();
        }

        fn writeCallback(transfer: *Transfer) void {
            defer transfer.deinit();
            pending_transfers_count -= 1;
        }

        pub fn deinit(self: *UsbSerial) void {
            std.log.debug("Deiniting Serial", .{});
            while (pending_transfers_count > 0) {
                std.log.debug("PENDING {}", .{pending_transfers_count});
                self.device_handle.ctx.handleEvents() catch |err| std.log.err("Could not handle events: {}", .{err});
            }
            self.device_handle.releaseInterface(1) catch |err| std.log.err("Could not release interface: {}", .{err});
            self.device_handle.releaseInterface(0) catch |err| std.log.err("Could not release interface: {}", .{err});
        }
    };
}
