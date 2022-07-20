const std = @import("std");
const net = std.net;
const erldist = @import("../src/erldist.zig");

pub fn main() !void {
    const epmd_addr = net.Address.initIp4([_]u8{ 127, 0, 0, 1 }, 4369);

    var epmd_client = try erldist.epmd.EpmdClient.new(epmd_addr);
    defer epmd_client.deinit();

    const allocator = std.heap.page_allocator;
    const names = try epmd_client.getNames(allocator);
    defer names.deinit();

    std.debug.print("{s}", .{names.items});
}
