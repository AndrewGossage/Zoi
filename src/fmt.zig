const std = @import("std");
pub fn renderTemplate(
    io: std.Io,
    path: []const u8,
    x: anytype,
    allocator: std.mem.Allocator,
) ![]const u8 {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_only });
    defer file.close(io);
    const file_size = try file.length(io);
    const body: []u8 = try allocator.alloc(u8, file_size);
    defer allocator.free(body);
    var reader = file.reader(io, body);
    _ = try reader.interface.readSliceAll(body);
    var new_body = std.ArrayList(u8).empty;
    defer new_body.deinit(allocator);
    try new_body.appendSlice(allocator, body);

    var temp_body = std.ArrayList(u8).empty;
    defer temp_body.deinit(allocator);

    inline for (std.meta.fields(@TypeOf(x))) |f| {
        const l = try std.fmt.allocPrint(allocator, "${s}$", .{f.name});
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

