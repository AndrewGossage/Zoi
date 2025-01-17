const std = @import("std");
const Config = @import("config.zig");
const server = @import("server.zig");
const template = @import("template.zig");
const stdout = std.io.getStdOut().writer();

pub const routes = &[_]server.Route{
    .{ .path = "/", .callback = index },
    .{ .path = "/", .method = .POST, .callback = postEndpoint },
    .{ .path = "/styles/*", .callback = server.static },
    .{ .path = "/scripts/*", .callback = server.static },
    .{ .path = "/api/:endpoint", .callback = getEndpoint },
    .{ .path = "/api/:endpoint", .method = .POST, .callback = postEndpoint },
};

fn index(request: *std.http.Server.Request, allocator: std.mem.Allocator) !void {
    const body = try template.render("index.html", .{ .header = "Hello,", .paragraph = "world!", .foo = "foo" }, allocator);
    defer allocator.free(body);

    try request.respond(body, .{ .status = .ok, .keep_alive = false });
}

fn getEndpoint(request: *std.http.Server.Request, allocator: std.mem.Allocator) !void {
    const Response = struct {
        message: []const u8,
        id: usize,
    };

    const out = Response{
        .message = "Hello from Zoi!",
        .id = 1,
    };
    const body = try std.json.stringifyAlloc(allocator, out, .{});
    defer allocator.free(body);
    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
    };

    try request.respond(body, .{ .status = .ok, .keep_alive = false, .extra_headers = headers });
}

fn postEndpoint(request: *std.http.Server.Request, allocator: std.mem.Allocator) !void {
    const Response = struct {
        message: []const u8,
        endpoint: []const u8,
        id: usize,
    };

    const point = server.param(request.head.target, 1);
    const out = Response{
        .message = "Hello from Zoi!",
        .endpoint = point orelse "",
        .id = 1,
    };
    const body = try std.json.stringifyAlloc(allocator, out, .{});
    defer allocator.free(body);
    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
    };

    try request.respond(body, .{ .status = .ok, .keep_alive = false, .extra_headers = headers });
}
