const std = @import("std");
const s = @import("server.zig");
const Server = s.Server;
const toml = @import("toml.zig");
const eql = std.mem.eql;

// this is for manual routing or creating an api
pub const Router = struct {
    pub fn testing(message: anytype) !void {
        try message.server.sendMessage("<h1>testing</h1>", "200 ok", message.conn);
        return;
    }
    pub fn accept(message: anytype) !void {
        if (eql(u8, message.url, "testing")) {
            try Router.testing(message);
            return;
        }

        try message.server.sendMessage("<h1>default</h1>", "200 ok", message.conn);
    }
};

pub fn server_loop() !void {
    const port = try toml.getPort();
    var host: [4]u8 = undefined;
    _ = try toml.getHost(&host);
    var server = try Server.init(host, port);
    defer server.deinit();
    while (true) {
        // route to files in cwd
        // use server.acceptAdv for manual routing
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
