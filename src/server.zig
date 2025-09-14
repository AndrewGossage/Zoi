const std = @import("std");
const Config = @import("config.zig");

pub const State = enum {
    busy,
    err,
    waiting,
};

pub const ServerError = error{ Server, Client, Unknown, Default };

/// A stuct for housing an http route paramaters have a ':' wilcards are '\*'
/// if a requested route matches the path  and the method the callback function is called
pub const Route = struct {
    path: []const u8 = "/",
    method: std.http.Method = .GET,
    callback: *const fn (*std.http.Server.Request, std.mem.Allocator) anyerror!void = default,

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
        if ((a.peek() == null and b.peek() != null) or (a.peek() != null and b.next() == null)) {
            return false;
        }
        return true;
    }

    pub fn default(request: *std.http.Server.Request, allocator: std.mem.Allocator) ServerError!void {
        const body = std.fmt.allocPrint(allocator, "hello world from {s}", .{request.head.target}) catch return ServerError.Server;
        request.respond(body, .{ .status = .ok, .keep_alive = false }) catch return ServerError.Server;
    }
};

///this function returns the nth token from a url string and can be used to get parameters
pub fn param(s: []const u8, n: usize) ?[]const u8 {
    var out = std.mem.tokenizeSequence(u8, s, "/");
    for (0..n) |_| {
        _ = out.next();
    }
    return out.peek();
}

pub fn sendJson(allocator: std.mem.Allocator, request: *std.http.Server.Request, object: anytype, options: std.http.Server.Request.RespondOptions) !void {
    const body = try std.json.Stringify.valueAlloc(allocator, object, .{});
    defer allocator.free(body);

    try request.respond(body, options);
}

///this function returns a 404 error
pub fn four0four(request: *std.http.Server.Request, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const body = "<h1>NOT FOUND</h1>";
    request.respond(body, .{ .status = .not_found, .keep_alive = false }) catch return ServerError.Server;
}

///this function returns a 500 error
pub fn five00(request: *std.http.Server.Request, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const body = "<h1>ERROR</h1>";
    request.respond(body, .{ .status = .internal_server_error, .keep_alive = false }) catch return ServerError.Server;
}

///function for serving static files, the path on a route with this method should end with '\*' or ':<parameter>' unless only one file is meant to be served on the route
pub fn static(request: *std.http.Server.Request, allocator: std.mem.Allocator) !void {
    if (conf.hideDotFiles and std.mem.containsAtLeast(u8, request.head.target, 1, "/.")) {
        std.debug.print("Refusing to serve {s}\n", .{request.head.target[1..]});
        request.respond("<h1>403</h1>", .{ .status = .forbidden, .keep_alive = false }) catch return ServerError.Server;
    }
    const file = std.fs.cwd().openFile(request.head.target[1..], .{ .mode = .read_only }) catch {
        four0four(request, allocator) catch return ServerError.Server;
        return;
    };
    defer file.close();
    const file_size = try file.getEndPos();
    const body: []u8 = try allocator.alloc(u8, file_size);
    _ = try file.readAll(body);
    defer allocator.free(body);
    request.respond(body, .{ .status = .ok, .keep_alive = false }) catch return ServerError.Server;
}

///this route returns a 404 error and is called when no other route matched
const notFound = Route{ .callback = four0four };
/// this route return 500 and is called after an error.
const internalError = Route{ .callback = five00 };

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
    pub fn route(self: Router, request: *std.http.Server.Request, allocator: std.mem.Allocator) anyerror!void {
        for (self.routes.items) |*r| {
            const query = std.mem.indexOf(u8, request.head.target, "?") orelse request.head.target.len;
            if (r.match(request.head.target[0..query], request.head.method)) {
                std.debug.print("match: {s}\n", .{r.path});
                r.callback(request, allocator) catch |err| {
                    std.debug.print("error: {}\n", .{err});
                    return;
                };
            }
        }
        notFound.callback(request, allocator) catch return ServerError.Server;
        return;
    }
};

/// this is here to allow or disalow the static function from serving dotfiles
var conf: *Config = undefined;

