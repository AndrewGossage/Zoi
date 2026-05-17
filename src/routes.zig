const std = @import("std");

const Config = @import("config.zig");
const fmt = @import("fmt.zig");
const server = @import("server.zig");
const Context = server.Context;
const Callback = server.Callback;

pub const routes = &[_]server.Route{
    .{ .path = "/", .middleware = &[_]Callback{
        index_middleware,
    }, .callback = index },
    .{ .path = "/static/*", .callback = server.static },
    .{ .path = "/:param", .callback = param_test },

    .{ .path = "/api/:endpoint", .method = .POST, .callback = postEndpoint },
};

fn index_middleware(c: *Context) !void {
    server.debugPrint("Hit the middleware\n", .{});
    try c.put("foo", "bar");
}

fn index(c: *Context) !void {
    server.debugPrint("value from the middleware '{s}'\n", .{c.get("foo").?});

    var value: []const u8 = "This is a template string, use a query string to replace it. (?value=something)";
    const query = server.Parser.query(struct { value: ?[]const u8 }, c.allocator, c.request);
    if (query != null) {
        const decoded = try server.Parser.urlDecode(query.?.value orelse "default", c.allocator);
        value = try fmt.htmlEscape(c.allocator, decoded);
    }
    const body = try fmt.renderTemplate(c.io, "./static/index.html", .{ .value = value }, c.allocator);
    defer c.allocator.free(body);
    try c.request.respond(body, .{ .status = .ok, .keep_alive = c.keep_alive });
}

const TestParams = struct {
    param: []const u8,
};

fn param_test(c: *Context) !void {
    const params = server.Parser.params(TestParams, c) catch TestParams{.param = "Could not parse"};
    try c.request.respond(params.param, .{ .status = .ok, .keep_alive = c.keep_alive });
}

const PubCounter = struct {
    value: i64,
    lock: std.Io.Mutex,
};

var pubCounter = PubCounter{
    .value = 0,
    .lock = .init,
};

const PostInput = struct {
    request: []const u8,
};
const PostResponse = struct {
    message: []const u8,
    endpoint: []const u8,
    counter: i64,
};

fn postEndpoint(c: *Context) !void {
    _ = try pubCounter.lock.lock(c.io);
    pubCounter.value += 1;
    _ = pubCounter.lock.unlock(c.io);
    const reqBody = try server.Parser.json(PostInput, c.allocator, c.request);
    const out = PostResponse{
        .message = "Hello from Zoi!",
        .endpoint = "",
        .counter = if (std.mem.eql(u8, reqBody.request, "counter")) pubCounter.value else 0,
    };
    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
    };
    try server.sendJson(c.allocator, c.request, out, .{ .status = .ok, .keep_alive = c.keep_alive, .extra_headers = headers });
}
