const std = @import("std");
const server = @import("server.zig");
const Allocator = std.mem.Allocator;
const tomlName = "zoi.toml";

const eql = std.mem.eql;
pub fn readToml(allocator: Allocator) ![]u8 {
    return try server.read_file(tomlName, allocator);
}

pub fn getPort() !u16 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var value = try readKeyValue("[server]", "port", allocator);
    defer allocator.free(value);
    return try std.fmt.parseInt(u16, value, 0);
}

pub fn getWorkerCount() !u16 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var value = try readKeyValue("[server]", "workers", allocator);
    defer allocator.free(value);

    return std.fmt.parseInt(u16, value, 0) catch |e| {
        std.debug.print("val: {any}", .{value});
        return e;
    };
}

pub fn isDigit(char: u8) bool {
    const digits = "1234567890";
    for (digits) |digit| {
        if (digit == char) return true;
    }
    return false;
}
pub fn getHost(buf: []u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var value = try readKeyValue("[server]", "host", allocator);
    defer allocator.free(value);

    var pos: usize = 0;
    for (0..4) |i| {
        while (!isDigit(value[pos])) {
            pos += 1;
        }
        var end = pos;
        while (isDigit(value[end])) {
            end += 1;
        }
        buf[i] = try std.fmt.parseInt(u8, value[pos..end], 0);
        pos = end;
    }
}

pub fn readKeyValue(section: anytype, key: anytype, allocator: Allocator) ![]u8 {
    const t = try readToml(allocator);
    defer allocator.free(t);

    var it = std.mem.window(u8, t, section.len, 1);
    var pos: usize = 0;
    while (it.next()) |slice| {
        if (eql(u8, slice, section)) {
            pos = it.index.?;
            break;
        }
        pos += 1;
    }
    it = std.mem.window(u8, t[pos..], key.len, 1);
    var found: bool = false;
    while (it.next()) |slice| {
        // check if we found the key + the proper spaceing and
        // equal sign
        if (eql(u8, slice, key) and eql(u8, " = ", t[(it.index.? + key.len) .. it.index.? + 3 + key.len])) {
            pos = it.index.? + 3 + key.len;
            found = true;
        } else if (slice[0] == '[') {
            return "";
        }
    }
    if (!found) return "";
    var end: usize = pos;

    for (t[pos..]) |elem| {
        if (elem == '#') {
            end -= 1;
            break;
        } else if (elem == '\n') {
            break;
        } else if (elem == '[') {
            return "";
        }
        end += 1;
    }

    if (end > t.len) return "";
    const out: []u8 = try allocator.alloc(u8, t[pos..end].len);
    var index: usize = 0;
    while (index < t[pos..end].len) : (index += 1) {
        out[index] = t[pos..end][index];
    }
    return out;
}
