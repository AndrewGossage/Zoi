const std = @import("std");

pub fn renderTemplate(
    path: []const u8,
    x: anytype,
    allocator: std.mem.Allocator,
) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();
    const file_size = try file.getEndPos();
    const body: []u8 = try allocator.alloc(u8, file_size);
    _ = try file.readAll(body);
    defer allocator.free(body);

    // Updated for Zig 0.15: ArrayList is now unmanaged by default
    var new_body = std.ArrayList(u8){};
    defer new_body.deinit(allocator);
    try new_body.appendSlice(allocator, body);

    var temp_body = std.ArrayList(u8){};
    defer temp_body.deinit(allocator);

    inline for (std.meta.fields(@TypeOf(x))) |f| {
        const l = try std.fmt.allocPrint(allocator, "${s}$", .{f.name});
        std.debug.print("\n\n{s}\n\n", .{l});
        defer allocator.free(l);
        var pieces = std.mem.tokenizeSequence(u8, new_body.items, l);
        while (pieces.peek() != null) {
            try temp_body.appendSlice(allocator, pieces.next().?);
            if (pieces.peek() != null) {
                try temp_body.appendSlice(allocator, @field(x, f.name));
            }
        }
        new_body.clearRetainingCapacity();
        try new_body.appendSlice(allocator, temp_body.items);
        temp_body.clearRetainingCapacity();
    }
    const out = try new_body.toOwnedSlice(allocator);
    return out;
}

const encoded_values = [_][]const u8{
    "%20",
    "%21",
    "%22",
    "%23",
    "%24",
    "%25",
    "%26",
    "%27",
    "%28",
    "%29",
    "%2A",
    "%2B",
    "%2C",
    "%2D",
    "%2E",
    "%2F",
    "%3A",
    "%3B",
    "%3C",
    "%3D",
    "%3E",
    "%3F",
    "%40",
    "%5B",
    "%5C",
    "%5D",
    "%5E",
    "%5F",
    "%60",
    "%7B",
    "%7C",
    "%7D",
    "%7E",
};

const decoded_values = [_][]const u8{
    " ",
    "!",
    "\"",
    "#",
    "$",
    "%",
    "&",
    "'",
    "(",
    ")",
    "*",
    "+",
    ",",
    "-",
    ".",
    "/",
    ":",
    ";",
    "<",
    "=",
    ">",
    "?",
    "@",
    "[",
    "\\",
    "]",
    "^",
    "_",
    "`",
    "{",
    "|",
    "}",
    "~",
};

pub fn urlDecode(
    body: []const u8,
    allocator: std.mem.Allocator,
) ![]const u8 {
    // Updated for Zig 0.15: ArrayList is now unmanaged by default
    var temp_body = std.ArrayList(u8){};
    defer temp_body.deinit(allocator);

    var new_body = std.ArrayList(u8){};
    defer new_body.deinit(allocator);
    try new_body.appendSlice(allocator, body);

    inline for (0..encoded_values.len) |i| {
        const l = encoded_values[i];
        var pieces = std.mem.tokenizeSequence(u8, new_body.items, l);
        while (pieces.peek() != null) {
            try temp_body.appendSlice(allocator, pieces.next().?);
            if (pieces.peek() != null) {
                try temp_body.appendSlice(allocator, decoded_values[i]);
            }
        }
        new_body.clearRetainingCapacity();
        try new_body.appendSlice(allocator, temp_body.items);
        temp_body.clearRetainingCapacity();
    }
    const out = try new_body.toOwnedSlice(allocator);
    return out;
}

