/// deduplicate_text_bindings phase
///
/// Port of: template/pipeline/src/phases/deduplicate_text_bindings.ts
///
/// Status: STUB — not yet implemented.
/// This phase needs to be ported from the Angular TypeScript original.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

/// Phase entry point.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    _ = view;
    // TODO: implement deduplicate_text_bindings phase
}


// ─── Merged from merge_adjacent_text.zig (1:1 structure consolidation) ──
pub fn mergeAdjacentText(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    var write: usize = 0;
    var last_text_xref: ?u32 = null;
    const items = view.create.ops.items;

    for (items) |op| {
        if (op.kind == .Text and op.xref == last_text_xref) {
            // Same xref as previous Text — skip duplicate
            continue;
        }
        if (op.kind == .Text) {
            last_text_xref = op.xref;
        } else {
            last_text_xref = null;
        }
        items[write] = op;
        write += 1;
    }
    view.create.ops.items.len = write;
}
