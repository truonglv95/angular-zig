/// phase_remove_content_selectors phase — Remove ng-content selectors
///
/// Port of: template/pipeline/src/phases/phase_remove_content_selectors.ts
///
/// After projection definitions are set up, the ng-content selectors
/// are no longer needed and can be removed from the op list.
const std = @import("std");
const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;
const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

/// Remove ng-content selectors after projection setup.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    // Remove Projection ops that have already been processed
    // into ProjectionDef ops
    var write: usize = 0;
    const items = view.create.ops.items;
    for (items) |op| {
        if (op.kind != .Projection) {
            items[write] = op;
            write += 1;
        }
    }
    view.create.ops.items.len = write;
}