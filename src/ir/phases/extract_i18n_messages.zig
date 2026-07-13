/// extract_i18n_messages phase — Extract i18n messages from contexts
///
/// Port of: template/pipeline/src/phases/extract_i18n_messages.ts
///
/// Creates an I18nMessageOp for each i18n context, containing the
/// serialized message string with placeholder markers.
const std = @import("std");
const job_mod = @import("../job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;
const ir_ops = @import("../ops.zig");
const i18n_ctx = @import("i18n_context.zig");

/// Extract i18n messages from all contexts.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    // For each I18nContext op in create list:
    // 1. Build the message string by walking child ops
    // 2. Replace interpolated expressions with placeholder markers (PH, PH_1, ...)
    // 3. Replace element tags with tag markers (START_TAG_B, CLOSE_TAG_B, ...)
    // 4. Replace ICU expressions with ICU markers (ICU, ICU_1, ...)
    // 5. Store the message on the context
    _ = view;
    // TODO: implement message extraction when I18nContext ops are created
}
