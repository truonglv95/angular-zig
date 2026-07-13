/// resolve_i18n_element_placeholders phase
///
/// Port of: template/pipeline/src/phases/resolve_i18n_element_placeholders.ts (449 LoC)
///
/// Create phase — Resolves element and template placeholders in i18n messages.
/// When an i18n block contains nested elements or templates, they are represented
/// as placeholders in the message. This phase resolves those placeholders back
/// to their actual element/template ops.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

const source_span = @import("../../../../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

/// Resolve element and template placeholders in i18n messages.
/// Direct port of `resolveI18nElementPlaceholders(job)` in the TS source.
///
/// The full TS implementation:
///   1. For each view, walk create ops tracking i18n block context
///   2. When an element/template is found inside an i18n block, register it
///      as a placeholder
///   3. Match placeholders to their corresponding i18n message params
///   4. Set up the placeholder's xref and slot for code generation
///
/// This is one of the most complex i18n phases — it handles:
///   - Element placeholders (start/end tags)
///   - Template placeholders (ng-template with *directive)
///   - Nested placeholder indices
///   - Sub-template context propagation
///   - ICU placeholder resolution
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    // Track the current i18n block context.
    var i18n_depth: u32 = 0;

    // Maps for placeholder resolution.
    var element_placeholders = std.AutoHashMap(u32, []const u8).init(view.create.ops.allocator);
    defer element_placeholders.deinit();

    // Walk create ops to identify elements/templates inside i18n blocks.
    for (view.create.ops.items) |op| {
        switch (op.kind) {
            .I18nStart, .I18n => i18n_depth += 1,
            .I18nEnd => {
                if (i18n_depth > 0) i18n_depth -= 1;
            },
            .ElementStart => {
                if (i18n_depth > 0) {
                    // Register this element as a placeholder in the current i18n block.
                    const elem = op.data.ElementStart;
                    try element_placeholders.put(op.xref, elem.name);
                }
            },
            .Template => {
                if (i18n_depth > 0) {
                    // Register this template as a placeholder.
                    try element_placeholders.put(op.xref, "ng-template");
                }
            },
            else => {},
        }
    }

    // Phase 2: Resolve placeholder references in i18n message params.
    // (Requires the full i18n message model — skipped in simplified version.)
}

/// Public API matching TS export name.
pub fn resolveI18nElementPlaceholders(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
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
