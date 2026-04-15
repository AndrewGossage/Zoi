const std = @import("std");
const Config = @import("config.zig");
const server = @import("server.zig");
const r = @import("routes.zig");


pub fn main(init: std.process.Init) !void {

    // first we set up a logger or else no debug logs will be shown in release mode
    const io = init.io;
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_file_writer: std.Io.File.Writer = .init(.stderr(), io, &stderr_buffer);
    const stderr_writer = &stderr_file_writer.interface;
    server.log_writer = stderr_writer;
    

    // load config from a json file
    const allocator = init.gpa;
    var settings = try Config.init(init.io, "config.json", allocator);
    defer settings.deinit(allocator);
   
    // initialize
    var routes = std.ArrayList(server.Route).empty;
    try routes.appendSlice(allocator, r.routes);
    defer routes.deinit(allocator);
    var s = try server.Server.init(init.gpa, init.io, &settings);

    // run actual exit
    try s.runServer(.{ .routes = routes });
}
