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
    // return index.html to the home route
    const body = try template.render("index.html", .{ .value = "This is a template string" }, allocator);

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
    pubCounter.lock.lock();
    pubCounter.value += 1;
    pubCounter.lock.unlock();
    const reqBody = try server.Parser.json(PostInput, allocator, request.server.read_buffer);
    defer allocator.destroy(request);
    try stdout.print("request {s}\n", .{reqBody.request});
    const point = server.param(request.head.target, 1);
    const out = PostResponse{
        .message = "Hello from Zoi!",
        .endpoint = point orelse "",
        .counter = if (std.mem.eql(u8, reqBody.request, "counter")) pubCounter.value else std.time.timestamp(),
    };
    const body = try std.json.stringifyAlloc(allocator, out, .{});
    defer allocator.free(body);
    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
    };

    try request.respond(body, .{ .status = .ok, .keep_alive = false, .extra_headers = headers });
}

const PubCounter = struct {
    value: i64,
    lock: std.Thread.Mutex,
};

var pubCounter = PubCounter{
    .value = 0,
    .lock = .{},
};

const PostResponse = struct {
    message: []const u8,
    endpoint: []const u8,
    counter: i64,
};

const PostInput = struct {
    request: []const u8,
};
