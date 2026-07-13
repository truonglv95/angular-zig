/// R3 View Util — Shared utilities for view compilation
///
/// Port of: compiler/src/render3/render3/view/.ts (230 LoC)
const std = @import("std");

/// DefinitionMap — a map of key-value pairs for ɵɵdefine* calls.
pub const DefinitionMap = struct {
    entries: std.ArrayList(Entry),
    allocator: std.mem.Allocator,

    pub const Entry = struct { key: []const u8, value: []const u8 };

    pub fn init(allocator: std.mem.Allocator) DefinitionMap {
        return .{ .entries = std.ArrayList(Entry).init(allocator), .allocator = allocator };
    }

    pub fn deinit(self: *DefinitionMap) void {
        self.entries.deinit();
    }

    pub fn set(self: *DefinitionMap, key: []const u8, value: []const u8) !void {
        try self.entries.append(.{ .key = key, .value = value });
    }

    pub fn toObjectString(self: *const DefinitionMap, allocator: std.mem.Allocator) ![]const u8 {
        var buf = std.ArrayList(u8).init(allocator);
        try buf.append('{');
        for (self.entries.items, 0..) |entry, i| {
            if (i > 0) try buf.appendSlice(", ");
            try buf.appendSlice(entry.key);
            try buf.appendSlice(": ");
            try buf.appendSlice(entry.value);
        }
        try buf.append('}');
        return buf.toOwnedSlice();
    }
};

/// Context name used in template functions.
pub const CONTEXT_NAME = "ctx";

/// Render flags name used in template functions.
pub const RENDER_FLAGS = "rf";

/// Temporary name allocator.
pub const TemporaryAllocator = struct {
    counter: u32 = 0,

    pub fn next(self: *TemporaryAllocator) []const u8 {
        self.counter += 1;
        return "tmp";
    }
};

/// Convert a value to a literal expression string.
pub fn asLiteral(value: []const u8) []const u8 {
    return value;
}
