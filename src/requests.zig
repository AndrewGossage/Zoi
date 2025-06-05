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
    var client = std.http.Client{
        .allocator = allocator,
    };
    _ = status;

    std.debug.print("\nURL: {s} {s}\n", .{ url, @tagName(method) });

    var response_body = std.ArrayList(u8).init(allocator);
    const start = std.time.milliTimestamp();

    const response = try client.fetch(.{
        .method = method,
        .location = .{ .url = url },
        .extra_headers = headers,
        .payload = payload,
        .response_storage = .{ .dynamic = &response_body },
    });

    const stop = std.time.milliTimestamp();
    std.debug.print("Response Status: {d} {s}\n", .{ response.status, response_body.items });
    std.debug.print("Response time: {d}ms\n\n", .{stop - start});

    return response_body;
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
    var json_string = std.ArrayList(u8).init(allocator);
    try std.json.stringify(payload, .{}, json_string.writer());
    defer json_string.deinit();
    return request_j(T, .PUT, url, headers, allocator, json_string.items, .ok);
}

pub fn post_json(T: type, url: anytype, headers: anytype, allocator: std.mem.Allocator, payload: anytype) !T {
    var json_string = std.ArrayList(u8).init(allocator);
    try std.json.stringify(payload, .{}, json_string.writer());
    defer json_string.deinit();

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
    var temp_body = std.ArrayList(u8).init(allocator);
    defer temp_body.deinit();

    var new_body = std.ArrayList(u8).init(allocator);
    defer new_body.deinit();
    try new_body.appendSlice(body);

    inline for (0..code_values.len) |i| {
        const l = code_values[i][1];
        var pieces = std.mem.tokenizeSequence(u8, new_body.items, l);
        while (pieces.peek() != null) {
            try temp_body.appendSlice(pieces.next().?);
            if (pieces.peek() != null) {
                try temp_body.appendSlice(code_values[i][0]);
            }
        }
        new_body.clearRetainingCapacity();
        try new_body.appendSlice(temp_body.items);
        temp_body.clearRetainingCapacity();
    }

    const out = try new_body.toOwnedSlice();

    return out;
}
