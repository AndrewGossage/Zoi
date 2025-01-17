const std = @import("std");
const Config = @import("config.zig");
const server = @import("server.zig");
const template = @import("template.zig");
const stdout = std.io.getStdOut().writer();
const State = enum {
    busy,
    err,
    waiting,
};

fn param(s: []const u8, n: usize) ?[]const u8 {
    var out = std.mem.tokenizeSequence(u8, s, "/");
    for (0..n) |_| {
        _ = out.next();
    }
    return out.peek();
}

fn foo(request: *std.http.Server.Request, allocator: std.mem.Allocator) !void {
    const bar = param(request.head.target, 1);
    const body = try std.fmt.allocPrint(allocator, "<h1>{s}</h1>", .{bar.?});
    defer allocator.free(body);

    try request.respond(body, .{ .status = .ok, .keep_alive = false });
}

fn index(request: *std.http.Server.Request, allocator: std.mem.Allocator) !void {
    const body = try template.render("index.html", .{ .header = "Hello,", .paragraph = "world!", .foo = "foo" }, allocator);
    defer allocator.free(body);

    try request.respond(body, .{ .status = .ok, .keep_alive = false });
}

fn star(request: *std.http.Server.Request, allocator: std.mem.Allocator) !void {
    const bar = param(request.head.target, 1);
    const body = try std.fmt.allocPrint(allocator, "<h1>{s}</h1>", .{bar.?});
    defer allocator.free(body);
    try request.respond(body, .{ .status = .ok, .keep_alive = false });
}
const ROUTES = &[_]server.Route{ .{ .path = "/", .callback = index }, .{ .path = "/foo/:bar", .callback = foo }, .{ .path = "/star/*" }, .{ .path = "/styles/*", .callback = server.static } };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var settings = try Config.init("config.json", allocator);
    defer settings.deinit(allocator);
    try stdout.print("{any}\n", .{settings});
    var routes = std.ArrayList(server.Route).init(allocator);
    try routes.appendSlice(ROUTES);
    defer routes.deinit();
    var s = try server.Server.init(&settings, allocator);
    try s.runServer(.{ .routes = routes });
}
