const std = @import("std");
const Config = @import("config.zig");
const builtin = @import("builtin");

pub var log_writer: ?*std.Io.Writer = null;

pub fn debugPrint(comptime fstring: []const u8, values: anytype) void {
    if (log_writer == null) {
        if (builtin.mode == .Debug) {
            std.debug.print(fstring, values);
        }
        return;
    }
    log_writer.?.print(fstring, values) catch return;
    log_writer.?.flush() catch return;
}

pub const Callback: type = *const fn (*Context) anyerror!void;

pub const Context = struct {
    request: *std.http.Server.Request,
    next: bool = true,
    keep_alive: bool = false,
    allocator: std.mem.Allocator,
    io: std.Io,
    route: *const Route,
    values: std.StringHashMap([]const u8),
    pub fn get(self: *Context, key: []const u8) ?[]const u8 {
        return self.values.get(key);
    }
    pub fn put(self: *Context, key: []const u8, value: []const u8) !void {
        try self.values.put(key, value);
    }
    pub fn init(request: *std.http.Server.Request, route: *const Route, allocator: std.mem.Allocator, io: std.Io) !Context {
        return .{ .allocator = allocator, .request = request, .route = route, .io = io, .values = .init(allocator), .keep_alive = requestKeepAlive(request) };
    }
};

pub const State = enum {
    busy,
    err,
    waiting,
};

pub const ServerError = error{ Server, Client, Unknown, Default };

fn requestKeepAlive(request: *std.http.Server.Request) bool {
    if (isUnderPressure()) return false;
    if (request.head.version != .@"HTTP/1.1") return false;
    var it = request.iterateHeaders();
    while (it.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "connection")) {
            if (std.ascii.eqlIgnoreCase(h.value, "close")) return false;
        }
    }
    return true;
}

/// a handler for a route
/// http route parameters have a ':' prefix; wildcards use '\*'
/// if a requested route matches the path and the method the callback function is called
pub const Route = struct {
    path: []const u8 = "/",
    method: std.http.Method = .GET,
    callback: Callback = default,
    middleware: ?[]const Callback = null,

    pub fn match(self: *Route, path: []const u8, m: std.http.Method) bool {
        if (m != self.method) {
            return false;
        }
        var a = std.mem.tokenizeSequence(u8, self.path, "/");
        var b = std.mem.tokenizeSequence(u8, path, "/");
        while (a.peek() != null and b.peek() != null) {
            if (std.mem.eql(u8, a.peek().?, "*")) {
                return true;
            }
            if (std.mem.startsWith(u8, a.peek().?, ":")) {
                // do nothing
            } else if (!std.mem.eql(u8, a.peek().?, b.peek().?)) {
                return false;
            }
            _ = a.next();
            _ = b.next();
        }
        if ((a.peek() == null and b.peek() != null) or (a.peek() != null and b.peek() == null)) {
            return false;
        }
        return true;
    }

    pub fn run(self: *Route, c: *Context) !void {
        if (self.middleware != null) {
            for (self.middleware.?) |middleware| {
                middleware(c) catch |err| {
                    return err;
                };
            }
        }
        try self.callback(c);
    }

    pub fn default(c: *Context) !void {
        const body = std.fmt.allocPrint(c.allocator, "hello world from {s}", .{c.request.head.target}) catch return ServerError.Server;
        c.request.respond(body, .{ .status = .ok, .keep_alive = c.keep_alive }) catch return ServerError.Server;
    }
};

pub fn sendJson(allocator: std.mem.Allocator, request: *std.http.Server.Request, object: anytype, options: std.http.Server.Request.RespondOptions) !void {
    const body = try std.json.Stringify.valueAlloc(allocator, object, .{ .emit_null_optional_fields = false });
    defer allocator.free(body);

    try request.respond(body, options);
}

///this function returns a 404 error
pub fn four0four(c: *Context) !void {
    const body = "<h1>NOT FOUND</h1>";
    c.request.respond(body, .{ .status = .not_found, .keep_alive = c.keep_alive }) catch return ServerError.Server;
}

///this function returns a 500 error
pub fn five00(request: *std.http.Server.Request, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const body = "<h1>ERROR</h1>";
    request.respond(body, .{ .status = .internal_server_error, .keep_alive = false }) catch return ServerError.Server;
}

