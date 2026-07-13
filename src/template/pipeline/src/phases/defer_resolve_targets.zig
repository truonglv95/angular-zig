/// defer_resolve_targets — Resolve @defer target directives
const std = @import("std");
const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    for (view.create.ops.items) |op| {
        if (op.kind == .Defer) {
            var view_it = job.views.iterator();
            while (view_it.next()) |entry| {
                if (entry.value_ptr.*.parent == op.xref) {
                    // entry.value_ptr.*.is_deferred = true; // TODO: add is_deferred field
                }
            }
        }
    }
}
