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
        var hash = std.StringHashMap([]const u8).init(message.allocator);
        defer hash.deinit();
        try hash.put("Custom-Header", "testing");
        try message.server.sendMessageWithHeaders("<h1>Hello from Zoi!</h1>", "200 ok", message.conn, hash);
        return;
    }

    pub fn echo(self: anytype, message: anytype) !void {
        _ = self;
        try message.server.sendMessage(message.body, "200 ok", message.conn);
    }

    pub fn accept(self: anytype, message: anytype) !void {
        if (eql(u8, message.url, "testing.html")) {
            try self.testing(message);
            return;
        } else if (eql(u8, message.url, "echo")) {
            try self.echo(message);
            return;
        } else {
            try message.server.acceptFallback(message.conn, message.url);
        }
    }
};

pub const Queue = struct {};

fn worker(server: anytype) !void {
    while (true) {

        //by default this will handle '/testing.html' and '/echo.html' and anything
        //else will be treated as a request for a static webpage
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
