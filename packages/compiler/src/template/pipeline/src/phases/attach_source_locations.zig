/// attach_source_locations phase
///
/// Port of: template/pipeline/src/phases/attach_source_locations.ts
///
/// Both phase — migrated from impl.zig
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
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const default_span = AbsoluteSourceSpan{ .start = 1, .end = 1 };

    // Process create ops
    {
        var last_span = default_span;
        const items = view.create.ops.items;
        for (items) |*op| {
            if (op.source_span.start == 0 and op.source_span.end == 0) {
                op.source_span = last_span;
            } else {
                last_span = op.source_span;
            }
        }
    }

    // Process update ops
    {
        var last_span = default_span;
        const items = view.update.ops.items;
        for (items) |*op| {
            if (op.source_span.start == 0 and op.source_span.end == 0) {
                op.source_span = last_span;
            } else {
                last_span = op.source_span;
            }
        }
    }
}
