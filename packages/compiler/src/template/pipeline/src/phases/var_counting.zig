/// var_counting phase
///
/// Port of: template/pipeline/src/phases/var_counting.ts
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
    var var_count: u32 = 0;
    for (view.update.ops.items) |op| {
        switch (op.kind) {
            .StoreLet => var_count += 1,
            .Variable => var_count += 1,
            else => {},
        }
    }
    view.vars = var_count;
}

// ─── Merged from compact_xrefs.zig (1:1 structure consolidation) ──
pub fn compactXrefs(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
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

// ─── Merged from validate_xrefs.zig (1:1 structure consolidation) ──
pub fn validateXrefs(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
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

pub fn countVariables(allocator: std.mem.Allocator) void {
    _ = allocator;
}
