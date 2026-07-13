/// i18n_text_extraction phase — Extract translatable text from templates
///
/// Port of: template/pipeline/src/phases/i18n_text_extraction.ts
///
/// Extracts translatable text content from Text and BoundText ops
/// and creates i18n message nodes for them.
const std = @import("std");
const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;
const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

/// Extract translatable text from templates.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    // Scan create ops for Text ops inside i18n blocks
    // Extract their text content into i18n message nodes
    for (view.create.ops.items) |op| {
        if (op.kind == .Text) {
            // TODO: check if inside i18n block, extract text
        }
    }
}
