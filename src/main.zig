const std = @import("std");
const Config = @import("config.zig");
const server = @import("server.zig");
const r = @import("routes.zig");


pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var threaded = std.Io.Threaded.init(allocator, .{ .stack_size = 262144 });
    defer threaded.deinit();
    const io = threaded.io();

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_file_writer: std.Io.File.Writer = .init(.stderr(), io, &stderr_buffer);
    const stderr_writer = &stderr_file_writer.interface;
    server.log_writer = stderr_writer;

    var settings = try Config.init(io, "config.json", allocator);
    defer settings.deinit(allocator);

    var routes = std.ArrayList(server.Route).empty;
    try routes.appendSlice(allocator, r.routes);
    defer routes.deinit(allocator);
    var s = try server.Server.init(allocator, io, &settings);

    try s.runServer(.{ .routes = routes });
}
