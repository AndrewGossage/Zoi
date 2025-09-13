const std = @import("std");
const writer = std.io.getStdOut().writer();
//pub var verbose: bool = false;

pub fn request(
    method: anytype,
    url: anytype,
    headers: anytype,
    allocator: std.mem.Allocator,
    payload: anytype,
    status: ?std.http.Status,
) !std.ArrayList(u8) {
    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();
    _ = status;

    std.debug.print("\nURL: {s} {s}\n", .{ url, @tagName(method) });

    // Updated for Zig 0.15: Use the new HTTP client API
    const uri = try std.Uri.parse(url);
    var response_body = std.ArrayList(u8){};

    var req = try client.request(method, uri, .{ .extra_headers = headers });
    defer req.deinit();

    const start = std.time.milliTimestamp();

    // Send the request
    if (payload) |p| {
        try req.send(p);
    } else {
        try req.sendBodiless();
    }

    // Receive the response head
    var transfer_buffer: [4096]u8 = undefined;
    var reader_buffer: [4096]u8 = undefined;

    const head = try req.reader.receiveHead();

    // Parse content length (simple implementation)
    const content_len = parseContentLength(head) catch 1024 * 1024; // Default to 1MB if can't parse

    // Read the response body
    const reader = req.reader.bodyReader(&transfer_buffer, .none, content_len);
    var bytes_read: usize = 0;

    while (bytes_read < content_len) {
        const size = try reader.readSliceShort(&reader_buffer);
        if (size == 0) break;

        bytes_read += size;
        try response_body.appendSlice(allocator, reader_buffer[0..size]);
    }

    const stop = std.time.milliTimestamp();
    // Get status from the reader after receiveHead() has been called
    std.debug.print("Response Status: {d} {s}\n", .{ req.reader.status, response_body.items });
    std.debug.print("Response time: {d}ms\n\n", .{stop - start});

    return response_body;
}

fn parseContentLength(buf: []const u8) !usize {
    const prefix = "Content-Length:";
    var it = std.mem.tokenizeAny(u8, buf, "\r\n");
    while (it.next()) |line| {
        if (std.ascii.startsWithIgnoreCase(line, prefix)) {
            // Skip the header name
            const value = std.mem.trim(u8, line[prefix.len..], " \t");
            return try std.fmt.parseInt(usize, value, 10);
        }
    }
    return error.NoContentLen; // Not found
}

fn parseAndPrintJson(input: []const u8) !void {
    const allocator = std.heap.page_allocator;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, input, .{});
    const keys = parsed.value.object.keys();
    for (0..keys.len) |i| {
        std.debug.print("    {d}: {s}\n", .{ i, keys[i] });
    }
}

pub fn request_j(T: type, method: anytype, url: anytype, headers: anytype, allocator: std.mem.Allocator, payload: anytype, status: ?std.http.Status) !T {
    const report_array = try request(method, url, headers, allocator, payload, status);
    defer report_array.deinit(allocator);

    const report = std.json.parseFromSlice(T, allocator, report_array.items, .{
        .ignore_unknown_fields = true,
    }) catch |err| {
        try writer.print("could not parse report\n++++++++\n{s}\n+++++++\n\nfields:\n", .{report_array.items});
        parseAndPrintJson(report_array.items) catch {};
        return err;
    };
    return report.value;
}

pub fn get_json(T: type, url: anytype, headers: anytype, allocator: std.mem.Allocator) !T {
    return request_j(T, .GET, url, headers, allocator, null, .ok);
}

pub fn put_json(T: type, url: anytype, headers: anytype, allocator: std.mem.Allocator, payload: anytype) !T {
    // Updated for Zig 0.15: ArrayList is now unmanaged by default
    var json_string = std.ArrayList(u8){};
    defer json_string.deinit(allocator);

    try std.json.stringify(payload, .{}, json_string.writer(allocator));
    return request_j(T, .PUT, url, headers, allocator, json_string.items, .ok);
}

