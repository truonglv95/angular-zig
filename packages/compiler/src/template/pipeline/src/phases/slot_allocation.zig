/// slot_allocation phase
///
/// Port of: template/pipeline/src/phases/slot_allocation.ts
///
/// Post phase — migrated from impl.zig
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
    var max_slot: u32 = 0;

    // Scan creation ops for max xref
    const create_items = view.create.ops.items;
    for (create_items) |op| {
        if (op.xref > max_slot) max_slot = op.xref;
    }

    // Also scan update ops for any xrefs that might exceed creation ops
    const update_items = view.update.ops.items;
    for (update_items) |op| {
        // Strip the context-needed flag (bit 31) before comparing
        const clean_xref = op.xref & 0x7FFFFFFF;
        if (clean_xref > max_slot) max_slot = clean_xref;
    }

    // decls = max_slot + 1 (number of declaration slots needed)
    view.decls = max_slot + 1;
}

// ─── Merged from allocate_interpolation_slots.zig (1:1 structure consolidation) ──
pub fn allocateInterpolationSlots(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
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
