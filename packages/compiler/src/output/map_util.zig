/// Map Util — mapLiteral and mapEntry helpers
///
/// Port of: compiler/src/output/map_util.ts (34 LoC)
const std = @import("std");

/// Create a literal map expression string from key-value pairs.
pub fn mapLiteral(allocator: std.mem.Allocator, entries: []const MapEntry) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.append('{');
    for (entries, 0..) |entry, i| {
        if (i > 0) try buf.appendSlice(", ");
        try buf.appendSlice(entry.key);
        try buf.appendSlice(": ");
        try buf.appendSlice(entry.value);
    }
    try buf.append('}');
    return buf.toOwnedSlice();
}

pub const MapEntry = struct {
    key: []const u8,
    value: []const u8,
};
