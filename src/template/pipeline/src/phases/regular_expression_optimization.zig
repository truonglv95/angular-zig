/// regular_expression_optimization phase — Optimize regex patterns
///
/// Port of: template/pipeline/src/phases/regular_expression_optimization.ts
///
/// This phase is a no-op in the Zig port — regex patterns are compiled
/// at build time using Zig's comptime machinery rather than at runtime.
const std = @import("std");
const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

/// Optimize regex patterns (no-op in Zig — comptime regexes).
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    _ = view;
    // No-op: Zig uses comptime-compiled regexes, no runtime optimization needed.
}