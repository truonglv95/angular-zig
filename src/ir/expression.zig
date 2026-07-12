/// IR Expression — Intermediate representation expressions
///
/// These replace the Expression AST during compilation.
/// Simpler than AST — only the constructs that matter for code gen.
const std = @import("std");
const enums = @import("enums.zig");
pub const ExpressionKind = enums.ExpressionKind;
const source_span = @import("../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

// ─── Forward declaration ──────────────────────────────────────

pub const IrExpr = struct {
    kind: ExpressionKind,
    span: AbsoluteSourceSpan,
    data: ExprData,

    pub fn context(span: AbsoluteSourceSpan) IrExpr {
        return .{ .kind = .Context, .span = span, .data = .{ .Context = {} } };
    }

    pub fn readVariable(name: []const u8, xref: u32, span: AbsoluteSourceSpan) IrExpr {
        return .{ .kind = .ReadVariable, .span = span, .data = .{ .ReadVariable = .{ .name = name, .xref = xref } } };
    }

    pub fn empty(span: AbsoluteSourceSpan) IrExpr {
        return .{ .kind = .EmptyExpr, .span = span, .data = .{ .EmptyExpr = {} } };
    }

    pub fn constCollected(index: u32, span: AbsoluteSourceSpan) IrExpr {
        return .{ .kind = .ConstCollected, .span = span, .data = .{ .ConstCollected = index } };
    }

    pub fn binaryExpr(left: *IrExpr, op: u8, right: *IrExpr, span: AbsoluteSourceSpan) IrExpr {
        return .{ .kind = .BinaryExpr, .span = span, .data = .{ .BinaryExpr = .{ .left = left, .op = op, .right = right } } };
    }

    pub fn callExpr(receiver: *IrExpr, args: []const *IrExpr, span: AbsoluteSourceSpan) IrExpr {
        return .{ .kind = .CallExpr, .span = span, .data = .{ .CallExpr = .{ .receiver = receiver, .args = args } } };
    }

    pub fn literalExpr(value: []const u8, span: AbsoluteSourceSpan) IrExpr {
        return .{ .kind = .LiteralExpr, .span = span, .data = .{ .LiteralExpr = .{ .value = value } } };
    }

    pub fn readPropExpr(receiver: *IrExpr, name: []const u8, span: AbsoluteSourceSpan) IrExpr {
        return .{ .kind = .ReadPropExpr, .span = span, .data = .{ .ReadPropExpr = .{ .receiver = receiver, .name = name } } };
    }

    pub fn conditionalExpr(condition: *IrExpr, true_expr: *IrExpr, false_expr: *IrExpr, span: AbsoluteSourceSpan) IrExpr {
        return .{ .kind = .ConditionalExpr, .span = span, .data = .{ .ConditionalExpr = .{ .condition = condition, .true_expr = true_expr, .false_expr = false_expr } } };
    }

    pub fn notExpr(expression: *IrExpr, span: AbsoluteSourceSpan) IrExpr {
        return .{ .kind = .NotExpr, .span = span, .data = .{ .NotExpr = .{ .expression = expression } } };
    }
};

// ─── Expression Data (Tagged Union) ──────────────────────────

pub const ExprData = union(ExpressionKind) {
    /// Implicit context (the component instance)
    Context: void,

    /// Read a local variable by name and xref
    ReadVariable: struct {
        name: []const u8,
        xref: u32,
    },

    /// Navigate up N context levels
    NextContext: u32,

    /// Reference a template variable (#ref)
    Reference: struct {
        name: []const u8,
        xref: u32,
    },

    /// Pure function expression (extracted for optimization)
    PureFunctionExpr: struct {
        fn_ref: u32,
        params: []const *IrExpr,
        body: *IrExpr,
    },

    /// Pure function parameter reference
    PureFunctionParameterExpr: struct {
        index: u32,
    },

    /// Pipe binding (expr | pipeName:arg1:arg2)
    PipeBinding: struct {
        name: []const u8,
        args: []const *IrExpr,
        pure: bool,
    },

    /// Variadic pipe binding
    PipeBindingVariadic: struct {
        name: []const u8,
        args: []const *IrExpr,
    },

    /// Safe property read (already null-checked)
    SafePropertyRead: struct {
        receiver: *IrExpr,
        name: []const u8,
    },

    /// Safe keyed read (already null-checked)
    SafeKeyedRead: struct {
        receiver: *IrExpr,
        key: *IrExpr,
    },

    /// Empty expression (no-op)
    EmptyExpr: void,

    /// Conditional case value
    ConditionalCase: struct {
        condition: *IrExpr,
        value: *IrExpr,
    },

    /// Reference to constant pool index
    ConstCollected: u32,

    /// Two-way binding assignment
    TwoWayBindingSet: struct {
        lhs: *IrExpr,
        rhs: *IrExpr,
    },

    /// Arrow function (for event handlers)
    ArrowFunction: struct {
        param_names: []const []const u8,
        body: *IrExpr,
    },

    /// Slot literal
    SlotLiteralExpr: u32,

    /// Binary expression (a + b, a > b, etc.)
    BinaryExpr: struct {
        left: *IrExpr,
        op: u8,
        right: *IrExpr,
    },

    /// Function call (ctx.handleClick($event))
    CallExpr: struct {
        receiver: *IrExpr,
        args: []const *IrExpr,
    },

    /// Inline literal value without constant pool (e.g. "42", "'hello'", "true")
    LiteralExpr: struct {
        value: []const u8,
    },

    /// Property chain read (ctx.property)
    ReadPropExpr: struct {
        receiver: *IrExpr,
        name: []const u8,
    },

    /// Ternary conditional (a ? b : c)
    ConditionalExpr: struct {
        condition: *IrExpr,
        true_expr: *IrExpr,
        false_expr: *IrExpr,
    },

    /// Logical not (!expr)
    NotExpr: struct {
        expression: *IrExpr,
    },
};

// ─── Tests ────────────────────────────────────────────────────

test "IrExpr context" {
    const span = AbsoluteSourceSpan{ .start = 0, .end = 0 };
    const expr = IrExpr.context(span);
    try std.testing.expectEqual(ExpressionKind.Context, expr.kind);
}

test "IrExpr readVariable" {
    const span = AbsoluteSourceSpan{ .start = 0, .end = 10 };
    const expr = IrExpr.readVariable("items", 3, span);
    try std.testing.expectEqual(ExpressionKind.ReadVariable, expr.kind);
    try std.testing.expectEqualStrings("items", expr.data.ReadVariable.name);
    try std.testing.expectEqual(@as(u32, 3), expr.data.ReadVariable.xref);
}

test "IrExpr size" {
    comptime {}
}

test "IrExpr binaryExpr" {
    const span = AbsoluteSourceSpan{ .start = 0, .end = 5 };
    // We need heap-allocated IrExprs for the constructor args
    const allocator = std.testing.allocator;
    const left = try allocator.create(IrExpr);
    left.* = IrExpr.readVariable("a", 0, span);
    const right = try allocator.create(IrExpr);
    right.* = IrExpr.readVariable("b", 1, span);
    defer {
        allocator.destroy(left);
        allocator.destroy(right);
    }

    const expr = IrExpr.binaryExpr(left, 0, right, span);
    try std.testing.expectEqual(ExpressionKind.BinaryExpr, expr.kind);
    try std.testing.expectEqual(@as(u8, 0), expr.data.BinaryExpr.op);
}

test "IrExpr callExpr" {
    const span = AbsoluteSourceSpan{ .start = 0, .end = 10 };
    const allocator = std.testing.allocator;
    const recv = try allocator.create(IrExpr);
    recv.* = IrExpr.context(span);
    defer allocator.destroy(recv);

    const args = [_]*IrExpr{};
    const expr = IrExpr.callExpr(recv, &args, span);
    try std.testing.expectEqual(ExpressionKind.CallExpr, expr.kind);
}

test "IrExpr literalExpr" {
    const span = AbsoluteSourceSpan{ .start = 0, .end = 4 };
    const expr = IrExpr.literalExpr("42", span);
    try std.testing.expectEqual(ExpressionKind.LiteralExpr, expr.kind);
    try std.testing.expectEqualStrings("42", expr.data.LiteralExpr.value);
}

test "IrExpr readPropExpr" {
    const span = AbsoluteSourceSpan{ .start = 0, .end = 8 };
    const allocator = std.testing.allocator;
    const recv = try allocator.create(IrExpr);
    recv.* = IrExpr.context(span);
    defer allocator.destroy(recv);

    const expr = IrExpr.readPropExpr(recv, "name", span);
    try std.testing.expectEqual(ExpressionKind.ReadPropExpr, expr.kind);
    try std.testing.expectEqualStrings("name", expr.data.ReadPropExpr.name);
}

test "IrExpr conditionalExpr" {
    const span = AbsoluteSourceSpan{ .start = 0, .end = 10 };
    const allocator = std.testing.allocator;
    const cond = try allocator.create(IrExpr);
    cond.* = IrExpr.readVariable("flag", 0, span);
    const t = try allocator.create(IrExpr);
    t.* = IrExpr.literalExpr("'yes'", span);
    const f = try allocator.create(IrExpr);
    f.* = IrExpr.literalExpr("'no'", span);
    defer {
        allocator.destroy(cond);
        allocator.destroy(t);
        allocator.destroy(f);
    }

    const expr = IrExpr.conditionalExpr(cond, t, f, span);
    try std.testing.expectEqual(ExpressionKind.ConditionalExpr, expr.kind);
}

test "IrExpr notExpr" {
    const span = AbsoluteSourceSpan{ .start = 0, .end = 5 };
    const allocator = std.testing.allocator;
    const inner = try allocator.create(IrExpr);
    inner.* = IrExpr.readVariable("x", 0, span);
    defer allocator.destroy(inner);

    const expr = IrExpr.notExpr(inner, span);
    try std.testing.expectEqual(ExpressionKind.NotExpr, expr.kind);
}
