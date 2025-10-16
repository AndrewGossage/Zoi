const std = @import("std");
pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    client: std.http.Client,
    persistent_headers: []const std.http.Header,

    pub fn init(allocator: std.mem.Allocator, persistent_headers: []const std.http.Header) HttpClient {
        return .{
            .allocator = allocator,
            .client = .{ .allocator = allocator },
            .persistent_headers = persistent_headers,
        };
    }

    pub fn deinit(self: *HttpClient) void {
        self.client.deinit();
    }

    pub fn get(
        self: *HttpClient,
        url: []const u8,
        additional_headers: ?[]const std.http.Header,
    ) ![]const u8 {
        var list = std.ArrayListUnmanaged(u8).empty;
        errdefer list.deinit(self.allocator);

        var writer = std.Io.Writer.Allocating.fromArrayList(self.allocator, &list);
        const w = &writer.writer;

        // Combine persistent headers with additional headers
        var all_headers = std.ArrayListUnmanaged(std.http.Header).empty;
        defer all_headers.deinit(self.allocator);

        try all_headers.appendSlice(self.allocator, self.persistent_headers);
        if (additional_headers) |extra| {
            try all_headers.appendSlice(self.allocator, extra);
        }

        const req = try self.client.fetch(.{
            .location = .{ .url = url },
            
            .method = .GET,
            .response_writer = w,
            .extra_headers = all_headers.items,
        });
        _ = req;

        try w.flush();
        return try writer.toOwnedSlice();
    }


};

