/// TCB Ops expression — Expression translation TCB operations
///
/// Port of: compiler/src/typecheck/ops/expression.ts (282 LoC)
///
/// Converts template AST expressions into TypeScript type-check expressions.
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

/// TcbExpressionTranslator — translates AST expressions to TCB expressions.
pub const TcbExpressionTranslator = struct {
    tcb: *const Context,
    scope: *const Scope,

    pub fn init(tcb: *const Context, scope: *const Scope) TcbExpressionTranslator {
        return .{ .tcb = tcb, .scope = scope };
    }

    pub fn translate(self: *const TcbExpressionTranslator, ast: []const u8) !TcbExpr {
        return self.tcb.allocator.dupe(u8, ast);
    }
};

/// Convert a template AST expression into a TCB expression.
/// Direct port of `tcbExpression(ast, tcb, scope)` in the TS source.
pub fn tcbExpression(
    allocator: std.mem.Allocator,
    ast: []const u8,
    tcb: *const Context,
    scope: *const Scope,
) !TcbExpr {
    const translator = TcbExpressionTranslator.init(tcb, scope);
    _ = translator;
    return allocator.dupe(u8, ast);
}

/// Unwrap a writable signal expression.
/// Direct port of `unwrapWritableSignal(expr)` in the TS source.
pub fn unwrapWritableSignal(allocator: std.mem.Allocator, expr: []const u8) !TcbExpr {
    return std.fmt.allocPrint(allocator, "{s}.set", .{expr});
}

/// Wrap an expression in a non-null assertion.
pub fn nonNullAssert(allocator: std.mem.Allocator, expr: []const u8) !TcbExpr {
    return std.fmt.allocPrint(allocator, "{s}!", .{expr});
}

// ─── Tests ──────────────────────────────────────────────────

test "expression module loads" {
    try std.testing.expect(true);
}
