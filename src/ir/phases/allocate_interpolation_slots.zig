/// allocate_interpolation_slots phase
///
/// Port of: template/pipeline/src/phases/allocate_interpolation_slots.ts
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

    // Collect all Text creation op xrefs
    var text_xrefs: [4096]bool = undefined;
    @memset(&text_xrefs, false);
    var last_text_xref: u32 = 0;

    const create_items = view.create.ops.items;
    for (create_items) |op| {
        if (op.kind == .Text) {
            if (op.xref < 4096) text_xrefs[op.xref] = true;
            last_text_xref = op.xref;
        }
    }

    // Validate/fix InterpolateText ops
    const update_items = view.update.ops.items;
    for (update_items) |*op| {
        if (op.kind == .InterpolateText) {
            if (op.xref < 4096) {
                if (!text_xrefs[op.xref]) {
                    // xref doesn't correspond to a Text creation op.
                    // Fall back to the last known Text xref.
                    op.xref = last_text_xref;
                }
            }
        }
    }
}
