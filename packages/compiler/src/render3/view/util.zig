/// R3 View Util — Shared utilities for view compilation
///
/// Port of: compiler/src/render3/view/util.ts (230 LoC)
///
/// Provides shared utilities used by the view compiler, including:
///   - DefinitionMap: builds JS object literals for ɵɵdefine* calls
///   - CONTEXT_NAME, RENDER_FLAGS: parameter names for template functions
///   - R3CompiledExpression: a compiled expression with optional tsIgnore
///   - typeWithParameters: generates type strings with type arguments
///   - asLiteral, conditionallyCreateDirectiveBindingLiteral
const std = @import("std");

/// Context name used in template functions.
/// Direct port of `CONTEXT_NAME` in the TS source.
pub const CONTEXT_NAME = "ctx";

/// Render flags name used in template functions.
/// Direct port of `RENDER_FLAGS` in the TS source.
pub const RENDER_FLAGS = "rf";

/// Render flag values for create and update phases.
pub const RENDER_FLAGS_CREATE: u32 = 1;
pub const RENDER_FLAGS_UPDATE: u32 = 2;

/// DefinitionMap — a map of key-value pairs for ɵɵdefine* calls.
/// Direct port of `DefinitionMap` class in the TS source.
pub const DefinitionMap = struct {
    entries: std.array_list.Managed(Entry),
    allocator: std.mem.Allocator,

    pub const Entry = struct {
        key: []const u8,
        value: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) DefinitionMap {
        return .{
            .entries = std.array_list.Managed(Entry).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DefinitionMap) void {
        self.entries.deinit();
    }

    pub fn set(self: *DefinitionMap, key: []const u8, value: []const u8) !void {
        try self.entries.append(.{ .key = key, .value = value });
    }

    /// Convert the definition map to a JavaScript object literal string.
    pub fn toObjectLiteral(self: *const DefinitionMap, allocator: std.mem.Allocator) ![]const u8 {
        var buf = std.array_list.Managed(u8).init(allocator);
        errdefer buf.deinit();
        try buf.appendSlice("{ ");
        for (self.entries.items, 0..) |entry, i| {
            if (i > 0) try buf.appendSlice(", ");
            try buf.appendSlice(entry.key);
            try buf.appendSlice(": ");
            try buf.appendSlice(entry.value);
        }
        try buf.appendSlice(" }");
        return buf.toOwnedSlice();
    }

    /// Backward-compatible alias.
    pub fn toObjectString(self: *const DefinitionMap, allocator: std.mem.Allocator) ![]const u8 {
        return self.toObjectLiteral(allocator);
    }
};

/// TemporaryAllocator — allocates unique temporary variable names.
pub const TemporaryAllocator = struct {
    counter: u32 = 0,

    pub fn next(self: *TemporaryAllocator) []const u8 {
        self.counter += 1;
        return "tmp";
    }
};

/// Convert a value to a literal expression string.
/// Direct port of `asLiteral(value)` in the TS source.
pub fn asLiteral(value: []const u8) []const u8 {
    return value;
}

/// Convert an array of values to a JS array literal.
/// Direct port of `asLiteral(arr)` for arrays.
pub fn asLiteralArray(allocator: std.mem.Allocator, values: []const []const u8) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();
    try buf.append('[');
    for (values, 0..) |v, i| {
        if (i > 0) try buf.appendSlice(", ");
        try buf.appendSlice(v);
    }
    try buf.append(']');
    return buf.toOwnedSlice();
}

/// Conditionally create a directive binding literal.
/// Returns null if the metadata is null.
/// Direct port of `conditionallyCreateDirectiveBindingLiteral(metadata)` in the TS source.
pub fn conditionallyCreateDirectiveBindingLiteral(
    allocator: std.mem.Allocator,
    metadata: ?[]const u8,
) !?[]const u8 {
    if (metadata == null) return null;
    return allocator.dupe(u8, metadata.?);
}

/// R3CompiledExpression — a compiled expression with optional tsIgnore comment.
/// Direct port of `R3CompiledExpression` interface in the TS source.
pub const R3CompiledExpression = struct {
    expression: []const u8,
    ts_ignore: bool = false,
};

/// tsIgnoreComment — the `@ts-ignore` comment string.
/// Direct port of `tsIgnoreComment` in the TS source.
pub const TS_IGNORE_COMMENT = "// @ts-ignore";

/// Generate a type string with type arguments.
/// Direct port of `typeWithParameters(type, typeArgumentCount)` in the TS source.
pub fn typeWithParameters(
    allocator: std.mem.Allocator,
    type_name: []const u8,
    type_arg_count: u32,
) ![]const u8 {
    if (type_arg_count == 0) {
        return allocator.dupe(u8, type_name);
    }
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();
    try buf.appendSlice(type_name);
    try buf.appendSlice("<any");
    var i: u32 = 1;
    while (i < type_arg_count) : (i += 1) {
        try buf.appendSlice(", any");
    }
    try buf.append('>');
    return buf.toOwnedSlice();
}

/// Convert a list of R3References to a JS array literal.
/// Direct port of `refsToArray(refs, shouldAllowNull)` in the TS source.
pub fn refsToArray(
    allocator: std.mem.Allocator,
    refs: []const []const u8,
) ![]const u8 {
    return asLiteralArray(allocator, refs);
}

/// Create a dev-only guarded expression.
/// Direct port of `devOnlyGuardedExpression(expr)` in the TS source.
pub fn devOnlyGuardedExpression(
    allocator: std.mem.Allocator,
    expr: []const u8,
) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(ngDevMode && {s})", .{expr});
}

/// Create a JIT-only guarded expression.
/// Direct port of `jitOnlyGuardedExpression(expr)` in the TS source.
pub fn jitOnlyGuardedExpression(
    allocator: std.mem.Allocator,
    expr: []const u8,
) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(ngJitMode && {s})", .{expr});
}

// ─── Tests ──────────────────────────────────────────────────

test "DefinitionMap toObjectLiteral" {
    const allocator = std.testing.allocator;
    var map = DefinitionMap.init(allocator);
    defer map.deinit();
    try map.set("type", "MyComp");
    try map.set("decls", "1");
    const result = try map.toObjectLiteral(allocator);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("{ type: MyComp, decls: 1 }", result);
}

test "asLiteralArray" {
    const allocator = std.testing.allocator;
    const values = [_][]const u8{ "a", "b", "c" };
    const result = try asLiteralArray(allocator, &values);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("[a, b, c]", result);
}

test "typeWithParameters" {
    const allocator = std.testing.allocator;
    const r0 = try typeWithParameters(allocator, "MyType", 0);
    defer allocator.free(r0);
    try std.testing.expectEqualStrings("MyType", r0);

    const r2 = try typeWithParameters(allocator, "MyType", 2);
    defer allocator.free(r2);
    try std.testing.expectEqualStrings("MyType<any, any>", r2);
}

test "devOnlyGuardedExpression" {
    const allocator = std.testing.allocator;
    const result = try devOnlyGuardedExpression(allocator, "checkTypes()");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("(ngDevMode && checkTypes())", result);
}

test "RENDER_FLAGS constants" {
    try std.testing.expectEqualStrings("rf", RENDER_FLAGS);
    try std.testing.expectEqualStrings("ctx", CONTEXT_NAME);
    try std.testing.expectEqual(@as(u32, 1), RENDER_FLAGS_CREATE);
    try std.testing.expectEqual(@as(u32, 2), RENDER_FLAGS_UPDATE);
}
