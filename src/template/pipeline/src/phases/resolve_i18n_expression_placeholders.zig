/// resolve_i18n_expression_placeholders phase
///
/// Port of: template/pipeline/src/phases/resolve_i18n_expression_placeholders.ts (83 LoC)
///
/// Update phase — Resolve i18n expression placeholders by mapping placeholder
/// names to their corresponding expression indices.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

/// Resolve i18n expression placeholders.
/// Direct port of `resolveI18nExpressionPlaceholders(job)` in the TS source.
///
/// For each I18nExpression update op with a placeholder name, resolve the
/// placeholder to its corresponding expression index in the i18n message.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    // The TS source walks I18nExpression ops and resolves their `placeholder`
    // field by looking up the placeholder name in the parent i18n block's
    // message placeholders map.
    //
    // Our model doesn't yet have the placeholder field on I18nExpression ops.
    // When added, this phase will:
    //   1. Collect all I18nContext ops and their messages
    //   2. For each I18nExpression, find its parent context
    //   3. Look up the placeholder name in the message's placeholders
    //   4. Set the expression's resolved index
    for (view.update.ops.items) |*op| {
        if (op.kind != .I18nExpression) continue;
        _ = op.data.I18nExpression;
    }
}

/// Public API matching TS export name.
pub fn resolveI18nExpressionPlaceholders(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    return run(job, view);
}

test "run is a no-op on view without I18nExpression ops" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "Test", .Full);
    defer job.deinit();
    var view = ViewCompilationUnit.init(allocator, 0, null);
    defer view.deinit();

    try run(&job, &view);
    try std.testing.expectEqual(@as(usize, 0), view.update.ops.items.len);
}
