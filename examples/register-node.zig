const std = @import("std");
const net = std.net;
const epmd = @import("../src/epmd.zig");
const allocator = std.heap.page_allocator;

pub fn main() !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len != 2) {
        std.debug.print("Usage: $ register-node NODE_NAME\n", .{});
        return error.InvalidCommandLineArg;
    }

    const node_name = args[1];
    const node_port = 4321;
    const epmd_addr = net.Address.initIp4([_]u8{ 127, 0, 0, 1 }, 4369);

    var epmd_client = try epmd.EpmdClient.connect(epmd_addr);
    defer epmd_client.deinit();

    const node = epmd.NodeEntry{ .name = node_name, .port = node_port };
    defer node.deinit();

    const creation = try epmd_client.registerNode(node);
    std.debug.print("Registered node: creation={d}\n\n", .{creation});
    std.debug.print("Please enter a key to terminate this process and to deregister the node.\n", .{});

    var buf: [1]u8 = undefined;
    _ = try std.io.getStdIn().read(&buf);
}
