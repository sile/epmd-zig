const std = @import("std");
const net = std.net;
const epmd = @import("../src/epmd.zig");
const allocator = std.heap.page_allocator;

pub fn main() !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len != 2) {
        std.debug.print("Usage: $ get-node NODE_NAME\n", .{});
        return error.InvalidCommandLineArg;
    }

    const node_name = args[1];
    const epmd_addr = net.Address.initIp4([_]u8{ 127, 0, 0, 1 }, 4369);

    var epmd_client = try epmd.EpmdClient.connect(epmd_addr);
    defer epmd_client.deinit();

    if (try epmd_client.getNode(node_name, allocator)) |node| {
        defer node.deinit();
        std.debug.print("Node:\n" ++
            "- name: {s}\n" ++
            "- port: {d}\n" ++
            "- node_type: {d}\n" ++
            "- protocol: {d}\n" ++
            "- highest_version: {d}\n" ++
            "- lowest_version: {d}\n" ++
            "- extra: {s}\n", //
            .{ node.name, node.port, node.node_type, node.protocol, node.highest_version, node.lowest_version, node.extra });
    } else {
        std.debug.print("No such node: {s}\n", .{node_name});
    }
}
