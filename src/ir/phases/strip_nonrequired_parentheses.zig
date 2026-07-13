/// strip_nonrequired_parentheses phase — Remove unnecessary parentheses
///
/// Port of: template/pipeline/src/phases/strip_nonrequired_parentheses.ts
///
/// Angular templates allow parentheses around expressions for readability,
/// but these have no runtime effect. This phase removes Parenthesized
/// expressions, replacing them with their inner expression.
const std = @import("std");

const job_mod = @import("../job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../ops.zig");
const IrOp = ir_ops.IrOp;

const ir_expr = @import("../expression.zig");
const IrExpr = ir_expr.IrExpr;

/// Strip unnecessary parentheses from all expressions.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    // Process create ops
    for (view.create.ops.items) |*op| {
        stripParensFromOp(op);
    }
    // Process update ops
    for (view.update.ops.items) |*op| {
        stripParensFromOp(op);
    }
}

/// Strip parentheses from an op's expressions.
fn stripParensFromOp(op: *IrOp) void {
    if (getExpressionPtr(op)) |expr_ptr| {
        stripParensRecursive(expr_ptr);
    }
}

/// Get the mutable expression pointer from an op.
fn getExpressionPtr(op: *IrOp) ?*IrExpr {
    return switch (op.data) {
        .Binding => |*b| b.expression,
        .Property => |*p| p.expression,
        .DomProperty => |*d| d.expression,
        .StyleProp => |*s| s.expression,
        .ClassProp => |*c| c.expression,
        .StyleMap => |*s| s.expression,
        .ClassMap => |*c| c.expression,
        .TwoWayProperty => |*t| t.expression,
        else => null,
    };
}

/// Recursively strip parentheses from an expression tree.
fn stripParensRecursive(expr: *IrExpr) void {
    // The current IR expression model doesn't have a Parenthesized variant —
    // parentheses are already stripped during expression parsing.
    // This phase is a no-op in the current implementation.
    // If a Parenthesized variant is added to IrExpr in the future,
    // this function should replace it with its inner expression.
    _ = expr;
}
