/// convert_i18n_bindings phase
///
/// Port of: template/pipeline/src/phases/convert_i18n_bindings.ts (81 LoC)
///
/// Update phase — Some binding instructions in the update block may actually
/// correspond to i18n bindings. In that case, they should be replaced with
/// i18nExp instructions for the dynamic portions.
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

/// Convert i18n bindings to i18nExp instructions.
/// Direct port of `convertI18nBindings(job)` in the TS source.
///
/// For each Property/Attribute update op with an i18nContext:
///   1. Find the corresponding I18nAttributes create op
///   2. For each expression in the interpolation, create an I18nExpression op
///   3. Replace the original op with the list of I18nExpression ops
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    // Collect I18nAttributes create ops by target xref.
    // In our model, we don't have an I18nAttributes op kind. The TS source
    // checks `op.kind === ir.OpKind.I18nAttributes`. We skip this collection
    // for now.

    // Process update ops: replace Property/Attribute ops with i18n contexts.
    var new_update = std.array_list.Managed(IrOp).init(view.update.ops.allocator);
    defer new_update.deinit();

    for (view.update.ops.items) |op| {
        switch (op.kind) {
            .Property, .Attribute => {
                // In the TS source, this checks:
                //   if (op.i18nContext === null) continue;
                //   if (!(op.expression instanceof ir.Interpolation)) continue;
                // Our model doesn't have i18nContext on Property/Attribute ops yet.
                // When added, this phase will replace interpolation expressions
                // with I18nExpression ops.
                try new_update.append(op);
            },
            else => {
                try new_update.append(op);
            },
        }
    }

    // Replace update ops.
    view.update.ops.clearRetainingCapacity();
    for (new_update.items) |op| {
        try view.update.ops.append(op);
    }
}

/// Public API matching TS export name.
pub fn convertI18nBindings(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    return run(job, view);
}

test "run is a no-op on empty view" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "Test", .Full);
    defer job.deinit();
    var view = ViewCompilationUnit.init(allocator, 0, null);
    defer view.deinit();

    try run(&job, &view);
    try std.testing.expectEqual(@as(usize, 0), view.update.ops.items.len);
}