///function for serving static files, the path on a route with this method should end with '\*' or ':<parameter>' unless only one file is meant to be served on the route
pub fn static(c: *Context) !void {
    const request = c.request;
    const allocator = c.allocator;
    if (conf.hideDotFiles and (std.mem.containsAtLeast(u8, request.head.target, 1, "/.") or
        std.mem.containsAtLeast(u8, request.head.target, 1, "/%2E") or
        std.mem.containsAtLeast(u8, request.head.target, 1, "/%2e") or
        std.mem.containsAtLeast(u8, request.head.target, 1, "/%252E") or
        std.mem.containsAtLeast(u8, request.head.target, 1, "/%252e")))
    {
        request.respond("<h1>403</h1>", .{ .status = .forbidden, .keep_alive = c.keep_alive }) catch return ServerError.Server;
        return;
    }
    debugPrint("static {s}\n", .{request.head.target[1..]});

    const file = blk: {
        if (!std.mem.containsAtLeastScalar(u8, request.head.target[1..], 1, '.')) {
            const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ request.head.target[1..], "index.html" });
            debugPrint("static {s}\n", .{path});

            break :blk std.Io.Dir.cwd().openFile(c.io, path, .{ .mode = .read_only }) catch {
                four0four(c) catch return ServerError.Server;
                return;
            };
        }

        break :blk std.Io.Dir.cwd().openFile(c.io, request.head.target[1..], .{ .mode = .read_only }) catch {
            four0four(c) catch return ServerError.Server;
            return;
        };
    };

    defer file.close(c.io);
    const file_size = try file.length(c.io);
    const body: []u8 = try allocator.alloc(u8, file_size);
    var reader = file.reader(c.io, body);
    _ = try reader.interface.readSliceAll(body);
    const target = request.head.target;
    const mime: []const u8 = if (std.mem.endsWith(u8, target, ".css"))
        "text/css"
    else if (std.mem.endsWith(u8, target, ".js"))
        "application/javascript"
    else if (std.mem.endsWith(u8, target, ".html") or std.mem.endsWith(u8, target, ".htm"))
        "text/html"
    else if (std.mem.endsWith(u8, target, ".svg"))
        "image/svg+xml"
    else if (std.mem.endsWith(u8, target, ".png"))
        "image/png"
    else if (std.mem.endsWith(u8, target, ".jpg") or std.mem.endsWith(u8, target, ".jpeg"))
        "image/jpeg"
    else if (std.mem.endsWith(u8, target, ".ico"))
        "image/x-icon"
    else if (std.mem.endsWith(u8, target, ".woff2"))
        "font/woff2"
    else if (std.mem.endsWith(u8, target, ".woff"))
        "font/woff"
    else
        "application/octet-stream";
    const cache_headers = [_]std.http.Header{
        .{ .name = "Cache-Control", .value = "public, max-age=3600" },
        .{ .name = "Content-Type", .value = mime },
    };
    request.respond(body, .{ .status = .ok, .keep_alive = c.keep_alive, .extra_headers = &cache_headers }) catch return ServerError.Server;
}

///this route returns a 404 error and is called when no other route matched
const notFound = Route{ .callback = four0four };

///this struct is a wrapper around a std.ArrayList(Route) call Router.route to find the correct route for a request
pub const Router = struct {
    routes: std.ArrayList(Route),

    pub fn init(allocator: std.mem.Allocator) !Router {
        const router = Router{
            .routes = std.ArrayList(Route).init(allocator),
        };
        return router;
    }

    pub fn deinit(self: *Router) void {
        self.routes.deinit();
    }

    /// dispatch a request to the first route with a matching path and method
    /// returns whether the connection should be kept alive
    pub fn route(self: Router, io: std.Io, request: *std.http.Server.Request, allocator: std.mem.Allocator) anyerror!bool {
        for (self.routes.items) |*r| {
            const query = std.mem.indexOf(u8, request.head.target, "?") orelse request.head.target.len;
            if (r.match(request.head.target[0..query], request.head.method)) {
                var c: Context = try .init(request, r, allocator, io);
                debugPrint("match: {s}\n", .{r.path});
                r.run(&c) catch |err| {
                    debugPrint("error: {}\n", .{err});
                    return false;
                };
                return c.keep_alive;
            }
        }
        var c: Context = try .init(request, &notFound, allocator, io);
        notFound.callback(&c) catch return false;
        return c.keep_alive;
    }
};

/// controls whether the static handler blocks dotfiles
var conf: *Config = undefined;

