/// convert_i18n_bindings phase — Convert i18n attribute bindings
///
/// Port of: template/pipeline/src/phases/convert_i18n_bindings.ts
///
/// Converts i18n attribute bindings into i18n ops that can be
/// processed by the i18n pipeline.
const std = @import("std");
const job_mod = @import("../job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

/// Convert i18n attribute bindings.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    _ = view;
    // TODO: convert i18n attribute bindings to I18nStart/I18nEnd ops
}
