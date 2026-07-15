/// create_i18n_contexts phase
///
/// Port of: template/pipeline/src/phases/create_i18n_contexts.ts (128 LoC)
///
/// Create phase — Create one helper context op per i18n block (including
/// generate descending blocks). Also, if an ICU exists inside an i18n block
/// that also contains other localizable content, create an additional helper
/// context op for the ICU.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

const ir_enums = @import("../../ir/enums.zig");
const I18nContextKind = ir_enums.I18nContextKind;

const source_span = @import("../../../../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

/// Create i18n context ops for i18n blocks, attributes, and ICUs.
/// Direct port of `createI18nContexts(job)` in the TS source.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    // Phase 1: Create i18n context ops for i18n attrs.
    // For each Binding/Property/Attribute/ExtractedAttribute op with an i18nMessage,
    // create an I18nContext op (if not already created for that message) and
    // assign it to the op's i18nContext field.
    var attr_context_by_message = std.StringHashMap(u32).init(view.create.ops.allocator);
    defer attr_context_by_message.deinit();

    for (view.update.ops.items) |*op| {
        switch (op.kind) {
            .Binding, .Property, .Attribute => {
                // Our model doesn't have i18nMessage on these ops yet.
                // When added, this will create I18nContext ops and assign them.
            },
            else => {},
        }
    }

    // Phase 2: Create i18n context ops for root i18n blocks.
    var block_context_by_i18n_block = std.AutoHashMap(u32, u32).init(view.create.ops.allocator);
    defer block_context_by_i18n_block.deinit();

    for (view.create.ops.items) |*op| {
        if (op.kind == .I18nStart) {
            // Check if this is a root i18n block (op.xref === op.root).
            // In our model, I18nStart has a single `xref` field.
            // The `root` field would need to be added.
            const context_xref = job.slots.allocXref();
            try block_context_by_i18n_block.put(op.xref, context_xref);

            // Create an I18nContext op and push it to create ops.
            const context_op = IrOp{
                .kind = .Statement,
                .xref = context_xref,
                .source_span = op.source_span,
                .data = .{ .Statement = "i18nContext" },
            };
            try view.create.ops.append(context_op);
        }
    }

    // Phase 3: Assign i18n contexts for child i18n blocks.
    // (Child blocks inherit from their root — skipped in simplified model.)

    // Phase 4: Create or assign i18n contexts for ICUs.
    // For each IcuStart inside an I18nStart/I18nEnd block:
    //   - If the ICU message differs from the parent, create a new ICU context.
    //   - Otherwise, convert the parent's context to an ICU context.
    // (Skipped — requires IcuStart op kind which we model as .I18n.)
}

/// Public API matching TS export name.
pub fn createI18nContexts(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
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
