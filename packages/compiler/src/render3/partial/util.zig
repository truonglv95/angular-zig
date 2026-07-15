/// R3 Partial Util — Shared helpers for partial declarations
///
/// Port of: compiler/src/render3/render3/partial/.ts (91 LoC)
const std = @import("std");

/// Utilities for partial declaration compilation.
pub fn generateFactory(allocator: std.mem.Allocator, type_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "() => new {s}()", .{type_name});
}

pub fn generateDependencyArray(allocator: std.mem.Allocator, deps: []const []const u8) ![]const u8 {
    if (deps.len == 0) return allocator.dupe(u8, "[]");
    var buf = std.ArrayList(u8).init(allocator);
    try buf.append('[');
    for (deps, 0..) |dep, i| {
        if (i > 0) try buf.appendSlice(", ");
        try buf.appendSlice(dep);
    }
    try buf.append(']');
    return buf.toOwnedSlice();
}
