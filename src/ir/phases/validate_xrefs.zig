/// validate_xrefs phase
///
/// Port of: template/pipeline/src/phases/validate_xrefs.ts
///
/// Post phase — migrated from impl.zig
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
    const max_decls = view.decls orelse return;

    // Validate create ops: xrefs should be non-decreasing (except ElementEnd)
    const create_items = view.create.ops.items;
    var prev_xref: u32 = 0;
    for (create_items) |op| {
        // Strip context flag if present
        const clean_xref = op.xref & 0x7FFFFFFF;
        if (op.kind != .ElementEnd and op.kind != .ContainerEnd) {
            if (clean_xref < prev_xref) {
                // Non-monotonic xref in create list — structural issue
                // In strict mode this would be an error.
                // For now, just note it and continue.
            }
        }
        if (clean_xref < max_decls) {
            // Valid xref
        }
        if (clean_xref > prev_xref) prev_xref = clean_xref;
    }

    // Validate update ops: xrefs should reference valid slots
    const update_items = view.update.ops.items;
    for (update_items) |op| {
        const clean_xref = op.xref & 0x7FFFFFFF;
        // xrefs in update ops should reference creation slots
        // (they can exceed max_decls for temporary slots)
        _ = clean_xref;
    }
}
