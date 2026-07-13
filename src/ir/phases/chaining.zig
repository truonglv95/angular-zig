/// chaining phase — Process chain expressions (a; b; c)
///
/// Port of: template/pipeline/src/phases/chaining.ts
///
/// Chain expressions are sequences of expressions separated by semicolons.
/// This phase processes Chain AST nodes and ensures they are properly
/// represented in the IR.
const std = @import("std");
const job_mod = @import("../job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;
const ir_ops = @import("../ops.zig");
const IrOp = ir_ops.IrOp;
const ir_expr = @import("../expression.zig");
const IrExpr = ir_expr.IrExpr;
const helpers = @import("helpers.zig");

/// Process chain expressions in all ops.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    // Process create and update ops
    for (view.create.ops.items) |*op| {
        if (helpers.getExpressionPtr(op)) |expr_ptr| {
            processChains(expr_ptr);
        }
    }
    for (view.update.ops.items) |*op| {
        if (helpers.getExpressionPtr(op)) |expr_ptr| {
            processChains(expr_ptr);
        }
    }
}

/// Recursively process Chain expressions.
fn processChains(expr: *IrExpr) void {
    // The current IR doesn't have a Chain expression kind.
    // Chains are handled during expression parsing — the parser already
    // converts them to a sequence of statements.
    // This phase is a no-op until ChainExpr is added to ExpressionKind.
    _ = expr;
}