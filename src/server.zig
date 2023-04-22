const std = @import("std");
const net = std.net;
const client_msg = "Hello";
const server_msg = "HTTP/1.1 200 OK\r\n\r\n";
const eql = std.mem.eql;
const Allocator = std.mem.Allocator;
pub const Server = struct {
    stream_server: std.net.StreamServer,

    pub fn init(port: u16) !Server {
        const address = std.net.Address.initIp4([4]u8{ 127, 0, 0, 1 }, port);

        var server = std.net.StreamServer.init(.{ .reuse_address = true });
        try server.listen(address);

        std.debug.print("Listening at port {}\n", .{port});
        return Server{ .stream_server = server };
    }

    pub fn deinit(self: *Server) void {
        self.stream_server.deinit();
    }

    pub fn accept(self: *Server) !void {
        //connection over tcp
        const conn = try self.stream_server.accept();

        defer conn.stream.close();

        //first buffer for reading messages second of sending them
        var buf: [1024]u8 = undefined;
        var b: [2048]u8 = undefined;

        //get the path to the file
        const msg_size = try conn.stream.read(buf[0..]);
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();
        const slash = try read_url(&buf, allocator);
        defer slash.deinit();

        //print the message we have received
        std.debug.print("\nMessage:\n{s}\n", .{buf[0..msg_size]});

        //open the proper file
        var er404 = try std.fs.cwd().openFile("404.html", .{ .mode = .read_only });
        var file = std.fs.cwd().openFile(slash.items, .{ .mode = .read_only }) catch er404;
        defer file.close();

        //create the ArrayList for message
        var response = std.ArrayList(u8).init(allocator);
        defer response.deinit();
        //read the file
        var foo = try std.os.read(file.handle, &b);
        _ = try clean_buffer(&b, foo);
        //add status line
        try response.appendSlice("HTTP/1.1 200 OK\r\nContent-Length: 2048\r\n\r\n");

        //add page content
        try response.appendSlice(&b);
        //print items
        std.debug.print("{s}\n", .{response.items});
        // write to the stream
        const resp: []const u8 = response.items;
        _ = try conn.stream.write(resp);
    }
};
pub fn clean_buffer(buf: anytype, start: usize) !void {
    var i = start;
    // add null characters to fill a buffer
    // prevents junk from displaying on screen
    while (i < buf.len) {
        buf[i] = 0;
        i += 1;
    }
}

// parse the url from a tcp message
pub fn read_url(buf: []u8, allocator: Allocator) !std.ArrayList(u8) {
    var list = std.ArrayList(u8).init(allocator);
    var pos: usize = 1;
    // find the start of the path
    for (buf) |elem| {
        if (elem == '/') {
            break;
        }
        pos += 1;
    }
    //find the end of the path and add appropriate characters
    var end: usize = 0;
    for (buf[pos..buf.len]) |elem| {
        if (elem == ' ') {
            break;
        } else {
            try list.append(elem);
        }
        end += 1;
    }
    //print the url that we found
    std.debug.print("url:{s}\n", .{list.items});

    //default to index.html for the home page
    if (eql(u8, list.items, "")) {
        try list.appendSlice("index.html");
        std.debug.print("Caught default url", .{});
    }
    return list;
}
