const std = @import("std");
const server = @import("server.zig");
const Allocator = std.mem.Allocator;
const tomlName = "zoi.toml";

const eql = std.mem.eql;
pub fn readToml(allocator: Allocator) ![]u8 {
    return try server.readFile(tomlName, allocator);
}
pub fn lastDigit(buf: anytype) usize {
    var end = buf.len - 1;
    while (isDigit(buf[end]) == false) end -= 1;
    return end;
}

pub fn getPort(allocator: Allocator) !u16 {
    const value = try readKeyValue("[server]", "port", allocator);
    defer allocator.free(value);
    const end = lastDigit(value);
    return std.fmt.parseInt(u16, value[0 .. end + 1], 0) catch |e| {
        return e;
    };
}

pub fn getWorkerCount(allocator: Allocator) !u16 {
    var value = try readKeyValue("[server]", "workers", allocator);
    defer allocator.free(value);
    const end = lastDigit(value);
    return std.fmt.parseInt(u16, value[0 .. end + 1], 0) catch |e| {
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
pub fn checkFormat(fileName: anytype, allocator: Allocator) !bool {
    var value = try readKeyValue("[server]", "fileTypes", allocator);
    defer _ = allocator.free(value);
    var pos: usize = 0;

    while (pos < value.len) {
        if (value[pos] == '"') {
            var end = pos + 1;
            while (value[end] != '"' and value[end] != '}') {
                end += 1;
            }
            if (value[end] == '}' or end > value.len) {
                return false;
            }
            if (eql(u8, fileName, value[pos + 1 .. end])) {
                return true;
            }
            pos = end;
        }
        pos += 1;
    }
    return false;
}

pub fn getHost(buf: []u8, allocator: Allocator) !void {
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

    const section_start = std.mem.indexOf(u8, t, section);
    if (section_start == null) {
        return "";
    }

    var pos: usize = section_start.? + section.len;

    const slice = t[pos..];
    const key_start = std.mem.indexOf(u8, slice, key);
    if (key_start == null) {
        return "";
    }

    pos = key_start.?;
    //make sure why found a key not a value
    while (slice[pos - 1] != '\n') {
        pos += 1;
        const key_inc = std.mem.indexOf(u8, slice[pos..], key);
        if (key_inc == null) {
            return "";
        }
        pos += key_inc.?;
    }

    while (slice[pos] != '=') pos += 1;
    while (slice[pos] == ' ' or slice[pos] == '=') pos += 1;
    var end: usize = pos;

    for (slice[pos..]) |elem| {
        if (elem == '#') {
            end -= 1;
            break;
        } else if (elem == '\n') {
            break;
        }
        end += 1;
    }

    const out: []u8 = try allocator.alloc(u8, t[pos..end].len + 1);
    var index: usize = 0;
    while (index < t[pos..end].len) : (index += 1) {
        out[index] = slice[pos..end][index];
    }
    return out;
}
