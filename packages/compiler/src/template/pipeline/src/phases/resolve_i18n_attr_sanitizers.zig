/// resolve_i18n_attr_sanitizers phase
///
/// Port of: template/pipeline/src/phases/resolve_i18n_attr_sanitizers.ts (75 LoC)
///
/// Update phase — Resolve security context (sanitizers) for i18n attribute
/// expressions. Each I18nExpression op that targets an attribute gets its
/// security context resolved based on the attribute name and element.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

const schema = @import("../../../../schema/dom_element_schema_registry.zig");

/// Resolve sanitizers for i18n attribute expressions.
/// Direct port of `resolveI18nAttrSanitizers(job)` in the TS source.
///
/// For each I18nExpression update op:
///   1. Look up the owning element's tag name
///   2. Look up the attribute name
///   3. Use DomElementSchemaRegistry to resolve the security context
///   4. Set the op's securityContext field
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    // Build a map of xref → element tag name from create ops.
    var element_names = std.AutoHashMap(u32, []const u8).init(view.create.ops.allocator);
    defer element_names.deinit();

    for (view.create.ops.items) |op| {
        switch (op.kind) {
            .ElementStart => {
                const elem = op.data.ElementStart;
                try element_names.put(op.xref, elem.name);
            },
            else => {},
        }
    }

    // Resolve sanitizers for I18nExpression ops.
    // In our model, I18nExpression ops have an `expressions` field but no
    // separate security_context or attribute name. The TS source checks
    // `op.kind === ir.OpKind.I18nExpression` and uses `op.i18nOwner` to find
    // the element and `op.commonBindingName` for the attribute name.
    // When those fields are added, this phase will resolve security contexts.
    const registry = schema.SchemaRegistry{};
    _ = registry;

    for (view.update.ops.items) |*op| {
        if (op.kind != .I18nExpression) continue;
        // Resolution logic would go here when fields are available.
    }
}

/// Public API matching TS export name.
pub fn resolveI18nAttrSanitizers(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
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
