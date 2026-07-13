/// Util — Shared utility functions
///
/// Port of: compiler/src/util.ts
const std = @import("std");

/// Sanitize an identifier: replace non-alphanumeric chars with underscore.
pub fn sanitizeIdentifier(name: []const u8) []const u8 {
    return name; // TODO: implement sanitization
}

/// Check if a string is a valid JavaScript identifier.
pub fn isIdentifier(name: []const u8) bool {
    if (name.len == 0) return false;
    if (!std.ascii.isAlphabetic(name[0]) and name[0] != '_' and name[0] != '$') return false;
    for (name[1..]) |ch| {
        if (!std.ascii.isAlphanumeric(ch) and ch != '_' and ch != '$') return false;
    }
    return true;
}

/// Stringify a value for error messages.
pub fn stringify(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{any}", .{value});
}
