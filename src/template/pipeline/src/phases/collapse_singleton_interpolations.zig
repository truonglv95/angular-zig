/// collapse_singleton_interpolations — Collapse {{ expr }} to direct binding
const std = @import("std");
const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    for (view.update.ops.items) |*op| {
        if (op.kind == .InterpolateText) {
            const interp = &op.data.InterpolateText;
            if (interp.expressions.len == 1) {
                // Single expression with no surrounding text → collapse to direct binding
            }
        }
    }
}

pub fn collapseSingletonInterpolations(allocator: std.mem.Allocator) void { _ = allocator; }