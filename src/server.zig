const std = @import("std");
const Config = @import("config.zig");
const builtin = @import("builtin");


pub var log_writer: ?*std.Io.Writer = null;

pub fn debugPrint(comptime fstring: []const u8, values: anytype) void {
    if (log_writer == null){
        if (builtin.mode == .Debug){
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
        return .{ .allocator = allocator, .request = request, .route = route, .io = io, .values = .init(allocator) };
    }
};

pub const State = enum {
    busy,
    err,
    waiting,
};

pub const ServerError = error{ Server, Client, Unknown, Default };

/// a handler for a route
/// http route paramaters have a ':' wilcards have '\*'
/// if a requested route matches the path  and the method the callback function is called
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
        c.request.respond(body, .{ .status = .ok, .keep_alive = false }) catch return ServerError.Server;
    }
};

pub fn sendJson(allocator: std.mem.Allocator, request: *std.http.Server.Request, object: anytype, options: std.http.Server.Request.RespondOptions) !void {
    const body = try std.json.Stringify.valueAlloc(allocator, object, .{});
    defer allocator.free(body);

    try request.respond(body, options);
}

///this function returns a 404 error
pub fn four0four(c: *Context) !void {
    const body = "<h1>NOT FOUND</h1>";
    c.request.respond(body, .{ .status = .not_found, .keep_alive = false }) catch return ServerError.Server;
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
    if (conf.hideDotFiles and std.mem.containsAtLeast(u8, request.head.target, 1, "/.")) {
        request.respond("<h1>403</h1>", .{ .status = .forbidden, .keep_alive = false }) catch return ServerError.Server;
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
    request.respond(body, .{ .status = .ok, .keep_alive = false }) catch return ServerError.Server;
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
    pub fn route(self: Router, io: std.Io, request: *std.http.Server.Request, allocator: std.mem.Allocator) anyerror!void {
        for (self.routes.items) |*r| {
            const query = std.mem.indexOf(u8, request.head.target, "?") orelse request.head.target.len;
            if (r.match(request.head.target[0..query], request.head.method)) {
                var c: Context = try .init(request, r, allocator, io);

                debugPrint("match: {s}\n", .{r.path});
                r.run(&c) catch |err| {
                    debugPrint("error: {}\n", .{err});
                    return;
                };
                return;
            }
        }
        var c: Context = try .init(request, &notFound, allocator, io);
        notFound.callback(&c) catch return ServerError.Server;
        return;
    }
};

/// this is here to allow or disalow the static function from serving dotfiles
var conf: *Config = undefined;

/// A wrapper around std.Io.net.Server with builtin multithreading, arena based memory management and routing
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
        const tcp_server = try addr.listen(io, .{});
        conf = settings;
        return .{ .settings = settings, .allocator = allocator, .io = io, .address = addr, .server = tcp_server, .lock = std.Io.Mutex.init };
    }

    /// listen on the address and port indicated from the provided config, dispatch requests via the router to the provided routes
    pub fn runServer(self: *Server, router: Router) !void {
        //const allocator = self.allocator;
        var server = self.server;
        defer server.deinit(self.io);
        var buf: [1024]u8 = undefined;

        var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), self.io, &buf);
        const stdout = &stdout_file_writer.interface;

        try stdout.print("Listening on http://{s}\n", .{self.settings.address});

        var state: State = .waiting;
        const worker_count: usize = self.settings.workers;
        const workers: []std.Thread = try self.allocator.alloc(std.Thread, worker_count);
        const worker_states = try self.allocator.alloc(State, worker_count);
        defer self.allocator.free(workers);
        defer self.allocator.free(worker_states);

        // Initialize worker states
        // Spawn workers
        for (0..worker_count) |i| {
            debugPrint("Spawning worker: {}\n", .{i + 1});
            workers[i] = try std.Thread.spawn(.{}, listen, .{ self, i, &worker_states[i], router });
        }

        // Monitor and respawn threads if they finish
        while (true) {
            var idle_count: usize = 0;

            for (0..worker_count) |i| {
                // error state
                if (worker_states[i] == .waiting) {
                    idle_count += 1;
                }
                if (worker_states[i] == .err) {
                    debugPrint("Worker {d} stopped. Restarting...\n", .{i + 1});
                    workers[i] = try std.Thread.spawn(.{}, listen, .{ self, i, &worker_states[i], router });
                }
            }
            if (self.should_close == true and idle_count >= worker_count) {
                for (0..worker_count) |i| {
                    debugPrint("Killing worker: {}\n", .{i + 1});
                }
                std.process.exit(0);
            }

            _ = try std.Io.sleep(self.io, std.Io.Duration.fromMilliseconds(1000), std.Io.Clock.real);
        }
        try self.listen(0, &state, router);
    }

    /// should normally not be called directly, intead call runServer
    pub fn listen(self: *Server, id: usize, state: *State, router: Router) !void {
        const io = self.io;

        var recv_buffer: [4096]u8 = undefined;
        var send_buffer: [4096]u8 = undefined;

        state.* = .waiting;
        errdefer state.* = .err; // on error this thread will be killed and replaced
        debugPrint("path {s}\n", .{router.routes.items[0].path});
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        while (!self.should_close) {
            var stream = try self.server.accept(io);
            var connection_reader = stream.reader(io, &recv_buffer);
            var connection_writer = stream.writer(io, &send_buffer);
            var server: std.http.Server = .init(&connection_reader.interface, &connection_writer.interface);
            debugPrint("{d} - {any}\n", .{ id, state });
            state.* = .waiting;
            state.* = .busy; // tell the parent server that we are answering a request
            // Fixed: Create reader and writer from connection.stream

            if (self.should_close) {
                return;
            }
            var request = try server.receiveHead();
            //print which path we are reaching
            debugPrint("Worker #{d}: {s} \n", .{ id, request.head.target });
            // this is to ensure clean memory usage but can be bypassed in config.json
            try router.route(self.io, &request, arena.allocator());
            state.* = .waiting;
            _ = arena.reset(.free_all);
        }
    }
};

