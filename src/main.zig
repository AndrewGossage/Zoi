const std = @import("std");
const s = @import("server.zig");
const Server = s.Server;
pub fn server_loop() !void {
    while (true) {
        var server = try Server.init(8080);
        defer server.deinit();

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
