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

pub const NODE_TYPE_NORMAL: u8 = 72;
pub const NODE_TYPE_HIDDEN: u8 = 77;

pub const PROTOCOL_TCP_IP_V4: u8 = 0;

pub const DEFAULT_HIGHEST_VERSION: u16 = 6;
pub const DEFAULT_LOWEST_VERSION: u16 = 5;

pub const NodeEntry = struct {
    const Self = @This();

    allocator: ?Allocator = null,

    name: []u8,
    port: u16,
    node_type: u8 = NODE_TYPE_NORMAL,
    protocol: u8 = PROTOCOL_TCP_IP_V4,
    highest_version: u16 = DEFAULT_HIGHEST_VERSION,
    lowest_version: u16 = DEFAULT_LOWEST_VERSION,
    extra: ?[]u8 = null,

    pub fn deinit(self: Self) void {
        if (self.allocator) |allocator| {
            allocator.free(self.name);
            if (self.extra) |extra| {
                allocator.free(extra);
            }
        }
    }

    fn len(self: Self) usize {
        return @sizeOf(u16) + self.name.len +
            @sizeOf(@TypeOf(self.port)) +
            @sizeOf(@TypeOf(self.node_type)) +
            @sizeOf(@TypeOf(self.protocol)) +
            @sizeOf(@TypeOf(self.highest_version)) +
            @sizeOf(@TypeOf(self.lowest_version)) +
            @sizeOf(u16) + if (self.extra) |e| e.len else 0;
    }
};

pub const Creation = u32;

pub const EpmdClient = struct {
    const Self = @This();

    connection: net.Stream,

    pub fn connect(epmd_addr: net.Address) !Self {
        const connection = try net.tcpConnectToAddress(epmd_addr);
        return Self{ .connection = connection };
    }

    pub fn registerNode(self: Self, node: NodeEntry) !Creation {
        // Request.
        const size = @intCast(u16, 1 + node.len());
        try self.writeU16(size);
        try self.writeU8(TAG_ALIVE2_REQ);
        try self.writeU16(node.port);
        try self.writeU8(node.node_type);
        try self.writeU8(node.protocol);
        try self.writeU16(node.highest_version);
        try self.writeU16(node.lowest_version);
        try self.writeLengthPrefixedBytes(node.name);
        try self.writeLengthPrefixedBytes(if (node.extra) |e| e else &.{});

        // Response.
        switch (try self.readU8()) {
            TAG_ALIVE2_RESP => {
                if ((try self.readU8()) != 0) {
                    return error.RegisterNodeError;
                }
                const creation = try self.readU16();
                return @intCast(u32, creation);
            },
            TAG_ALIVE2_X_RESP => {
                if ((try self.readU8()) != 0) {
                    return error.RegisterNodeError;
                }
                const creation = try self.readU32();
                return creation;
            },
            else => {
                return error.UnexpectedAlive2ResponseTag;
            },
        }
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

    fn readU32(self: Self) !u32 {
        const bytes = try self.readN(4);
        return mem.readIntBig(u32, &bytes);
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

    fn writeLengthPrefixedBytes(self: Self, bytes: []u8) !void {
        try self.writeU16(@intCast(u16, bytes.len));
        try self.writeAll(bytes);
    }

    fn writeAll(self: Self, buf: []const u8) !void {
        var written: usize = 0;
        while (written < buf.len) {
            written += try self.connection.write(buf[written..]);
        }
    }
};
