/// remove_i18n_contexts phase — Remove i18n context ops after processing
///
/// Port of: template/pipeline/src/phases/remove_i18n_contexts.ts
///
/// After i18n messages are extracted and constants collected,
/// the i18n context ops are no longer needed and can be removed.
const std = @import("std");
const job_mod = @import("../job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;
const ir_ops = @import("../ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

/// Remove i18n context ops after processing.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    // Remove I18n context ops from create list (they're metadata only)
    var write: usize = 0;
    const items = view.create.ops.items;
    for (items) |op| {
        // Keep all ops for now — I18nContext ops aren't in the current IR
        items[write] = op;
        write += 1;
    }
    view.create.ops.items.len = write;
}
