/// insert_incremental_hydration_runtime phase
///
/// Port of: template/pipeline/src/phases/insert_incremental_hydration_runtime.ts
///
/// Inserts ɵɵincrementalHydration instruction calls at the beginning
/// of template functions for components that support incremental hydration.
const std = @import("std");
const job_mod = @import("../job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

/// Insert incremental hydration runtime instructions.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    _ = view;
    // TODO: insert ɵɵincrementalHydration at the start of create ops
}