const std = @import("std");

pub fn render(
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
    var new_body = std.ArrayList(u8).init(allocator);
    defer new_body.deinit();
    try new_body.appendSlice(body);

    var temp_body = std.ArrayList(u8).init(allocator);
    defer temp_body.deinit();

    inline for (std.meta.fields(@TypeOf(x))) |f| {
        const l = try std.fmt.allocPrint(allocator, "${s}$", .{f.name});
        defer allocator.free(l);

        var pieces = std.mem.tokenizeSequence(u8, new_body.items, l);
        while (pieces.peek() != null) {
            try temp_body.appendSlice(pieces.next().?);
            if (pieces.peek() != null) {
                try temp_body.appendSlice(@field(x, f.name));
            }
        }
        new_body.clearRetainingCapacity();
        try new_body.appendSlice(temp_body.items);
        temp_body.clearRetainingCapacity();
    }
    const out = try new_body.toOwnedSlice();
    return out;
}
