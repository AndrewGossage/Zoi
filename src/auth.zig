const std = @import("std");
const config = @import("config.zig");
const server = @import("server.zig");
const fmt = @import("fmt.zig");
const builtin = @import("builtin");
const crypto = std.crypto;


pub const AuthBody = struct {
    exp: u64,
    iat: u64,
    login: u64,
    user: []const u8,
    value: []const u8,
};


pub const execresult = struct {
    stdout: []const u8,
    stderr: []const u8,
};




const indexquery = struct {
    value: ?[]const u8,
};


pub fn decodeAuth(allocator: std.mem.Allocator, cookie: []const u8,  secret: []const u8) !AuthBody {
    
    // Split JWT into parts
    var parts = std.mem.splitScalar(u8, cookie, '.');
    const header_b64 = parts.next() orelse return error.InvalidJWT;
    const payload_b64 = parts.next() orelse return error.InvalidJWT;
    const signature_b64 = parts.next() orelse return error.InvalidJWT;
    
    // Verify signature
    const message = cookie[0..(header_b64.len + 1 + payload_b64.len)];
    
    const decoder = std.base64.url_safe_no_pad.Decoder;
    
    // Decode signature
    var sig_buf: [64]u8 = undefined;
    const sig_len = try decoder.calcSizeForSlice(signature_b64);
    try decoder.decode(sig_buf[0..sig_len], signature_b64);
    const sig_decoded = sig_buf[0..sig_len];
    
    // Calculate expected signature
    var expected_sig: [crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;
    crypto.auth.hmac.sha2.HmacSha256.create(&expected_sig, message, std.mem.span(secret));
    
    if (!std.mem.eql(u8, sig_decoded, &expected_sig)) {
        return error.InvalidSignature;
    }
    
    // Decode payload
    const decoded_size = try decoder.calcSizeForSlice(payload_b64);
    const decoded = try allocator.alloc(u8, decoded_size);
    defer allocator.free(decoded);
    
    try decoder.decode(decoded, payload_b64);
    server.debugPrint("debug: {s}\n", .{decoded});
    // Parse JSON
    const parsed = try std.json.parseFromSlice(AuthBody, allocator, decoded, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    
    return parsed.value;
}

