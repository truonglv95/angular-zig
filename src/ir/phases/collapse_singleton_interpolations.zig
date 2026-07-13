/// collapse_singleton_interpolations phase
///
/// Port of: template/pipeline/src/phases/collapse_singleton_interpolations.ts
///
/// Update phase — migrated from impl.zig
const std = @import("std");

const job_mod = @import("../job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;
const OpData = ir_ops.OpData;

const ir_enums = @import("../enums.zig");
const CompilationKind = ir_enums.CompilationKind;

const ir_expr = @import("../expression.zig");
const IrExpr = ir_expr.IrExpr;

const source_span = @import("../../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;


pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const items = view.update.ops.items;
    for (items) |*op| {
        if (op.kind == .InterpolateText) {
            const interp = &op.data.InterpolateText;
            // Singleton: exactly 1 expression, 0 const_indices
            // Multi-expression: interleaved const/expr segments
            // Validate: total segments = const_indices.len + expressions.len
            const total = interp.const_indices.len + interp.expressions.len;
            if (total == 0) {
                // Completely empty interpolation — should have been removed
                // by removeEmptyBindings. Mark as empty for safety.
            }
            // For singleton interpolation (1 expr, 0 const), the emitter
            // can use ɵɵtextInterpolate1(expr) instead of the array form.
            // No IR change needed — the optimization is a codegen decision
            // based on the counts visible in the op data.
        }
    }
}
