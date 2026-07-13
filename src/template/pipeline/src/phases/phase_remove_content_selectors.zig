/// phase_remove_content_selectors — Remove Projection ops after processing
const std = @import("std");
const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    var write: usize = 0;
    const items = view.create.ops.items;
    for (items) |op| {
        if (op.kind != .Projection) { items[write] = op; write += 1; }
    }
    view.create.ops.items.len = write;
}
