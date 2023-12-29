const std = @import("std");
const net = std.net;
const client_msg = "Hello";
const server_msg = "HTTP/1.1 200 OK\r\n\r\n";
const eql = std.mem.eql;
const Allocator = std.mem.Allocator;
const toml = @import("toml.zig");
const dict = std.StringHashMap([]const u8);

pub const Server = struct {
    //create buffer for reading messages
    lock: std.Thread.Mutex,
    stream_server: std.net.StreamServer,
    gpa: @TypeOf(std.heap.GeneralPurposeAllocator(.{}){}),

    pub fn init(host: [4]u8, port: u16) !Server {
        const address = std.net.Address.initIp4(host, port);

        const gpa = std.heap.GeneralPurposeAllocator(.{}){};
        var server = std.net.StreamServer.init(.{ .reuse_address = true });
        try server.listen(address);

        //std.debug.print("Listening at {}.{}.{}.{}:{}\n", .{ host[0], host[1], host[2], host[3], port });
        return Server{
            .stream_server = server,
            .lock = .{},
            .gpa = gpa,
        };
    }

    pub fn deinit(self: *Server) void {
        self.stream_server.deinit();
        _ = self.gpa.deinit();
    }

    pub fn sendMessage(self: *Server, message: anytype, status: anytype, conn: anytype) !void {
        var gpa = self.gpa;
        const allocator = gpa.allocator();
        //create the ArrayList for message
        var response = std.ArrayList(u8).init(allocator);
        defer response.deinit();

        //add status line
        const m = try std.fmt.allocPrint(allocator, "HTTP/1.1 {s}\r\nContent-Length: {d}", .{ status, message.len });
        defer allocator.free(m);
        try response.appendSlice(m);
        try response.appendSlice("\r\n\r\n");
        try response.appendSlice(message);
        const resp: []const u8 = response.items;

        _ = try conn.stream.write(resp);
    }
    pub fn parseHeaders(self: *Server, buffer: anytype, allocator: Allocator) !dict {
        _ = self;
        var hash = dict.init(allocator);
        errdefer hash.deinit();
        try hash.put("foo", "bar");

        var it = std.mem.tokenize(u8, buffer, "\n");
        _ = it.next();
        while (it.next()) |slice| {
            const divider = std.mem.indexOf(u8, slice, ":");
            if (divider == null) {
                break;
            }
            const i = divider.? + 2;
            try hash.put(slice[0 .. i - 2], slice[i..slice.len]);
        }
        return hash;
    }

    pub fn acceptAdv(self: *Server, router: anytype) !void {
        self.lock.lock(); // make sure only one thread tries to read from the port at a time
        const message_buf: [1024]u8 = undefined;
        //connection over tcp
        const conn = self.stream_server.accept() catch |err| {
            self.lock.unlock();
            return err;
        };
        defer conn.stream.close();
        self.lock.unlock();

        var buf = message_buf;
        try clean_buffer(&buf, 0);
        //create allocator
        _ = try conn.stream.read(buf[0..]);
        std.debug.print("message: \n{s}\n\n", .{buf});
        var gpa = self.gpa;

        const allocator = gpa.allocator();
        var method = std.ArrayList(u8).init(allocator);
        defer method.deinit();
        if (eql(u8, buf[0..5], "POST /")) {
            try method.appendSlice("POST");
        } else {
            try method.appendSlice("GET");
        }

        //fetch and validate url and status line
        const url = try read_url(&buf, allocator);
        defer url.deinit();
        var headers = try self.parseHeaders(&buf, allocator);
        defer headers.deinit();

        try router.accept(.{ .method = method, .headers = headers, .server = self, .url = url.items, .buf = buf, .conn = conn, .allocator = allocator });
    }

    pub fn accept(self: *Server) !void {
        self.lock.lock(); // make sure only one thread tries to read from the port at a time
        const message_buf: [1024]u8 = undefined;
        //connection over tcp
        const conn = self.stream_server.accept() catch |err| {
            self.lock.unlock();
            return err;
        };
        defer conn.stream.close();
        self.lock.unlock();

        var buf = message_buf;
        try clean_buffer(&buf, 0);

        //create allocator
        _ = try conn.stream.read(buf[0..]);
        std.debug.print("message: \n{s}\n\n", .{buf});
        var gpa = self.gpa;

        const allocator = gpa.allocator();

        //fetch and validate url and status line
        const url = try read_url(&buf, allocator);
        defer url.deinit();

        //read file to be returned
        const b = try read_file(url.items, allocator);
        defer allocator.free(b);
        _ = b.len;

        // send response with correct status code
        if (eql(u8, url.items, "404.html")) {
            try self.sendMessage(b, "404 not found", conn);
            return;
        }
        try self.sendMessage(b, "200 ok", conn);
    }

    pub fn acceptFallback(self: *Server, conn: anytype, url: anytype) !void {
        var gpa = self.gpa;

        const allocator = gpa.allocator();

        const b = try read_file(url, allocator);
        defer allocator.free(b);
        _ = b.len;

        // send response with correct status code
        if (eql(u8, url, "404.html")) {
            try self.sendMessage(b, "404 not found", conn);
            return;
        }
        try self.sendMessage(b, "200 ok", conn);
    }

    pub fn acceptManConn(self: *Server, conn: anytype) !void {
        const message_buf: [1024]u8 = undefined;
        //connection over tcp
        defer conn.stream.close();

        var buf = message_buf;
        try clean_buffer(&buf, 0);

        //create allocator
        _ = try conn.stream.read(buf[0..]);
        std.debug.print("message: \n{s}\n\n", .{buf});
        var gpa = self.gpa;
        const allocator = gpa.allocator();

        //fetch and validate url and status line
        const url = try read_url(&buf, allocator);
        defer url.deinit();
        if (!validate_status_line(&buf)) {
            return;
        }

        //read file to be returned
        const b = try read_file(url.items, allocator);
        defer allocator.free(b);
        _ = b.len;
        try self.sendMessage(b, "200 ok", conn);
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
pub fn read_url(buf: anytype, allocator: Allocator) !std.ArrayList(u8) {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();
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
    if (pos > buf.len) {
        list.appendSlice("404.html") catch |err| {
            return err;
        };
        return list;
    }

    for (buf[pos..buf.len]) |elem| {
        if (elem == ' ') {
            break;
        } else {
            list.append(elem) catch |err| {
                return err;
            };
        }
        end += 1;
    }

    //default to index.html for the home page
    if (eql(u8, list.items, "")) {
        list.appendSlice("index.html") catch |err| {
            return err;
        };
    }

    // for now urls must be at least 3 characters long
    if (list.items.len < 3) {
        list.deinit();
        list = std.ArrayList(u8).init(allocator);

        std.debug.print("\n!! invalid filetype requested '{s}'\n", .{list.items});
        list.appendSlice("404.html") catch |err| {
            return err;
        };
    }

    //filter hidden files and directories
    var last: u8 = '/';
    for (list.items) |elem| {
        if (elem == '.' and last == '/') {
            list.deinit();
            list = std.ArrayList(u8).init(allocator);

            std.debug.print("\n!! invalid filetype requested '{s}'\n", .{list.items});
            list.appendSlice("404.html") catch |err| {
                return err;
            };

            std.debug.print("!! attempted to access hidden file or folder\n", .{});
            return list;
        }
        last = elem;
    }

    //make sure filetype is supported
    std.debug.print("file: {s}\n", .{list.items});
    var dotSpot: usize = list.items.len - 2;

    std.debug.print("\n", .{});
    var validFormat: bool = false;
    while (list.items[dotSpot + 1] != '.' and dotSpot > 0) {
        if (list.items[dotSpot] == '.') {
            validFormat = try toml.checkFormat(list.items[dotSpot + 1 .. list.items.len], allocator);
            break;
        }
        dotSpot -= 1;
        if (dotSpot == 0) {
            validFormat = try toml.checkFormat("/", allocator);
            break;
        }
    }
    if (validFormat == false) {
        list.deinit();
        list = std.ArrayList(u8).init(allocator);

        std.debug.print("\n!! invalid filetype requested '{s}'\n", .{list.items});
        list.appendSlice("404.html") catch |err| {
            return err;
        };
    }

    return list;
}
// make sure we are getting a valid status line
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

//read a file and return a buffer the same size as the file
pub fn read_file(name: anytype, allocator: Allocator) ![]u8 {
    var file = std.fs.cwd().openFile(name, .{ .mode = .read_only }) catch try std.fs.cwd().openFile("404.html", .{ .mode = .read_only });
    defer file.close();

    const file_size = try file.getEndPos();
    const b: []u8 = try allocator.alloc(u8, file_size);

    _ = try std.os.read(file.handle, b);

    return b;
}