const queue_capacity: usize = 128;
const pressure_threshold: usize = queue_capacity * 3 / 4;
pub const keep_alive_timeout_ms: u64 = 30_000;
var active_connections: std.atomic.Value(usize) = .init(0);

pub fn isUnderPressure() bool {
    return active_connections.load(.monotonic) >= pressure_threshold;
}

/// HTTP server using std.Io.Group and a connection queue for concurrent request handling
pub const Server = struct {
    settings: *Config,
    io: std.Io,
    allocator: std.mem.Allocator,
    server: std.Io.net.Server,
    address: std.Io.net.IpAddress,
    should_close: bool = false,
    lock: std.Io.Mutex,
    pub fn triggerClose(self: *Server) !void {
        try self.lock.lock(self.io);
        self.should_close = true;
        self.lock.unlock(self.io);
    }

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        settings: *Config,
    ) !Server {
        const addr: std.Io.net.IpAddress = try .resolve(io, settings.address, settings.port);
        const tcp_server = try addr.listen(io, .{ .reuse_address = true });
        conf = settings;
        return .{ .settings = settings, .allocator = allocator, .io = io, .address = addr, .server = tcp_server, .lock = std.Io.Mutex.init };
    }

    pub fn runServer(self: *Server, router: Router) !void {
        defer self.server.deinit(self.io);

        var buf: [1024]u8 = undefined;
        var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), self.io, &buf);
        const stdout = &stdout_file_writer.interface;
        try stdout.print("Listening on http://{s}\n", .{self.settings.address});

        var queue_buf: [queue_capacity]*Conn = undefined;
        var queue = std.Io.Queue(*Conn).init(&queue_buf);

        var group: std.Io.Group = .init;
        defer group.cancel(self.io);

        group.async(self.io, acceptConnections, .{ self.io, &self.server, self.allocator, &queue });
        for (0..self.settings.workers) |_| {
            group.async(self.io, handleConnections, .{ self.io, &queue, router });
        }
        try group.await(self.io);
    }

    /// respond helper — automatically disables keep-alive when the server is under pressure
    pub fn respond(self: *const Server, c: *Context, body: []const u8, options: std.http.Server.Request.RespondOptions) !void {
        _ = self;
        var opts = options;
        if (isUnderPressure()) opts.keep_alive = false;
        try c.request.respond(body, opts);
    }

    /// sendJson helper — automatically disables keep-alive when the server is under pressure
    pub fn sendJsonResponse(self: *const Server, c: *Context, object: anytype, options: std.http.Server.Request.RespondOptions) !void {
        _ = self;
        var opts = options;
        if (isUnderPressure()) opts.keep_alive = false;
        try sendJson(c.allocator, c.request, object, opts);
    }
};

pub const Conn = struct {
    arena: std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,
    stream: std.Io.net.Stream,
    reader: std.Io.net.Stream.Reader,
    recv_buffer: [8192]u8,
    io: std.Io,
    last_active: std.Io.Clock.Timestamp,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, stream: std.Io.net.Stream) !*Conn {
        const conn = try allocator.create(Conn);
        _ = active_connections.fetchAdd(1, .monotonic);
        conn.allocator = allocator;
        conn.stream = stream;
        conn.io = io;
        conn.arena = std.heap.ArenaAllocator.init(allocator);
        conn.reader = conn.stream.reader(io, &conn.recv_buffer);
        conn.last_active = std.Io.Clock.Timestamp.now(io, .real);
        return conn;
    }

    pub fn deinit(conn: *Conn) void {
        _ = active_connections.fetchSub(1, .monotonic);
        conn.stream.close(conn.io);
        conn.arena.deinit();
        conn.allocator.destroy(conn);
    }
};

fn acceptConnections(io: std.Io, server: *std.Io.net.Server, allocator: std.mem.Allocator, queue: *std.Io.Queue(*Conn)) std.Io.Cancelable!void {
    defer queue.close(io);
    while (true) {
        const stream = server.accept(io) catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            else => continue,
        };
        const conn = Conn.init(allocator, io, stream) catch continue;
        queue.putOne(io, conn) catch |err| switch (err) {
            error.Closed => {
                conn.deinit();
                return;
            },
            error.Canceled => {
                conn.deinit();
                return error.Canceled;
            },
        };
    }
}

