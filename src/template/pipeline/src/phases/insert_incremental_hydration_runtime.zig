/// insert_incremental_hydration_runtime — Insert ɵɵincrementalHydration
const std = @import("std");
const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    if (view.parent != null) return;
    try view.create.append(.{
        .kind = .Statement, .xref = 0, .source_span = .empty(),
        .data = .{ .Statement = "ɵɵincrementalHydration(0)" },
    });
}
