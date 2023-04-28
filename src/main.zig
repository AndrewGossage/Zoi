const std = @import("std");
const s = @import("server.zig");
const Server = s.Server;
const toml = @import("toml.zig");
pub fn server_loop() !void {
    const port = try toml.getPort();
    var host: [4]u8 = undefined;
    _ = try toml.getHost(&host);
    var server = try Server.init(host, port);
    defer server.deinit();
    while (true) {
        server.accept() catch |e| {
            std.debug.print("error found: {}\n", .{e});

            continue;
        };
    }
}
pub fn main() !void {
    try server_loop();
    std.debug.print("working\n", .{});
}
