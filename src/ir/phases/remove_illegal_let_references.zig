/// remove_illegal_let_references phase — Remove illegal @let references
///
/// Port of: template/pipeline/src/phases/remove_illegal_let_references.ts
///
/// Removes @let declarations that reference variables not in scope,
/// which would cause runtime errors.
const std = @import("std");
const job_mod = @import("../job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

/// Remove illegal @let references.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    _ = view;
    // TODO: validate @let references and remove illegal ones
}