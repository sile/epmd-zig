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
        try self.writeInt(u16, size);
        try self.writeInt(u8, TAG_ALIVE2_REQ);
        try self.writeInt(u16, node.port);
        try self.writeInt(u8, node.node_type);
        try self.writeInt(u8, node.protocol);
        try self.writeInt(u16, node.highest_version);
        try self.writeInt(u16, node.lowest_version);
        try self.writeLengthPrefixedBytes(node.name);
        try self.writeLengthPrefixedBytes(if (node.extra) |e| e else &.{});

        // Response.
        switch (try self.readInt(u8)) {
            TAG_ALIVE2_RESP => {
                if ((try self.readInt(u8)) != 0) {
                    return error.RegisterNodeError;
                }
                const creation = try self.readInt(u16);
                return @intCast(u32, creation);
            },
            TAG_ALIVE2_X_RESP => {
                if ((try self.readInt(u8)) != 0) {
                    return error.RegisterNodeError;
                }
                const creation = try self.readInt(u32);
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
        try self.writeInt(u16, size);
        try self.writeInt(u8, TAG_PORT_PLEASE2_REQ);
        try self.writeAll(node_name);

        // Response.
        const tag = try self.readInt(u8);
        if (tag != TAG_PORT2_RESP) {
            return error.UnexpectedPortPlease2ResponseTag;
        }

        switch (try self.readInt(u8)) {
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

            .port = try self.readInt(u16),
            .node_type = try self.readInt(u8),
            .protocol = try self.readInt(u8),
            .highest_version = try self.readInt(u16),
            .lowest_version = try self.readInt(u16),
            .name = try self.readLengthPrefixedBytes(allocator),
            .extra = try self.readLengthPrefixedBytes(allocator),
        };
    }

    pub fn getNames(self: Self, allocator: Allocator) !ArrayList(u8) {
        // Request.
        try self.writeInt(u16, 1); // length
        try self.writeInt(u8, TAG_NAMES_REQ);

        // Response.
        _ = try self.readInt(u32); // EPMD port
        const names = try self.readAll(allocator);

        return names;
    }

    pub fn dump(self: Self, allocator: Allocator) !ArrayList(u8) {
        // Request.
        try self.writeInt(u16, 1); // length
        try self.writeInt(u8, TAG_DUMP_REQ);

        // Response.
        _ = try self.readInt(u32); // EPMD port
        const info = try self.readAll(allocator);

        return info;
    }

    pub fn kill(self: Self, allocator: Allocator) !ArrayList(u8) {
        // Request.
        try self.writeInt(u16, 1); // length
        try self.writeInt(u8, TAG_KILL_REQ);

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

    fn readInt(self: Self, comptime T: type) !T {
        var buf: [@sizeOf(T)]u8 = undefined;
        try self.readExact(&buf);
        return mem.readIntBig(T, &buf);
    }

    fn readLengthPrefixedBytes(self: Self, allocator: Allocator) ![]u8 {
        const len = try self.readInt(u16);
        const buf = try allocator.alloc(u8, len);
        try self.readExact(buf);
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

    fn writeInt(self: Self, comptime T: type, v: T) !void {
        const N = @sizeOf(T);
        var buf: [N]u8 = undefined;
        mem.writeIntBig(T, &buf, v);
        return self.writeAll(&buf);
    }

    fn writeLengthPrefixedBytes(self: Self, bytes: []u8) !void {
        try self.writeInt(u16, @intCast(u16, bytes.len));
        try self.writeAll(bytes);
    }

    fn writeAll(self: Self, buf: []const u8) !void {
        var written: usize = 0;
        while (written < buf.len) {
            written += try self.connection.write(buf[written..]);
        }
    }
};
