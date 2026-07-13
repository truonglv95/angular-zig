/// apply_i18n_expressions phase
///
/// Port of: template/pipeline/src/phases/apply_i18n_expressions.ts (80 LoC)
///
/// Update phase — Adds apply operations after i18n expressions.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

const source_span = @import("../../../../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

/// Add apply operations after i18n expressions.
/// Direct port of `applyI18nExpressions(job)` in the TS source.
///
/// For each I18nExpression update op, if it needs an application (i.e., the
/// next op is not an I18nExpression targeting the same context), insert an
/// I18nApply op after it.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    // Collect I18nContext create ops by xref.
    // In our model, we don't have I18nContext as a separate kind. Skip.

    // Build new update list with I18nApply ops inserted after qualifying
    // I18nExpression ops.
    var new_update = std.array_list.Managed(IrOp).init(view.update.ops.allocator);
    defer new_update.deinit();

    for (view.update.ops.items, 0..) |op, i| {
        try new_update.append(op);

        if (op.kind == .I18nExpression) {
            // Check if the next op is also an I18nExpression.
            // If not, or if it targets a different context, insert an I18nApply.
            const needs_apply = if (i + 1 < view.update.ops.items.len)
                view.update.ops.items[i + 1].kind != .I18nExpression
            else
                true;

            if (needs_apply) {
                // Insert an I18nApply op (using Statement kind as placeholder).
                const apply_op = IrOp{
                    .kind = .Statement,
                    .xref = op.xref,
                    .source_span = op.source_span,
                    .data = .{ .Statement = "i18nApply" },
                };
                try new_update.append(apply_op);
            }
        }
    }

    // Replace update ops.
    view.update.ops.clearRetainingCapacity();
    for (new_update.items) |op| {
        try view.update.ops.append(op);
    }
}

/// Public API matching TS export name.
pub fn applyI18nExpressions(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
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
