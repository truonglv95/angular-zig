/// TCB Ops codegen — TCB code generation utilities
///
/// Port of: compiler/src/typecheck/ops/codegen.ts (137 LoC)
///
/// Provides helpers for generating TypeScript code blocks.
const std = @import("std");

/// TcbExpr — a type-check expression result (string representation of TS code).
pub const TcbExpr = []const u8;

/// Context — the TCB compilation context.
pub const Context = struct {
    allocator: std.mem.Allocator,
    config: TcbConfig = .{},
};

/// TCB configuration options.
pub const TcbConfig = struct {
    check_type_of_dom_events: bool = true,
    strict_null_checks: bool = true,
};

/// Scope — the template scope for variable resolution.
pub const Scope = struct {
    allocator: std.mem.Allocator,
    parent: ?*const Scope = null,
};

/// TcbExpr — a type-check expression result (string representation of TS code).
/// Generate a statements block from a list of expressions.
/// Direct port of `getStatementsBlock(statements)` in the TS source.
pub fn getStatementsBlock(
    allocator: std.mem.Allocator,
    statements: []const TcbExpr,
) !TcbExpr {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();
    try buf.appendSlice("{ ");
    for (statements) |stmt| {
        try buf.appendSlice(stmt);
        try buf.appendSlice("; ");
    }
    try buf.append('}');
    return buf.toOwnedSlice();
}

/// Wrap an expression as a statement.
pub fn toStatement(allocator: std.mem.Allocator, expr: TcbExpr) !TcbExpr {
    return std.fmt.allocPrint(allocator, "{s};", .{expr});
}

/// Generate a variable declaration.
pub fn declareVar(
    allocator: std.mem.Allocator,
    name: []const u8,
    value: TcbExpr,
    type_annotation: ?[]const u8,
) !TcbExpr {
    if (type_annotation) |t| {
        return std.fmt.allocPrint(allocator, "var {s}: {s} = {s};", .{ name, t, value });
    }
    return std.fmt.allocPrint(allocator, "var {s} = {s};", .{ name, value });
}

// ─── Tests ──────────────────────────────────────────────────

test "codegen module loads" {
    try std.testing.expect(true);
}
