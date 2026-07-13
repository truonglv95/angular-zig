/// has_const_expression_collection phase
///
/// Port of: template/pipeline/src/phases/has_const_expression_collection.ts
///
/// Update phase — migrated from impl.zig
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;
const OpData = ir_ops.OpData;

const ir_enums = @import("../../ir/enums.zig");
const CompilationKind = ir_enums.CompilationKind;

const ir_expr = @import("../../ir/expression.zig");
const IrExpr = ir_expr.IrExpr;

const source_span = @import("../../../../source_span.zig");

// ─── Shared helpers ──
const getExpressionPtr = helpers.getExpressionPtr;
const helpers = @import("../helpers.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;


pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const items = view.update.ops.items;
    for (items) |*op| {
        const expr = getExpressionPtr(op) orelse continue;
        resolvePureRefs(expr);
    }
}

/// Recursively walk an expression tree and resolve pure function references.
fn resolvePureRefs(expr: *IrExpr) void {
    switch (expr.kind) {
        .CallExpr => {
            const call = &expr.data.CallExpr;
            // Check if the receiver is a PureFunctionExpr
            if (call.receiver.kind == .PureFunctionExpr) {
                // The fn_ref is already stored in the PureFunctionExpr.
                // Mark by keeping the expression as-is; codegen reads fn_ref
                // directly from the PureFunctionExpr receiver.
            }
            // Recurse into arguments
            for (call.args) |arg| {
                resolvePureRefs(@constCast(arg));
            }
        },
        .BinaryExpr => {
            const bin = &expr.data.BinaryExpr;
            resolvePureRefs(bin.left);
            resolvePureRefs(bin.right);
        },
        .ConditionalExpr => {
            const cond = expr.data.ConditionalExpr;
            resolvePureRefs(cond.condition);
            resolvePureRefs(cond.true_expr);
            resolvePureRefs(cond.false_expr);
        },
        .NotExpr => {
            resolvePureRefs(expr.data.NotExpr.expression);
        },
        else => {},
    }
}
