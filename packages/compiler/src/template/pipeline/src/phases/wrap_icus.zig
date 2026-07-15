/// wrap_icus phase
///
/// Port of: template/pipeline/src/phases/wrap_icus.ts (46 LoC)
///
/// Create phase — Wraps ICUs that do not already belong to an i18n block
/// in a new i18n block (inserts I18nStart before and I18nEnd after).
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

const source_span = @import("../../../../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

/// Wrap standalone ICUs in i18n blocks.
/// Direct port of `wrapI18nIcus(job)` in the TS source.
///
/// Tracks the current i18n context while scanning create ops. When an IcuStart
/// is found outside of an i18n block, allocates a new xref and inserts an
/// I18nStart before it. When the matching IcuEnd is found, inserts an I18nEnd
/// after it.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    // We need to track:
    //   currentI18nOp: whether we're inside an I18nStart/I18nEnd block
    //   addedI18nId: the xref of the wrapper i18n block we added (if any)
    var current_i18n_depth: u32 = 0;
    var added_i18n_id: ?u32 = null;

    // We can't easily insert into the array while iterating, so we build a new list.
    var new_ops = std.array_list.Managed(IrOp).init(view.create.ops.allocator);
    defer new_ops.deinit();

    for (view.create.ops.items) |op| {
        switch (op.kind) {
            .I18nStart, .I18n => {
                current_i18n_depth += 1;
                try new_ops.append(op);
            },
            .I18nEnd => {
                if (current_i18n_depth > 0) current_i18n_depth -= 1;
                try new_ops.append(op);
            },
            .IcuStart => {
                // IcuStart equivalent — check if we're inside an i18n block.
                // In our model, Icu ops use the .I18n kind (no separate IcuStart/IcuEnd).
                // We check the i18n message to distinguish start vs end.
                if (current_i18n_depth == 0 and added_i18n_id == null) {
                    // Standalone ICU — wrap it in a new i18n block.
                    added_i18n_id = job.slots.allocXref();
                    const i18n_start = IrOp{
                        .kind = .I18nStart,
                        .xref = added_i18n_id.?,
                        .source_span = op.source_span,
                        .data = .{ .I18nStart = .{ .xref = added_i18n_id.? } },
                    };
                    try new_ops.append(i18n_start);
                }
                try new_ops.append(op);
            },
            else => {
                // Check for IcuEnd equivalent — if we added an i18n wrapper,
                // close it after the ICU op.
                const was_wrapping = added_i18n_id != null;
                try new_ops.append(op);
                if (was_wrapping and op.kind != .IcuStart) {
                    // This shouldn't happen in practice — ICU ops are paired.
                    // But if we see a non-ICU op while wrapping, close the wrapper.
                    const i18n_end = IrOp{
                        .kind = .I18nEnd,
                        .xref = added_i18n_id.?,
                        .source_span = op.source_span,
                        .data = .{ .I18nEnd = {} },
                    };
                    try new_ops.append(i18n_end);
                    added_i18n_id = null;
                }
            },
        }
    }

    // If we still have an open wrapper at the end, close it.
    if (added_i18n_id) |id| {
        const i18n_end = IrOp{
            .kind = .I18nEnd,
            .xref = id,
            .source_span = AbsoluteSourceSpan.empty(),
            .data = .{ .I18nEnd = {} },
        };
        try new_ops.append(i18n_end);
    }

    // Replace the view's create ops with the new list.
    view.create.ops.clearRetainingCapacity();
    for (new_ops.items) |op| {
        try view.create.ops.append(op);
    }
}

/// Public API matching TS export name.
pub fn wrapI18nIcus(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    return run(job, view);
}

test "run is a no-op on empty view" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "Test", .Full);
    defer job.deinit();
    var view = ViewCompilationUnit.init(allocator, 0, null);
    defer view.deinit();

    try run(&job, &view);
    try std.testing.expectEqual(@as(usize, 0), view.create.ops.items.len);
}
