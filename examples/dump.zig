const std = @import("std");
const net = std.net;
const epmd = @import("../src/epmd.zig");

pub fn main() !void {
    const epmd_addr = net.Address.initIp4([_]u8{ 127, 0, 0, 1 }, 4369);

    var epmd_client = try epmd.EpmdClient.connect(epmd_addr);
    defer epmd_client.deinit();

    const allocator = std.heap.page_allocator;
    const info = try epmd_client.dump(allocator);
    defer info.deinit();

    std.debug.print("{s}", .{info.items});
}