pub fn post_json(T: type, url: anytype, headers: anytype, allocator: std.mem.Allocator, payload: anytype) !T {
    // Updated for Zig 0.15: ArrayList is now unmanaged by default
    var json_string = std.ArrayList(u8){};
    defer json_string.deinit(allocator);

    try std.json.stringify(payload, .{}, json_string.writer(allocator));
    return request_j(T, .POST, url, headers, allocator, json_string.items, .ok);
}

pub fn delete_json(T: type, url: anytype, headers: anytype, allocator: std.mem.Allocator) !T {
    return request_j(T, .DELETE, url, headers, allocator, null, .ok);
}

pub fn get(url: anytype, headers: anytype, allocator: std.mem.Allocator, status: ?std.http.Status) !std.ArrayList(u8) {
    return request(.GET, url, headers, allocator, null, status);
}

pub fn post(url: anytype, headers: anytype, allocator: std.mem.Allocator, payload: anytype, status: ?std.http.Status) !std.ArrayList(u8) {
    return request(.POST, url, headers, allocator, payload, status);
}

pub fn put(url: anytype, headers: anytype, allocator: std.mem.Allocator, payload: anytype, status: ?std.http.Status) !std.ArrayList(u8) {
    return request(.PUT, url, headers, allocator, payload, status);
}

pub fn delete(url: anytype, headers: anytype, allocator: std.mem.Allocator, status: ?std.http.Status) !std.ArrayList(u8) {
    return request(.DELETE, url, headers, allocator, null, status);
}

// the following code is taken from an MIT liscensed repo owned by me -Andrew
const code_values_full = [_]struct { []const u8, []const u8 }{
    .{ "%20", " " },
    .{ "%21", "!" },
    .{ "%22", "\"" },
    .{ "%23", "#" },
    .{ "%24", "$" },
    .{ "%25", "%" },
    .{ "%26", "&" },
    .{ "%27", "'" },
    .{ "%28", "(" },
    .{ "%29", ")" },
    .{ "%2A", "*" },
    .{ "%2B", "+" },
    .{ "%2C", "," },
    .{ "%2D", "-" },
    .{ "%2E", "." },
    .{ "%3A", ":" },
    .{ "%3B", ";" },
    .{ "%3C", "<" },
    .{ "%3D", "=" },
    .{ "%3E", ">" },
    .{ "%3F", "?" },
    .{ "%40", "@" },
    .{ "%5B", "[" },
    .{ "%5C", "\\" },
    .{ "%5D", "]" },
    .{ "%5E", "^" },
    .{ "%5F", "_" },
    .{ "%60", "`" },
    .{ "%7B", "{" },
    .{ "%7C", "|" },
    .{ "%7D", "}" },
    .{ "%7E", "~" },
};

const code_values = [_]struct { []const u8, []const u8 }{
    .{ "%20", " " },
};

pub fn urlEncode(
    body: []const u8,
    allocator: std.mem.Allocator,
) ![]const u8 {
    // Updated for Zig 0.15: ArrayList is now unmanaged by default
    var temp_body = std.ArrayList(u8){};
    defer temp_body.deinit(allocator);

    var new_body = std.ArrayList(u8){};
    defer new_body.deinit(allocator);
    try new_body.appendSlice(allocator, body);

    inline for (0..code_values.len) |i| {
        const l = code_values[i][1];
        var pieces = std.mem.tokenizeSequence(u8, new_body.items, l);
        while (pieces.peek() != null) {
            try temp_body.appendSlice(allocator, pieces.next().?);
            if (pieces.peek() != null) {
                try temp_body.appendSlice(allocator, code_values[i][0]);
            }
        }
        new_body.clearRetainingCapacity();
        try new_body.appendSlice(allocator, temp_body.items);
        temp_body.clearRetainingCapacity();
    }
    const out = try new_body.toOwnedSlice(allocator);
    return out;
}

