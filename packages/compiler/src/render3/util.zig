/// R3 Util — Shared utilities for render3 code generation
///
/// Port of: compiler/src/render3/render3/.ts (194 LoC)
const std = @import("std");

/// R3CompiledExpression — compiled template function expression.
pub const R3CompiledExpression = struct {
    name: []const u8,
    statements: []const u8,
    source: []const u8 = "",
};

/// R3Reference — a reference to an Angular symbol.
pub const R3Reference = struct {
    name: []const u8,
    module_name: []const u8 = "",
};

/// Generate a type string with parameters.
pub fn typeWithParameters(allocator: std.mem.Allocator, type_name: []const u8, param_count: u32) ![]const u8 {
    if (param_count == 0) return type_name;
    var buf = std.ArrayList(u8).init(allocator);
    try buf.appendSlice(type_name);
    try buf.append('<');
    for (0..param_count) |i| {
        if (i > 0) try buf.appendSlice(", ");
        try buf.appendSlice("P");
        const digit: u8 = @intCast(i);
        try buf.append('0' + digit);
    }
    try buf.append('>');
    return buf.toOwnedSlice();
}

/// Context name used in template functions.
pub const CONTEXT_NAME = "ctx";

/// Render flags name used in template functions.
pub const RENDER_FLAGS = "rf";

/// Allocate a temporary variable name.
pub fn temporaryAllocator() TemporaryAllocator {
    return .{};
}

pub const TemporaryAllocator = struct {
    counter: u32 = 0,

    pub fn next(self: *TemporaryAllocator) []const u8 {
        self.counter += 1;
        return switch (self.counter) {
            1 => "t",
            else => "t",
        };
    }
};
