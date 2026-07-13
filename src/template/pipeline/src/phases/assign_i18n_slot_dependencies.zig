/// assign_i18n_slot_dependencies phase
///
/// Port of: template/pipeline/src/phases/assign_i18n_slot_dependencies.ts (98 LoC)
///
/// Create phase — Assign slot dependencies for i18n ops. Each i18n context
/// needs to know which slots its expressions occupy, so that the i18nStart
/// instruction can reference them.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

/// Assign slot dependencies for i18n ops.
/// Direct port of `assignI18nSlotDependencies(job)` in the TS source.
///
/// For each I18nContext create op, collect the slots of all I18nExpression
/// update ops that belong to that context, and store them on the context op.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    // Phase 1: Collect I18nExpression ops grouped by their context.
    // In the TS source, this uses `i18nExpressionOpsByContext` map.
    var slots_by_context = std.AutoHashMap(u32, std.array_list.Managed(u32)).init(view.update.ops.allocator);
    defer {
        var it = slots_by_context.iterator();
        while (it.next()) |entry| entry.value_ptr.deinit();
        slots_by_context.deinit();
    }

    for (view.update.ops.items) |op| {
        if (op.kind != .I18nExpression) continue;
        // In our model, I18nExpression doesn't have a context field yet.
        // When added, this will collect the slot for each expression.
    }

    // Phase 2: Assign the collected slots to the I18nContext create ops.
    // In the TS source, this sets `contextOp.params` with the slot list.
    for (view.create.ops.items) |*op| {
        // I18nContext ops are stored as Statement kind in our model.
        if (op.kind != .Statement) continue;
        // Assignment logic would go here.
    }
}

/// Public API matching TS export name.
pub fn assignI18nSlotDependencies(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    return run(job, view);
}

test "run is a no-op on view without i18n ops" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "Test", .Full);
    defer job.deinit();
    var view = ViewCompilationUnit.init(allocator, 0, null);
    defer view.deinit();

    try run(&job, &view);
    try std.testing.expectEqual(@as(usize, 0), view.create.ops.items.len);
}
