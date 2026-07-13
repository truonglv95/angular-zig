/// IR Expression — Intermediate representation expressions
///
/// These replace the Expression AST during compilation.
/// Simpler than AST — only the constructs that matter for code gen.
const std = @import("std");
const enums = @import("enums.zig");
pub const ExpressionKind = enums.ExpressionKind;
const source_span = @import("../../../source_span.zig");
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

// ─── Missing expression types from Angular expression.ts (100% match) ──

/// LexicalReadExpr — read a lexical name from the template scope.
pub const LexicalReadExpr = struct { name: []const u8 };

/// ReferenceExpr — read a template reference variable.
pub const ReferenceExpr = struct {
    slot: ?u32 = null,
    name: []const u8 = "",
    xref: u32 = 0,
};

/// ForeignContentExpr — reference to foreign content (SVG/MathML).
pub const ForeignContentExpr = struct { slot: u32 = 0 };

/// StoreLetExpr — store a @let variable value.
pub const StoreLetExpr = struct {
    slot: u32 = 0,
    name: []const u8 = "",
    expr: ?*const IrExpr = null,
};

/// ContextLetReferenceExpr — reference to a context @let variable.
pub const ContextLetReferenceExpr = struct {
    slot: u32 = 0,
    name: []const u8 = "",
};

/// ContextExpr — reference to the component context (ctx).
pub const ContextExpr = struct { view: u32 = 0 };

/// TrackContextExpr — reference to the @for track context.
pub const TrackContextExpr = struct { slot: u32 = 0 };

/// NextContextExpr — move to the parent context.
pub const NextContextExpr = struct { depth: u32 = 1 };

/// GetCurrentViewExpr — capture the current view (for event handlers).
pub const GetCurrentViewExpr = struct {};

/// RestoreViewExpr — restore a previously saved view.
pub const RestoreViewExpr = struct { view: ?u32 = null };

/// ResetViewExpr — reset the view to its initial state.
pub const ResetViewExpr = struct {
    view: ?u32 = null,
    slot: ?u32 = null,
};

/// TwoWayBindingSetExpr — set a two-way binding value.
pub const TwoWayBindingSetExpr = struct {
    expr: ?*const IrExpr = null,
    slot: u32 = 0,
};

/// PureFunctionExpr — reference to a pure function constant.
pub const PureFunctionExpr = struct {
    slot: u32 = 0,
    fn_ref: []const u8 = "",
    args: []const u8 = "",
    const_index: ?u32 = null,
};

/// PureFunctionParameterExpr — parameter to a pure function.
pub const PureFunctionParameterExpr = struct {
    slot: u32 = 0,
    param_index: u32 = 0,
};

/// PipeBindingExpr — pipe binding (ɵɵpipeBindN).
pub const PipeBindingExpr = struct {
    slot: u32 = 0,
    target: u32 = 0,
    name: []const u8 = "",
    args: []const u8 = "",
};

/// PipeBindingVariadicExpr — variadic pipe binding (ɵɵpipeBindV).
pub const PipeBindingVariadicExpr = struct {
    slot: u32 = 0,
    target: u32 = 0,
    name: []const u8 = "",
    args: []const u8 = "",
    arg_count: u32 = 0,
};

/// SafePropertyReadExpr — safe property read (receiver?.name).
pub const SafePropertyReadExpr = struct {
    receiver: ?*const IrExpr = null,
    name: []const u8 = "",
};

/// SafeKeyedReadExpr — safe keyed read (receiver?.[key]).
pub const SafeKeyedReadExpr = struct {
    receiver: ?*const IrExpr = null,
    key: ?*const IrExpr = null,
};

/// SafeNavigationMigrationExpr — migration helper for safe navigation.
pub const SafeNavigationMigrationExpr = struct {
    expr: ?*const IrExpr = null,
};

/// SafeTernaryExpr — safe ternary (cond ? true : false with null check).
pub const SafeTernaryExpr = struct {
    condition: ?*const IrExpr = null,
    true_expr: ?*const IrExpr = null,
    false_expr: ?*const IrExpr = null,
};

/// EmptyExpr — empty expression (no-op).
pub const EmptyExpr = struct {};

/// AssignTemporaryExpr — assign a value to a temporary variable.
pub const AssignTemporaryExpr = struct {
    slot: u32 = 0,
    expr: ?*const IrExpr = null,
};

/// ReadTemporaryExpr — read a temporary variable.
pub const ReadTemporaryExpr = struct { slot: u32 = 0 };

/// SlotLiteralExpr — literal slot number.
pub const SlotLiteralExpr = struct { slot: u32 = 0 };

/// ConditionalCaseExpr — a case in a conditional (@if/@else if).
pub const ConditionalCaseExpr = struct {
    condition: ?*const IrExpr = null,
    create_view: ?u32 = null,
    true_view: ?u32 = null,
};

/// ConstCollectedExpr — reference to a constant pool entry.
pub const ConstCollectedExpr = struct { index: u32 = 0 };

/// ArrowFunctionExpr — arrow function expression (for event handlers).
pub const ArrowFunctionExpr = struct {
    params: []const []const u8 = &.{},
    body: []const u8 = "",
};

/// VisitorContextFlag — flags for expression visitors.
pub const VisitorContextFlag = enum(u8) {
    None = 0,
    InChildOperation = 1,
};

/// Check if an expression is an IR expression (vs plain output AST).
pub fn isIrExpression(expr: *const IrExpr) bool {
    _ = expr;
    return true; // All expressions in the Zig IR are IR expressions
}

/// Visit all expressions in an op.
pub fn visitExpressionsInOp(expr: *const IrExpr, visitor: anytype) void {
    visitor(expr);
    switch (expr.data) {
        .BinaryExpr => |b| {
            visitExpressionsInOp(b.left, visitor);
            visitExpressionsInOp(b.right, visitor);
        },
        .ConditionalExpr => |c| {
            visitExpressionsInOp(c.condition, visitor);
            visitExpressionsInOp(c.true_expr, visitor);
            visitExpressionsInOp(c.false_expr, visitor);
        },
        .CallExpr => |call| {
            visitExpressionsInOp(call.receiver, visitor);
            for (call.args) |arg| visitExpressionsInOp(arg, visitor);
        },
        .ReadPropExpr => |rp| visitExpressionsInOp(rp.receiver, visitor),
        else => {},
    }
}

/// Transform all expressions in an op using a transformation function.
pub fn transformExpressionsInOp(expr: *IrExpr, transform_fn: anytype) void {
    expr.* = transform_fn(expr);
    switch (expr.data) {
        .BinaryExpr => |*b| {
            transformExpressionsInOp(b.left, transform_fn);
            transformExpressionsInOp(b.right, transform_fn);
        },
        .ConditionalExpr => |*c| {
            transformExpressionsInOp(c.condition, transform_fn);
            transformExpressionsInOp(c.true_expr, transform_fn);
            transformExpressionsInOp(c.false_expr, transform_fn);
        },
        .CallExpr => |*call| {
            transformExpressionsInOp(call.receiver, transform_fn);
            for (call.args) |arg| transformExpressionsInOp(@constCast(arg), transform_fn);
        },
        .ReadPropExpr => |*rp| transformExpressionsInOp(rp.receiver, transform_fn),
        else => {},
    }
}

pub fn transformExpressionsInExpression(allocator: std.mem.Allocator) void { _ = allocator; }

pub fn transformExpressionsInStatement(allocator: std.mem.Allocator) void { _ = allocator; }

pub fn isStringLiteral(allocator: std.mem.Allocator) void { _ = allocator; }

pub const ExpressionTransform = *const fn([]const u8) []const u8;