fn handleConnections(io: std.Io, queue: *std.Io.Queue(*Conn), router: Router) std.Io.Cancelable!void {
    var send_buffer: [65536]u8 = undefined;

    while (true) {
        const conn = queue.getOne(io) catch |err| switch (err) {
            error.Closed => return,
            error.Canceled => return error.Canceled,
        };

        // Close connections that have been idle longer than the timeout
        const elapsed = conn.last_active.durationTo(std.Io.Clock.Timestamp.now(io, .real));
        if (elapsed.raw.toMilliseconds() >= @as(i64, @intCast(keep_alive_timeout_ms))) {
            conn.deinit();
            continue;
        }

        var conn_writer = conn.stream.writer(io, &send_buffer);
        var http_server: std.http.Server = .init(&conn.reader.interface, &conn_writer.interface);

        var request = http_server.receiveHead() catch {
            conn.deinit();
            continue;
        };

        const keep_alive = router.route(io, &request, conn.arena.allocator()) catch {
            _ = conn.arena.reset(.free_all);
            conn.deinit();
            continue;
        };
        conn_writer.interface.flush() catch {};
        _ = conn.arena.reset(.free_all);

        if (keep_alive) {
            conn.last_active = std.Io.Clock.Timestamp.now(io, .real);
            queue.putOne(io, conn) catch |err| switch (err) {
                error.Closed => conn.deinit(),
                error.Canceled => {
                    conn.deinit();
                    return error.Canceled;
                },
            };
        } else {
            conn.deinit();
        }
    }
}

