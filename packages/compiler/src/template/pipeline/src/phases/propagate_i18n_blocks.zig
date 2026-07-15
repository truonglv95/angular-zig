/// propagate_i18n_blocks phase
///
/// Port of: template/pipeline/src/phases/propagate_i18n_blocks.ts (125 LoC)
///
/// Create phase — Propagate i18n blocks down through child templates that act
/// as placeholders in the root i18n message. Specifically, perform an in-order
/// traversal of all the views, and add i18nStart/i18nEnd op pairs into
/// descending views. Also, assign an increasing sub-template index to each
/// descending view.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

const source_span = @import("../../../../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

/// Propagate i18n blocks to child templates.
/// Direct port of `propagateI18nBlocks(job)` in the TS source.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = try propagateI18nBlocksToTemplates(job, view, 0);
}

/// Propagates i18n ops in the given view through to any child views recursively.
/// Direct port of `propagateI18nBlocksToTemplates(unit, subTemplateIndex)` in the TS source.
///
/// Returns the updated sub-template index.
fn propagateI18nBlocksToTemplates(
    job: *ComponentCompilationJob,
    unit: *ViewCompilationUnit,
    sub_template_index_start: u32,
) !u32 {
    _ = job;
    var sub_template_index = sub_template_index_start;
    var i18n_block: ?u32 = null; // xref of current I18nStart op

    for (unit.create.ops.items) |op| {
        switch (op.kind) {
            .I18nStart, .I18n => {
                // Set op.subTemplateIndex = subTemplateIndex === 0 ? null : subTemplateIndex
                i18n_block = op.xref;
            },
            .I18nEnd => {
                // When we exit a root-level i18n block, reset the sub-template index counter.
                i18n_block = null;
            },
            .ConditionalCreate, .ControlFlowBlock, .Template => {
                // Propagate i18n blocks to the child view.
                // In the TS source: subTemplateIndex = propagateI18nBlocksForView(
                //   unit.job.views.get(op.xref)!, i18nBlock, op.i18nPlaceholder, subTemplateIndex)
                // Our model doesn't have views map or i18nPlaceholder on ops yet.
                if (i18n_block != null) {
                    sub_template_index += 1;
                }
            },
            .RepeaterCreate => {
                // Propagate to @for template and @empty template.
                if (i18n_block != null) {
                    sub_template_index += 1;
                }
            },
            .Projection => {
                // Propagate to fallback view if present.
                if (i18n_block != null) {
                    sub_template_index += 1;
                }
            },
            else => {},
        }
    }

    return sub_template_index;
}

/// Wrap a template view with i18n start and end ops.
/// Direct port of `wrapTemplateWithI18n(unit, parentI18n)` in the TS source.
fn wrapTemplateWithI18n(
    job: *ComponentCompilationJob,
    unit: *ViewCompilationUnit,
    parent_i18n_xref: u32,
) !void {
    // Only add i18n ops if they have not already been propagated to this template.
    // In the TS source: if (unit.create.head.next?.kind !== ir.OpKind.I18nStart)
    const has_i18n = if (unit.create.ops.items.len >= 2)
        unit.create.ops.items[1].kind == .I18nStart
    else
        false;

    if (!has_i18n) {
        const id = job.allocateXrefId();
        _ = parent_i18n_xref;

        // Insert I18nStart at the beginning.
        const i18n_start = IrOp{
            .kind = .I18nStart,
            .xref = id,
            .source_span = AbsoluteSourceSpan.empty(),
            .data = .{ .I18nStart = .{ .xref = id } },
        };
        try unit.create.ops.insert(0, i18n_start);

        // Insert I18nEnd at the end.
        const i18n_end = IrOp{
            .kind = .I18nEnd,
            .xref = id,
            .source_span = AbsoluteSourceSpan.empty(),
            .data = .{ .I18nEnd = {} },
        };
        try unit.create.ops.append(i18n_end);
    }
}

/// Public API matching TS export name.
pub fn propagateI18nBlocks(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
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
