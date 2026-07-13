/// Shared helpers for IR phase implementations.
///
/// These helpers are used by multiple per-phase files. They live here
/// to avoid duplication and keep the per-phase files focused on their
/// specific transformation logic.
const std = @import("std");

const ir_ops = @import("../ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;
const OpData = ir_ops.OpData;

const ir_expr = @import("../expression.zig");
const IrExpr = ir_expr.IrExpr;

/// Max nesting depth for stack-allocated tracking arrays.
pub const MAX_DEPTH: usize = 128;

/// Whether a property name is security-sensitive (needs security_context).
pub fn isDangerousProperty(name: []const u8) bool {
    const dangerous = [_][]const u8{
        "innerHTML",
        "outerHTML",
        "formaction",
        "action",
        "data",
        "srcdoc",
    };
    for (dangerous) |d| {
        if (std.mem.eql(u8, name, d)) return true;
    }
    // href/src with javascript: prefix is checked separately
    return false;
}

/// Whether a URL-like property value starts with "javascript:".
pub fn isJavascriptUrl(value: []const u8) bool {
    return value.len >= 11 and std.mem.eql(u8, value[0..11], "javascript:");
}

/// Get the mutable expression pointer from an op, if it has one.
/// Returns null for ops without expressions.
pub fn getExpressionPtr(op: *IrOp) ?*IrExpr {
    return switch (op.data) {
        .Binding => |*b| b.expression,
        .Property => |*p| p.expression,
        .DomProperty => |*d| d.expression,
        .StyleProp => |*s| s.expression,
        .ClassProp => |*c| c.expression,
        .StyleMap => |*s| s.expression,
        .ClassMap => |*c| c.expression,
        .TwoWayProperty => |*t| t.expression,
        .InterpolateText => null, // has expressions[] but not a single expr
        .Conditional => |*c| c.condition_expr,
        .Repeater => |*r| r.track_by_fn orelse return null,
        .StoreLet => |*s| s.expression,
        .Variable => |*v| v.value,
        .Animation => |*a| a.expr,
        .AnimationBinding => |*a| a.expression,
        .AnimationString => |*a| a.expression,
        else => null,
    };
}

/// Get the const expression pointer from an op, if it has one.
pub fn getExpressionPtrConst(op: IrOp) ?*const IrExpr {
    return switch (op.data) {
        .Binding => |b| b.expression,
        .Property => |p| p.expression,
        .DomProperty => |d| d.expression,
        .StyleProp => |s| s.expression,
        .ClassProp => |c| c.expression,
        .StyleMap => |s| s.expression,
        .ClassMap => |c| c.expression,
        .TwoWayProperty => |t| t.expression,
        .Conditional => |c| c.condition_expr,
        .Repeater => |r| r.track_by_fn orelse null,
        .StoreLet => |s| s.expression,
        .Variable => |v| v.value,
        .Animation => |a| a.expr,
        .AnimationBinding => |a| a.expression,
        .AnimationString => |a| a.expression,
        else => null,
    };
}

/// Get the property/binding name from an op, if it has one.
pub fn getOpName(op: IrOp) ?[]const u8 {
    return switch (op.data) {
        .Binding => |b| b.name,
        .Property => |p| p.name,
        .DomProperty => |d| d.name,
        .StyleProp => |s| s.name,
        .ClassProp => |c| c.name,
        .TwoWayProperty => |t| t.name,
        .TwoWayListener => |t| t.name,
        .Listener => |l| l.name,
        .ElementStart => |e| e.name,
        .Statement => |s| s,
        else => null,
    };
}

/// Get the name of a Variable or StoreLet op.
pub fn getVariableName(op: IrOp) ?[]const u8 {
    return switch (op.data) {
        .StoreLet => |s| s.name,
        .Variable => |v| v.name,
        else => null,
    };
}

/// Binding priority for canonical ordering (lower = earlier).
pub fn bindingPriority(kind: OpKind) u8 {
    return switch (kind) {
        .TwoWayProperty, .TwoWayListener => 0,
        .Property, .DomProperty => 1,
        .Binding => 2,
        .ClassProp, .ClassMap => 3,
        .StyleProp, .StyleMap => 4,
        .InterpolateText => 5,
        .Pipe => 6,
        .AnimationBinding, .AnimationString => 7,
        .Advance => 8,
        .StoreLet, .Variable => 9,
        .Conditional => 10,
        .Repeater => 11,
        .I18nExpression => 12,
        else => 255,
    };
}

/// Create a zero-span IR op (used as fallback for inserted ops).
pub fn zeroOp(kind: OpKind, xref: u32, data: ir_ops.OpData) IrOp {
    return .{
        .kind = kind,
        .xref = xref,
        .source_span = .empty(),
        .data = data,
    };
}

/// Update the expression pointer in an op's data (based on kind).
pub fn updateOpExpression(op: *IrOp, new_expr: *IrExpr) void {
    switch (op.kind) {
        .Binding => op.data.Binding.expression = new_expr,
        .Property => op.data.Property.expression = new_expr,
        .DomProperty => op.data.DomProperty.expression = new_expr,
        .StyleProp => op.data.StyleProp.expression = new_expr,
        .ClassProp => op.data.ClassProp.expression = new_expr,
        .StyleMap => op.data.StyleMap.expression = new_expr,
        .ClassMap => op.data.ClassMap.expression = new_expr,
        .TwoWayProperty => op.data.TwoWayProperty.expression = new_expr,
        .Conditional => op.data.Conditional.condition_expr = new_expr,
        .StoreLet => op.data.StoreLet.expression = new_expr,
        .Variable => op.data.Variable.value = new_expr,
        .AnimationBinding => op.data.AnimationBinding.expression = new_expr,
        .AnimationString => op.data.AnimationString.expression = new_expr,
        else => {},
    }
}

/// Get the current nanosecond timestamp (portable).
pub fn getNsTimestamp() i64 {
    return std.time.nanoTimestamp();
}
