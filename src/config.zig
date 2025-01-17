const std = @import("std");

pub const Config = @This();

address: []const u8,
port: u16,
workers: usize = 1,
hideDotFiles: bool = true,
useArena: bool = true,

/// Initialize the `Config` from a JSON file.
pub fn init(filename: []const u8, allocator: std.mem.Allocator) !Config {
    const file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
    defer file.close();

    const file_size = try file.getEndPos();
    const b: []u8 = try allocator.alloc(u8, file_size);
    defer allocator.free(b);

    _ = try file.readAll(b);

    var settings = try std.json.parseFromSlice(Config, allocator, b, .{
        .ignore_unknown_fields = true,
    });
    defer settings.deinit(); // Free allocated JSON memory

    // Duplicate the address string so it remains valid
    const address_copy = try allocator.dupe(u8, settings.value.address);

    return Config{
        .address = address_copy,
        .port = settings.value.port,
        .workers = settings.value.workers,
    };
}

/// Deallocate dynamically allocated memory in `Config`.
pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
    allocator.free(self.address);
    self.* = undefined; // Prevent accidental use-after-free
}
