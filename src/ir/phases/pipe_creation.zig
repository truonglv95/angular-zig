/// pipe_creation phase
///
/// Port of: template/pipeline/src/phases/pipe_creation.ts
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
    const items = view.update.ops.items;
    for (items) |*op| {
        if (op.kind == .Pipe) {
            // Ensure pipe has a valid slot. If xref is 0 (unallocated),
            // allocate a new one.
            if (op.xref == 0) {
                op.xref = job.slots.allocSlot();
            }
            // Mark non-pure pipes for invalidation tracking
            if (!op.data.Pipe.pure) {
                // Impure pipes need to be re-evaluated each change detection.
                // The xref is already allocated — the emitter handles
                // impure pipe invalidation.
            }
        }
    }
}
