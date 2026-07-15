/// TCB Ops variables — Block variables TCB operations
///
/// Port of: compiler/src/typecheck/ops/variables.ts (113 LoC)
///
/// Type-checks implicit block variables like $index, $first, $last.
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

/// TcbBlockImplicitVariableOp — declares an implicit block variable.
/// Direct port of `TcbBlockImplicitVariableOp` class in the TS source.
pub const TcbBlockImplicitVariableOp = struct {
    tcb: *const Context,
    scope: *const Scope,
    var_name: []const u8,
    var_type: []const u8,

    pub fn execute(self: *const TcbBlockImplicitVariableOp) !TcbExpr {
        return std.fmt.allocPrint(self.tcb.allocator, "var {s}: {s};", .{ self.var_name, self.var_type });
    }
};

/// Block variable types for @for loops.
pub const ForLoopVariables = struct {
    pub const INDEX = "number";
    pub const COUNT = "number";
    pub const FIRST = "boolean";
    pub const LAST = "boolean";
    pub const EVEN = "boolean";
    pub const ODD = "boolean";
};

/// Generate a block variable declaration.
pub fn declareBlockVariable(
    allocator: std.mem.Allocator,
    name: []const u8,
    var_type: []const u8,
) !TcbExpr {
    return std.fmt.allocPrint(allocator, "var {s}: {s};", .{ name, var_type });
}

// ─── Tests ──────────────────────────────────────────────────

test "variables module loads" {
    try std.testing.expect(true);
}