/// this struct is used to parse []const u8 into a given type
pub const Parser = struct {
    ///parse a json encoded string to a provided type
    ///will automatically find the body in an http request.
    pub fn json(T: type, allocator: std.mem.Allocator, request: *std.http.Server.Request) !T {
        const buf = try allocator.alloc(u8, 4096);
        defer allocator.free(buf);
        const reader = try request.readerExpectContinue(buf);

        // Read the body
        const body = try reader.readAlloc(allocator, request.head.content_length.?);
        defer allocator.free(body);

        // Parse the JSON body - this creates a copy of the data
        const parsed = try std.json.parseFromSlice(T, allocator, body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always, // Force allocation of strings
        });

        // Don't free parsed here - the caller needs to call parsed.deinit()
        return parsed.value;
    }

    // parse cookies to a stringhashmap
    pub fn parseCookies(allocator: std.mem.Allocator, request: *std.http.Server.Request) !std.StringHashMap([]const u8) {
        var cookies = std.StringHashMap([]const u8).init(allocator);
        var it = request.iterateHeaders();
        var ele = it.next();
        while (ele != null) {
            if (std.mem.eql(u8, ele.?.name, "Cookie")) {
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
            if (t == null){
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
        var temp_body = std.ArrayList(u8){};
        defer temp_body.deinit(allocator);

        var new_body = std.ArrayList(u8){};
        defer new_body.deinit(allocator);
        try new_body.appendSlice(allocator, body);

        inline for (0..encoded_values.len) |i| {
            const l = encoded_values[i];
            var pieces = std.mem.tokenizeSequence(u8, new_body.items, l);
            while (pieces.peek() != null) {
                try temp_body.appendSlice(allocator, pieces.next().?);
                if (pieces.peek() != null) {
                    try temp_body.appendSlice(allocator, decoded_values[i]);
                }
            }
            new_body.clearRetainingCapacity();
            try new_body.appendSlice(allocator, temp_body.items);
            temp_body.clearRetainingCapacity();
        }
        const out = try new_body.toOwnedSlice(allocator);
        return out;
    }
};
