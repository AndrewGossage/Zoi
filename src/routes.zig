const std = @import("std");
const Config = @import("config.zig");
const server = @import("server.zig");
const fmt = @import("fmt.zig");
const stdout = std.io.getStdOut().writer();

pub const routes = &[_]server.Route{
    .{ .path = "/", .callback = index },
    .{ .path = "/home", .callback = index },
    .{ .path = "/", .method = .POST, .callback = postEndpoint },
    .{ .path = "/styles/*", .callback = server.static },
    .{ .path = "/scripts/*", .callback = server.static },

    .{ .path = "/api/:endpoint", .method = .POST, .callback = postEndpoint },
};

const IndexQuery = struct {
    value: ?[]const u8,
};
/// return index.html to the home route
fn index(request: *std.http.Server.Request, allocator: std.mem.Allocator) !void {
    var value: []const u8 = "This is a template string";
    const query = server.Parser.query(IndexQuery, allocator, request);

    if (query != null) {
        value = try fmt.urlDecode(query.?.value orelse "default", allocator);
    }
    const heap = std.heap.page_allocator;
    const body = try fmt.renderTemplate("index.html", .{ .value = value }, heap);

    defer heap.free(body);
    try request.respond(body, .{ .status = .ok, .keep_alive = false });
}

const DataResponse = struct {
    userId: i32,
    id: i32,
    title: []const u8,
    body: []const u8,
};

fn postEndpoint(request: *std.http.Server.Request, allocator: std.mem.Allocator) !void {
    pubCounter.lock.lock();
    pubCounter.value += 1;
    pubCounter.lock.unlock();

    const reqBody = try server.Parser.json(PostInput, allocator, request);

    std.debug.print("rqBody: {any}\n", .{reqBody});

    std.debug.print("request {s}\n", .{reqBody.request});
    const point = server.param(request.head.target, 1);
    const out = PostResponse{
        .message = "Hello from Zoi!",
        .endpoint = point orelse "",
        .counter = if (std.mem.eql(u8, reqBody.request, "counter")) pubCounter.value else std.time.timestamp(),
    };
    _ = out;

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
    };
    _ = headers;
    const heap = std.heap.page_allocator;

    const body = try fmt.renderTemplate("index.html", .{ .value = "hi" }, heap);

    defer heap.free(body);
    try request.respond(body, .{ .status = .ok, .keep_alive = false });

    //try server.sendJson(allocator, request, out, .{ .status = .ok, .keep_alive = false, .extra_headers = headers });
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
