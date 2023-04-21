const std = @import("std");
const os = std.os;
const warn = std.debug.warn;

pub fn main() !void {
    var file = try std.os.open("/path/to/file.txt");
    defer file.close();

    const file_size = try file.getEndPos();
    // why cant I use?
    // var buffer: [file_size]u8 = undefined;
    // ie, I only want to create a buffer that is same size as
    // the file been read.
    _ = file_size;
    var buffer: [1024 * 4]u8 = undefined;
    const bytes_read = try file.read(buffer[0..buffer.len]);
    warn("{}", buffer[0..bytes_read]);
}
