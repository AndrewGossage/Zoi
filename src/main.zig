const std = @import("std");
const Config = @import("config.zig");
const server = @import("server.zig");
const r = @import("routes.zig");

const Foo = struct { bar: u1, foo: []const u8 };

const stdout = std.io.getStdOut().writer();
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var settings = try Config.init("config.json", allocator);
    defer settings.deinit(allocator);
    var routes = std.ArrayList(server.Route){};
    try routes.appendSlice(allocator, r.routes);
    defer routes.deinit(allocator);
    var s = try server.Server.init(&settings, allocator);
    try s.runServer(.{ .routes = routes });
}
