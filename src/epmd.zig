const std = @import("std");
const net = std.net;
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;

const TAG_NAMES_REQ: u8 = 110;

pub const EpmdClient = struct {
    const Self = @This();

    connection: net.Stream,

    pub fn new(epmd_addr: net.Address) !Self {
        const connection = try net.tcpConnectToAddress(epmd_addr);
        return Self{ .connection = connection };
    }

    pub fn getNames(self: *Self, allocator: Allocator) !ArrayList(u8) {
        // Request.
        try self.writeU16(1); // length
        try self.writeU8(TAG_NAMES_REQ);

        // Response.
        _ = try self.readN(4); // EPMD port
        const names = try self.readAll(allocator);

        return names;
    }

    pub fn deinit(self: Self) void {
        self.connection.close();
    }

    fn readAll(self: Self, allocator: Allocator) !ArrayList(u8) {
        var bytes = ArrayList(u8).init(allocator);
        var buf: [1024]u8 = undefined;
        while (true) {
            const read_size = try self.connection.read(&buf);
            if (read_size == 0) {
                break;
            }
            try bytes.appendSlice(buf[0..read_size]);
        }
        return bytes;
    }

    fn readN(self: Self, comptime N: usize) ![N]u8 {
        var buf: [N]u8 = undefined;
        var offset: usize = 0;
        while (offset < buf.len) {
            const read_size = try self.connection.read(buf[offset..]);
            if (read_size == 0) {
                return error.UnexpectedEos;
            }
            offset += read_size;
        }
        return buf;
    }

    fn writeU8(self: Self, v: u8) !void {
        return self.writeAll(&[_]u8{v});
    }

    fn writeU16(self: Self, v: u16) !void {
        var buf = [_]u8{ 0, 0 };
        mem.writeIntBig(u16, &buf, v);
        return self.writeAll(&buf);
    }

    fn writeAll(self: Self, buf: []const u8) !void {
        var written: usize = 0;
        while (written < buf.len) {
            written += try self.connection.write(buf[written..]);
        }
    }
};
