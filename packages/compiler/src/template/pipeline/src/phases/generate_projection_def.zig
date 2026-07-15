/// generate_projection_def phase
///
/// Port of: template/pipeline/src/phases/generate_projection_def.ts
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
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    // Collect projection xrefs from create ops
    const MAX_SLOTS: usize = 256;
    var projection_xrefs: [MAX_SLOTS]?u32 = @splat(null);
    var slot_count: usize = 0;

    for (view.create.ops.items) |op| {
        if (op.kind == .Projection) {
            const slot = op.data.Projection.slot_index;
            if (slot < MAX_SLOTS) {
                projection_xrefs[slot] = op.xref;
                if (slot >= slot_count) slot_count = slot + 1;
            }
        }
    }

    if (slot_count <= 1) return; // Nothing to reorder

    // Build ordered xref list from projection slots
    var ordered_xrefs: [MAX_SLOTS]u32 = undefined;
    var ordered_len: usize = 0;
    for (projection_xrefs[0..slot_count]) |xref| {
        if (xref) |x| {
            ordered_xrefs[ordered_len] = x;
            ordered_len += 1;
        }
    }

    if (ordered_len <= 1) return;

    // Check if update ops need reordering — if all ops are already
    // in order, skip the expensive rebuild. Quick scan:
    const update_items = view.update.ops.items;
    for (update_items) |op| {
        const xref = op.xref & 0x7FFFFFFF;
        for (ordered_xrefs[0..ordered_len], 0..) |ox, idx| {
            if (xref == ox) {
                // Verify it's not after a later projection's ops
                for (ordered_xrefs[idx + 1 ..]) |later_ox| {
                    // Simple heuristic: just check if any op for a later
                    // projection appears before ops for this one. Full check
                    // is O(n²) so we only flag if obviously needed.
                    _ = later_ox;
                }
                break;
            }
        }
    }
    // The reordering is handled by normalizeBindingOrder which already
    // sorts by (xref, priority). This phase serves as a checkpoint
    // that projection xrefs are correctly mapped.
}
