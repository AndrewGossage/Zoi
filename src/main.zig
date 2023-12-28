const std = @import("std");
const s = @import("server.zig");
const Server = s.Server;
const toml = @import("toml.zig");
const eql = std.mem.eql;
const Connection = std.net.Connection;
// this is for manual routing or creating an api
pub const Router = struct {
    pub fn testing(self: anytype, message: anytype) !void {
        _ = self;
        try message.server.sendMessage("<h1>testing</h1> This is a message from Zoi", "200 ok", message.conn);
        return;
    }

    pub fn echo(self: anytype, message: anytype) !void {
        _ = self;
        try message.server.sendMessage(&message.buf, "200 ok", message.conn);
    }

    pub fn accept(self: anytype, message: anytype) !void {
        if (eql(u8, message.url, "testing.html")) {
            try self.testing(message);
            return;
        }

        if (eql(u8, message.url, "echo.html")) {
            try self.echo(message);
            return;
        }

        try message.server.acceptFallback(message.conn, message.url);
    }
};

pub const Queue = struct {};

fn worker(server: anytype) !void {
    while (true) {

        //by default this will only handle '/testing.html' and anything else will be
        // treated as a request for a static webpage
        const router = Router{};

        // use server.accept for only static content
        server.acceptAdv(router) catch |e| {
            std.debug.print("error found: {}\n", .{e});

            continue;
        };
    }
}

pub fn server_loop() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const worker_count = try toml.getWorkerCount(allocator);
    const workers: []std.Thread = try allocator.alloc(std.Thread, worker_count);
    defer allocator.free(workers);

    const port = try toml.getPort(allocator);

    var host: [4]u8 = undefined;
    _ = try toml.getHost(&host, allocator);
    var server = try Server.init(host, port);
    defer server.deinit();

    for (0..worker_count) |i| {
        std.debug.print("Spawning worker: {}\n", .{i + 1});
        workers[i] = try std.Thread.spawn(.{}, worker, .{&server});
    }
    for (0..worker_count) |i| {
        workers[i].join();
    }
}
pub fn main() !void {
    try server_loop();
    std.debug.print("working\n", .{});
}
