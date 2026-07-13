/// regular_expression_optimization — No-op (Zig uses comptime parsing)
const std = @import("std");
const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job; _ = view;
    // No-op: Zig uses comptime string parsing, not runtime regex
}

pub fn optimizeRegularExpressions(allocator: std.mem.Allocator) void { _ = allocator; }