/// A wrapper arount std.net.Server with builtin multithreading, arena based memory management and routing
pub const Server = struct {
    settings: *Config,
    allocator: std.mem.Allocator,
    server: std.net.Server,
    address: std.net.Address,

    pub fn init(
        settings: *Config,
        allocator: std.mem.Allocator,
    ) !Server {
        var address = try std.net.Address.parseIp4(settings.address, settings.port);
        const server = try address.listen(.{
            .reuse_address = true,
        });
        conf = settings;
        return .{ .settings = settings, .allocator = allocator, .address = address, .server = server };
    }

    /// listen on the address and port indicated from the provided config, dispatch requests via the router to the provided routes
    pub fn runServer(self: *Server, router: Router) !void {
        //const allocator = self.allocator;
        var server = self.server;
        defer server.deinit();
        var buf: [1000]u8 = undefined;
        var stdout = std.fs.File.writer(std.fs.File.stdout(), &buf).interface;
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
            std.debug.print("Spawning worker: {}\n", .{i + 1});
            workers[i] = try std.Thread.spawn(.{}, listen, .{ self, i, &worker_states[i], router });
        }

        // Monitor and respawn threads if they finish
        while (true) {
            for (0..worker_count) |i| {
                // error state
                if (worker_states[i] == .err) {
                    std.debug.print("Worker {d} stopped. Restarting...\n", .{i + 1});
                    workers[i] = try std.Thread.spawn(.{}, listen, .{ self, i, &worker_states[i], router });
                }
            }
            const now = std.time.milliTimestamp();
            while (std.time.milliTimestamp() - now < 1000) {}
        }
        try self.listen(0, &state, router);
    }

    /// should normally not be called directly, intead call runServer
    pub fn listen(self: *Server, id: usize, state: *State, router: Router) !void {
        var server = self.server;
        var buf: [1000]u8 = undefined;
        var stdout = std.fs.File.writer(std.fs.File.stdout(), &buf).interface;
        state.* = .waiting;
        errdefer state.* = .err; // on error this thread will be killed and replaced
        try stdout.print("path {s}\n", .{router.routes.items[0].path});
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        while (true) {
            try stdout.print("{d} - {any}\n", .{ id, state });
            state.* = .waiting;
            var connection = try server.accept();
            defer connection.stream.close();
            state.* = .busy; // tell the parent server that we are answering a request

            var buffer: [4096]u8 = undefined;
            var buff2: [4096]u8 = undefined;
            // Fixed: Create reader and writer from connection.stream
            var stream_reader = connection.stream.reader(&buffer);
            var stream_writer = connection.stream.writer(&buff2);
            var s = std.http.Server.init(stream_reader.interface(), &stream_writer.interface);
            var request = try s.receiveHead();
            //print which path we are reaching
            try stdout.print("Worker #{d}: {s} \n", .{ id, request.head.target });
            // this is to ensure clean memory usage but can be bypassed in config.json
            if (self.settings.useArena) {
                try router.route(&request, arena.allocator());
            } else {
                try router.route(&request, self.allocator);
            }
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
        // For Zig 0.15.1, we need to use readerExpectContinue properly
        const buf = try allocator.alloc(u8, 4096);
        defer allocator.free(buf);
        const reader = try request.readerExpectContinue(buf);

        // Read the body
        const body = try reader.readAlloc(allocator, request.head.content_length.?);
        defer allocator.free(body);

        std.debug.print("Body: {s}\n", .{body});

        // Parse the JSON body - this creates a copy of the data
        const parsed = try std.json.parseFromSlice(T, allocator, body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always, // Force allocation of strings
        });

        std.debug.print("Parsed: {any}\n", .{parsed});

        // Don't free parsed here - the caller needs to call parsed.deinit()
        return parsed.value;
    }
    // parses number to a given type
    fn parseStringToNum(T: type, str: []const u8) !T {
        return switch (@typeName(T)[0]) {
            'i', 'u' => try std.fmt.parseInt(T, str, 10),
            'f' => try std.fmt.parseFloat(T, str),
            else => @compileError("Unsupported type: " ++ @typeName(T)),
        };
    }

    /// this detects if a type is one of zigs arbitrary length numbers or a c number type
    /// it is not compatible with comptime types or c types
    fn isTypeNumber(T: type) bool {
        return switch (T) {
            else => {
                _ = std.fmt.parseInt(u32, @typeName(T)[1..], 10) catch return false;
                return true;
            },
        };
    }

    fn parseStringToType(T: type, str: []const u8) !T {
        std.debug.print("&{s}\n", .{@typeName(T)});
        if (isTypeNumber(T)) {
            std.debug.print("It's a number all right!\n", .{});
            return try parseStringToNum(T, str);
        }
        return switch (T) {
            // Signed integers
            []const u8 => str,
            bool => blk: {
                if (std.mem.eql(u8, str, "true")) break :blk true;
                if (std.mem.eql(u8, str, "false")) break :blk false;
                return error.InvalidBoolean;
            },
            // Characters (Assumes ASCII single character)
            // Unsupported types
            else => error.Default,
        };
    }

    /// takes a request and a type and returns query params that match that type.
    pub fn query(T: type, allocator: std.mem.Allocator, request: *std.http.Server.Request) ?T {
        const qIndex = std.mem.indexOf(u8, request.head.target, "?") orelse return null;
        return keyValue(T, allocator, request.head.target[qIndex + 1 ..], "&") catch return null;
    }

    /// this function parses key value pairs, memory is leaky so an arena is suggested
    pub fn keyValue(T: type, allocator: std.mem.Allocator, buffer: []const u8, sep: []const u8) !T {
        var x: T = undefined;
        var tokens = std.mem.tokenizeSequence(u8, buffer, sep);
        while (tokens.peek() != null) {
            inline for (std.meta.fields(T)) |f| {
                // to be safe we need to set nullable values first to null;
                if (@typeName(f.type)[0] == '?') {
                    @field(x, f.name) = null;
                }
                const token = tokens.peek().?;
                const l = try std.fmt.allocPrint(allocator, "{s}=", .{f.name});
                defer allocator.free(l);
                if (std.mem.startsWith(u8, token, l)) {
                    const i = f.name.len + 1;
                    if (f.type == []const u8 or f.type == ?[]const u8) {
                        std.debug.print("string \n", .{});
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
};
