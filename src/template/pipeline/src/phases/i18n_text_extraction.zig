/// i18n_text_extraction phase
///
/// Port of: template/pipeline/src/phases/i18n_text_extraction.ts (118 LoC)
///
/// Both phase — Removes text nodes within i18n blocks since they are already
/// hardcoded into the i18n message. Also, replaces interpolations on these
/// text nodes with i18n expressions of the non-text portions, which will be
/// applied later.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

const ir_enums = @import("../../ir/enums.zig");
const I18nParamResolutionTime = ir_enums.I18nParamResolutionTime;
const I18nExpressionFor = ir_enums.I18nExpressionFor;

const source_span = @import("../../../../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

/// Convert i18n text by removing text nodes in i18n blocks and replacing
/// interpolations with i18n expressions.
/// Direct port of `convertI18nText(job)` in the TS source.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    // Phase 1: Scan create ops to find text nodes within i18n blocks.
    var current_i18n: ?u32 = null; // xref of current I18nStart op
    const current_icu: ?u32 = null; // xref of current IcuStart op (not yet tracked)

    // Maps for tracking text nodes in i18n blocks.
    var text_node_i18n_blocks = std.AutoHashMap(u32, u32).init(view.create.ops.allocator);
    defer text_node_i18n_blocks.deinit();
    var text_node_icus = std.AutoHashMap(u32, ?u32).init(view.create.ops.allocator);
    defer text_node_icus.deinit();
    var icu_placeholder_by_text = std.AutoHashMap(u32, u32).init(view.create.ops.allocator);
    defer icu_placeholder_by_text.deinit();

    // Filter create ops: remove Text ops inside i18n blocks, or replace with
    // IcuPlaceholder ops if they have an icuPlaceholder.
    var new_create = std.array_list.Managed(IrOp).init(view.create.ops.allocator);
    defer new_create.deinit();

    for (view.create.ops.items) |op| {
        switch (op.kind) {
            .I18nStart, .I18n => {
                current_i18n = op.xref;
                try new_create.append(op);
            },
            .I18nEnd => {
                current_i18n = null;
                try new_create.append(op);
            },
            .Text => {
                if (current_i18n != null) {
                    // Text node inside an i18n block.
                    try text_node_i18n_blocks.put(op.xref, current_i18n.?);
                    try text_node_icus.put(op.xref, current_icu);

                    // In the TS source, if op.icuPlaceholder is not null, replace
                    // with an IcuPlaceholderOp. Otherwise, remove the text op.
                    // Our model doesn't have icuPlaceholder on Text ops yet.
                    // For now, we remove the text op (skip it).
                } else {
                    try new_create.append(op);
                }
            },
            else => {
                try new_create.append(op);
            },
        }
    }

    // Replace create ops.
    view.create.ops.clearRetainingCapacity();
    for (new_create.items) |op| {
        try view.create.ops.append(op);
    }

    // Phase 2: Update InterpolateText ops that target removed text nodes.
    // Replace them with I18nExpression ops.
    var new_update = std.array_list.Managed(IrOp).init(view.update.ops.allocator);
    defer new_update.deinit();

    for (view.update.ops.items) |op| {
        if (op.kind == .InterpolateText) {
            const interp = op.data.InterpolateText;
            if (text_node_i18n_blocks.get(op.xref)) |i18n_xref| {
                // This interpolation targets a text node in an i18n block.
                // Replace with I18nExpression ops (one per expression).
                _ = i18n_xref;
                _ = interp;
                // For now, we skip the interpolation (it's been accounted for
                // in the i18n message). When I18nExpression ops are fully
                // modeled, we'd create one per expression here.
                continue;
            }
        }
        try new_update.append(op);
    }

    // Replace update ops.
    view.update.ops.clearRetainingCapacity();
    for (new_update.items) |op| {
        try view.update.ops.append(op);
    }
}

/// Public API matching TS export name.
pub fn convertI18nText(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    return run(job, view);
}

test "run is a no-op on view without i18n blocks" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "Test", .Full);
    defer job.deinit();
    var view = ViewCompilationUnit.init(allocator, 0, null);
    defer view.deinit();

    try run(&job, &view);
    try std.testing.expectEqual(@as(usize, 0), view.create.ops.items.len);
}
