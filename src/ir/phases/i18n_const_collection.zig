/// i18n_const_collection phase — Collect i18n messages into constant pool
///
/// Port of: template/pipeline/src/phases/i18n_const_collection.ts
///
/// Collects extracted i18n messages into the constant pool so they
/// can be referenced by ɵɵi18n instruction calls.
const std = @import("std");
const job_mod = @import("../job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

/// Collect i18n messages into the constant pool.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = view;
    // For each extracted i18n message:
    // 1. Serialize the message to a string format
    // 2. Add it to the constant pool (job.pool)
    // 3. Store the constant index on the message op
    // TODO: implement when message extraction is done
    _ = job;
}
