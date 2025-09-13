const std = @import("std");
const Config = @import("config.zig");
const server = @import("server.zig");
const fmt = @import("fmt.zig");
const stdout = std.io.getStdOut().writer();

pub const routes = &[_]server.Route{
    .{ .path = "/", .callback = index },
    .{ .path = "/home", .callback = index },
    .{ .path = "/styles/*", .callback = server.static },
    .{ .path = "/scripts/*", .callback = server.static },
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
