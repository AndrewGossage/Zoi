const std = @import("std");
const Config = @import("config.zig");
pub const State = enum {
    busy,
    err,
    waiting,
};

pub const ServerError = error{ Server, Client, Unknown, Default };

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
            if (std.mem.startsWith(u8, a.peek().?, ":")) {} else if (!std.mem.eql(u8, a.peek().?, b.peek().?)) {
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
pub fn param(s: []const u8, n: usize) ?[]const u8 {
    var out = std.mem.tokenizeSequence(u8, s, "/");
    for (0..n) |_| {
        _ = out.next();
    }
    return out.peek();
}

pub fn four0four(request: *std.http.Server.Request, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const body = "<h1>NOT FOUND</h1>";
    request.respond(body, .{ .status = .not_found, .keep_alive = false }) catch return ServerError.Server;
}
pub fn five00(request: *std.http.Server.Request, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const body = "<h1>NOT FOUND</h1>";
    request.respond(body, .{ .status = .internal_server_error, .keep_alive = false }) catch return ServerError.Server;
}

pub fn static(request: *std.http.Server.Request, allocator: std.mem.Allocator) !void {
    if (conf.hideDotFiles and std.mem.containsAtLeast(u8, request.head.target, 1, "/.")) {
        std.debug.print("Refusing to serve {s}\n", .{request.head.target[1..]});

        request.respond("<h1>403</h1>", .{ .status = .forbidden, .keep_alive = false }) catch return ServerError.Server;
    }

    const file = try std.fs.cwd().openFile(request.head.target[1..], .{ .mode = .read_only });

    defer file.close();
    const file_size = try file.getEndPos();
    const body: []u8 = try allocator.alloc(u8, file_size);
    _ = try file.readAll(body);
    defer allocator.free(body);
    request.respond(body, .{ .status = .ok, .keep_alive = false }) catch return ServerError.Server;
}

pub const notFound = Route{ .callback = four0four };
pub const internalError = Route{ .callback = five00 };

pub const Router = struct {
    routes: std.ArrayList(Route),

    pub fn init(allocator: std.mem.Allocator) !Router {
        var router = Router{
            .routes = std.ArrayList(Route).init(allocator),
        };

        try router.routes.append(Route{ .path = "/hello", .callback = Route.default });

        return router;
    }

    pub fn deinit(self: *Router) void {
        self.routes.deinit();
    }

    pub fn route(self: Router, request: *std.http.Server.Request, allocator: std.mem.Allocator) anyerror!void {
        for (self.routes.items) |*r| {
            if (r.match(request.head.target, request.head.method)) {
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
var conf: *Config = undefined;

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

    pub fn runServer(self: *Server, router: Router) !void {
        //const allocator = self.allocator;
        var server = self.server;
        defer server.deinit();
        const stdout = std.io.getStdOut().writer();
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
            std.time.sleep(1 * std.time.ns_per_s); // Polling interval
        }

        try self.listen(0, &state, router);
    }

    pub fn listen(self: *Server, id: usize, state: *State, router: Router) !void {
        var server = self.server;
        const stdout = std.io.getStdOut().writer();
        state.* = .waiting;
        errdefer state.* = .err;
        try stdout.print("path {s}\n", .{router.routes.items[0].path});
        // Mark the thread as active
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        while (true) {
            try stdout.print("{d} - {any}\n", .{ id, state });
            state.* = .waiting;

            var connection = try server.accept();
            state.* = .busy;
            defer connection.stream.close();
            var buffer: [4096]u8 = undefined;

            var s = std.http.Server.init(connection, &buffer);
            var request = try s.receiveHead();

            try stdout.print("Worker #{d}: {s} \n", .{ id, request.head.target });
            if (self.settings.useArena) {
                try router.route(&request, arena.allocator());
            } else {
                try router.route(&request, self.allocator);
            }
            state.* = .waiting;
            _ = arena.reset(.retain_capacity);
        }

        // Mark the thread as finished when exiting

    }
};