/// this struct is used to parse []const u8 into a given type
pub const Parser = struct {
    ///parse a json encoded string to a provided type
    ///will automatically find the body in an http request.
    pub fn json(T: type, allocator: std.mem.Allocator, request: *std.http.Server.Request) !T {
        const content_length = request.head.content_length orelse return ServerError.Client;
        if (content_length < 1) return ServerError.Client;
        const buf = try allocator.alloc(u8, 4096);
        defer allocator.free(buf);
        const reader = try request.readerExpectContinue(buf);

        const body = try reader.readAlloc(allocator, content_length);
        defer allocator.free(body);
        if (body.len < 1) return ServerError.Client;

        const parsed = try std.json.parseFromSlice(T, allocator, body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        });
        return parsed.value;
    }

    /// parse cookies to a stringhashmap
    pub fn parseCookies(allocator: std.mem.Allocator, request: *std.http.Server.Request) !std.StringHashMap([]const u8) {
        var cookies = std.StringHashMap([]const u8).init(allocator);
        var it = request.iterateHeaders();
        var ele = it.next();
        while (ele != null) {
            if (std.ascii.eqlIgnoreCase(ele.?.name, "Cookie")) {
                var i = std.mem.tokenizeSequence(u8, ele.?.value, "; ");
                while (i.peek() != null) {
                    const kv = i.peek().?;
                    const delim = std.mem.indexOfScalar(u8, kv, '=');
                    if (delim != null) {
                        const k = kv[0..delim.?];
                        const v = kv[delim.? + 1 .. kv.len];
                        debugPrint("\ncookie name: {s}\n", .{k});
                        debugPrint("\ncookie value: {s}\n", .{v});
                        try cookies.put(k, v);
                    }
                    _ = i.next();
                }
            }
            ele = it.next();
        }
        return cookies;
    }

    fn parseStringToType(T: type, str: []const u8) !T {
        return switch (T) {
            []const u8 => str,
            bool => blk: {
                if (std.mem.eql(u8, str, "true")) break :blk true;
                if (std.mem.eql(u8, str, "false")) break :blk false;
                return error.InvalidBoolean;
            },
            else => return switch (@typeInfo(T)) {
                .int => std.fmt.parseInt(T, str, 10),
                .float => std.fmt.parseFloat(T, str, 10),
                else => @compileError("Unsupported type"),
            },
        };
    }

    /// takes a request and a type and returns query params that match that type.
    pub fn query(T: type, allocator: std.mem.Allocator, request: *std.http.Server.Request) ?T {
        const qIndex = std.mem.indexOf(u8, request.head.target, "?") orelse return null;
        return keyValue(T, allocator, request.head.target[qIndex + 1 ..], "&") catch return null;
    }

    pub const ParseErrors = error{MissingField};

    /// converts params to struct
    pub fn params(T: type, c: *Context) !T {
        var x: T = undefined;
        inline for (std.meta.fields(T)) |f| {
            const name: []const u8 = f.name;
            const t = single_param(f.type, c, name[0..]) catch {
                if (@typeInfo(f.type) == .optional) {
                    @field(x, f.name) = null;
                    continue;
                } else {
                    return ParseErrors.MissingField;
                }
            };
            if (t == null) {
                if (@typeInfo(f.type) == .optional) {
                    @field(x, f.name) = null;
                    continue;
                } else {
                    return ParseErrors.MissingField;
                }
            }

            @field(x, f.name) = t.?;
        }
        return x;
    }

    /// fetches single param from url
    pub fn single_param(T: type, c: *Context, key: []const u8) !?T {
        var foo = std.mem.tokenizeScalar(u8, c.route.path, '/');
        var bar = std.mem.tokenizeScalar(u8, c.request.head.target, '/');
        while (foo.peek() != null and bar.peek() != null) {
            const a = foo.peek();
            if (std.mem.eql(u8, a.?[1..], key)) {
                const decoded = try urlDecode(bar.peek().?, c.allocator);
                return try parseStringToType(T, decoded);
            }
            _ = foo.next();
            _ = bar.next();
        }
        return null;
    }

    /// this function parses key value pairs, memory is leaky so an arena is suggested
    pub fn keyValue(T: type, allocator: std.mem.Allocator, buffer: []const u8, sep: []const u8) !T {
        var x: T = undefined;
        var tokens = std.mem.tokenizeSequence(u8, buffer, sep);
        while (tokens.peek() != null) {
            inline for (std.meta.fields(T)) |f| {
                // to be safe we need to set nullable values first to null;
                if (@typeInfo(f.type) == .optional) {
                    @field(x, f.name) = null;
                }
                const token = tokens.peek().?;
                const l = try std.fmt.allocPrint(allocator, "{s}=", .{f.name});
                defer allocator.free(l);
                if (std.mem.startsWith(u8, token, l)) {
                    const i = f.name.len + 1;
                    if (f.type == []const u8 or f.type == ?[]const u8) {
                        debugPrint("string \n", .{});
                        const field = try allocator.alloc(u8, token.len - i);
                        std.mem.copyForwards(u8, field, token[i..]);
                        @field(x, f.name) = field;
                    } else {
                        @field(x, f.name) = try parseStringToType(f.type, token[i..]);
                    }
                }
            }
            _ = tokens.next();
        }
        return x;
    }

    const encoded_values = [_][]const u8{
        "%20",
        "%21",
        "%22",
        "%23",
        "%24",
        "%25",
        "%26",
        "%27",
        "%28",
        "%29",
        "%2A",
        "%2B",
        "%2C",
        "%2D",
        "%2E",
        "%2F",
        "%3A",
        "%3B",
        "%3C",
        "%3D",
        "%3E",
        "%3F",
        "%40",
        "%5B",
        "%5C",
        "%5D",
        "%5E",
        "%5F",
        "%60",
        "%7B",
        "%7C",
        "%7D",
        "%7E",
    };

    const decoded_values = [_][]const u8{
        " ",
        "!",
        "\"",
        "#",
        "$",
        "%",
        "&",
        "'",
        "(",
        ")",
        "*",
        "+",
        ",",
        "-",
        ".",
        "/",
        ":",
        ";",
        "<",
        "=",
        ">",
        "?",
        "@",
        "[",
        "\\",
        "]",
        "^",
        "_",
        "`",
        "{",
        "|",
        "}",
        "~",
    };

    pub fn urlDecode(
        body: []const u8,
        allocator: std.mem.Allocator,
    ) ![]const u8 {
        var temp_body = try std.ArrayList(u8).initCapacity(allocator, 256);
        defer temp_body.deinit(allocator);

        var new_body = try std.ArrayList(u8).initCapacity(allocator, 256);
        defer new_body.deinit(allocator);
        try new_body.appendSlice(allocator, body);

        inline for (0..encoded_values.len) |i| {
            const l = encoded_values[i];
            var pieces = std.mem.splitSequence(u8, new_body.items, l);
            var first = true;
            while (pieces.next()) |piece| {
                if (!first) try temp_body.appendSlice(allocator, decoded_values[i]);
                try temp_body.appendSlice(allocator, piece);
                first = false;
            }
            new_body.clearRetainingCapacity();
            try new_body.appendSlice(allocator, temp_body.items);
            temp_body.clearRetainingCapacity();
        }
        const out = try new_body.toOwnedSlice(allocator);
        return out;
    }
};
