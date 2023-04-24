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

        //create buffer for reading messages
        var buf: [1024]u8 = undefined;

        //get the path to the file
        _ = try conn.stream.read(buf[0..]);
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();
        const slash = try read_url(&buf, allocator);
        defer slash.deinit();
        if (!validate_status_line(&buf)) {
            return;
        }

        //open the proper file
        var file = std.fs.cwd().openFile(slash.items, .{ .mode = .read_only }) catch try std.fs.cwd().openFile("404.html", .{ .mode = .read_only });

        defer file.close();

        // create a buffer the correct size for the file
        const file_size = try file.getEndPos();
        const b: []u8 = try allocator.alloc(u8, file_size);
        defer allocator.free(b);

        //create the ArrayList for message
        var response = std.ArrayList(u8).init(allocator);
        defer response.deinit();

        //read the file
        var foo = try std.os.read(file.handle, b);

        //add status line
        var m = try std.fmt.allocPrint(allocator, "{d}", .{foo});
        try response.appendSlice("HTTP/1.1 200 OK\r\nContent-Length: ");
        try response.appendSlice(m);
        try response.appendSlice("\r\n\r\n");

        //add page content
        try response.appendSlice(b);

        //print items

        // write to the stream
        const resp: []const u8 = response.items;
        _ = try conn.stream.write(resp);
    }
};
// add null characters to fill a buffer
// prevents junk from displaying on screen
pub fn clean_buffer(buf: anytype, start: usize) !void {
    var i = start;

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

    //default to index.html for the home page
    if (eql(u8, list.items, "") or eql(u8, list.items, "Zoi")) {
        try list.appendSlice("index.html");
    }
    return list;
}
// make sure we are getting a valide status line
pub fn validate_status_line(buf: []u8) bool {
    if (!(eql(u8, buf[0..5], "GET /") or eql(u8, buf[0..6], "POST /"))) return false;
    const h = "HTTP/1.1\r\n";
    var it = std.mem.window(u8, buf, h.len, 1);
    while (it.next()) |slice| {
        if (eql(u8, slice, h)) {
            return true;
        } else if (slice[0] == '\r') return false;
    }

    return true;
}
