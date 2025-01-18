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
    var routes = std.ArrayList(server.Route).init(allocator);
    try routes.appendSlice(r.routes);
    defer routes.deinit();
    var s = try server.Server.init(&settings, allocator);
    try s.runServer(.{ .routes = routes });
}
