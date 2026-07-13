/// compact_xrefs phase
///
/// Port of: template/pipeline/src/phases/compact_xrefs.ts
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

    const MAX_XREFS = 4096;

    // Collect all xrefs used in both create and update lists
    var xref_used: [MAX_XREFS]bool = undefined;
    @memset(&xref_used, false);

    for (view.create.ops.items) |op| {
        const x = op.xref & 0x7FFFFFFF;
        if (x < MAX_XREFS) xref_used[x] = true;
    }
    for (view.update.ops.items) |op| {
        const x = op.xref & 0x7FFFFFFF;
        if (x < MAX_XREFS) xref_used[x] = true;
    }

    // Build dense mapping: old_xref → new_xref
    var xref_map: [MAX_XREFS]u32 = undefined;
    @memset(&xref_map, 0);
    var new_idx: u32 = 0;
    for (xref_used, 0..) |used, old_xref| {
        if (used) {
            xref_map[old_xref] = new_idx;
            new_idx += 1;
        }
    }

    // Apply mapping to create ops
    for (view.create.ops.items) |*op| {
        const old = op.xref;
        const clean = old & 0x7FFFFFFF;
        if (clean < MAX_XREFS) {
            op.xref = (old & 0x80000000) | xref_map[clean]; // preserve context flag
        }
    }

    // Apply mapping to update ops
    for (view.update.ops.items) |*op| {
        const old = op.xref;
        const clean = old & 0x7FFFFFFF;
        if (clean < MAX_XREFS) {
            op.xref = (old & 0x80000000) | xref_map[clean]; // preserve context flag
        }
    }
}
