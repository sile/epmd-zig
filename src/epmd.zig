const std = @import("std");
const net = std.net;
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;

const TAG_DUMP_REQ: u8 = 100;
const TAG_KILL_REQ: u8 = 107;
const TAG_NAMES_REQ: u8 = 110;
const TAG_ALIVE2_X_RESP: u8 = 118;
const TAG_PORT2_RESP: u8 = 119;
const TAG_ALIVE2_REQ: u8 = 120;
const TAG_ALIVE2_RESP: u8 = 121;
const TAG_PORT_PLEASE2_REQ: u8 = 122;

pub const NodeEntry = struct {
    const Self = @This();

    allocator: Allocator,

    name: []u8,
    port: u16,
    node_type: u8,
    protocol: u8,
    highest_version: u16,
    lowest_version: u16,
    extra: []u8,

    pub fn deinit(self: Self) void {
        self.allocator.free(self.name);
        self.allocator.free(self.extra);
    }
};

pub const EpmdClient = struct {
    const Self = @This();

    connection: net.Stream,

    pub fn connect(epmd_addr: net.Address) !Self {
        const connection = try net.tcpConnectToAddress(epmd_addr);
        return Self{ .connection = connection };
    }

    pub fn getNode(self: Self, node_name: []u8, allocator: Allocator) !?NodeEntry {
        // Request.
        const size = @intCast(u16, 1 + node_name.len);
        try self.writeU16(size);
        try self.writeU8(TAG_PORT_PLEASE2_REQ);
        try self.writeAll(node_name);

        // Response.
        const tag = try self.readU8();
        if (tag != TAG_PORT2_RESP) {
            return error.UnexpectedPortPlease2ResponseTag;
        }

        switch (try self.readU8()) {
            0 => {},
            1 => {
                return null;
            },
            else => {
                return error.PortPlease2ErrorResponse;
            },
        }

        return NodeEntry{
            .allocator = allocator,

            .port = try self.readU16(),
            .node_type = try self.readU8(),
            .protocol = try self.readU8(),
            .highest_version = try self.readU16(),
            .lowest_version = try self.readU16(),
            .name = try self.readLengthPrefixedBytes(allocator),
            .extra = try self.readLengthPrefixedBytes(allocator),
        };
    }

    pub fn getNames(self: Self, allocator: Allocator) !ArrayList(u8) {
        // Request.
        try self.writeU16(1); // length
        try self.writeU8(TAG_NAMES_REQ);

        // Response.
        _ = try self.readN(4); // EPMD port
        const names = try self.readAll(allocator);

        return names;
    }

    pub fn dump(self: Self, allocator: Allocator) !ArrayList(u8) {
        // Request.
        try self.writeU16(1); // length
        try self.writeU8(TAG_DUMP_REQ);

        // Response.
        _ = try self.readN(4); // EPMD port
        const info = try self.readAll(allocator);

        return info;
    }

    pub fn kill(self: Self, allocator: Allocator) !ArrayList(u8) {
        // Request.
        try self.writeU16(1); // length
        try self.writeU8(TAG_KILL_REQ);

        // Response.
        const result = try self.readAll(allocator);

        return result;
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

    fn readU8(self: Self) !u8 {
        const bytes = try self.readN(1);
        return bytes[0];
    }

    fn readU16(self: Self) !u16 {
        const bytes = try self.readN(2);
        return mem.readIntBig(u16, &bytes);
    }

    fn readLengthPrefixedBytes(self: Self, allocator: Allocator) ![]u8 {
        const len = try self.readU16();
        const buf = try allocator.alloc(u8, len);
        try self.readExact(buf);
        return buf;
    }

    fn readN(self: Self, comptime N: usize) ![N]u8 {
        var buf: [N]u8 = undefined;
        try self.readExact(&buf);
        return buf;
    }

    fn readExact(self: Self, buf: []u8) !void {
        var offset: usize = 0;
        while (offset < buf.len) {
            const read_size = try self.connection.read(buf[offset..]);
            if (read_size == 0) {
                return error.UnexpectedEos;
            }
            offset += read_size;
        }
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
