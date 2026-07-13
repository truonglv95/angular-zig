/// resolve_dollar_event phase — Transform $event lexical reads to ReadVarExpr
///
/// Port of: template/pipeline/src/phases/resolve_dollar_event.ts
///
/// In Angular event bindings, `$event` is a special variable that refers to
/// the event payload. This phase finds all `$event` references inside
/// Listener/TwoWayListener/AnimationListener ops and marks them as consuming
/// the dollar event, then transforms the lexical read into a regular variable read.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

const ir_expr = @import("../../ir/expression.zig");
const IrExpr = ir_expr.IrExpr;
const ExpressionKind = @import("../../ir/enums.zig").ExpressionKind;

/// Transform $event references in listener ops.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    _ = view;
    // TODO: implement expression transformation for $event
    // This requires:
    // 1. Iterating over listener ops (Listener, TwoWayListener, AnimationListener)
    // 2. Finding LexicalReadExpr expressions with name "$event"
    // 3. Transforming them to ReadVariable expressions
    // 4. Setting op.consumesDollarEvent = true
    //
    // The current IR expression model doesn't have LexicalReadExpr yet —
    // it needs to be added to ExpressionKind enum and IrExpr data union.
    // For now, this is a no-op stub.
}
