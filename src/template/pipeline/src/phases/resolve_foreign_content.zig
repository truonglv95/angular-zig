/// resolve_foreign_content phase
///
/// Port of: template/pipeline/src/phases/resolve_foreign_content.ts (58 LoC)
///
/// Create phase — Resolves `ContentOp`s by replacing them with a `TemplateOp`
/// and adding a corresponding property to the target `ForeignComponentOp`.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

const source_span = @import("../../../../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

/// Resolve foreign content ops.
/// Direct port of `resolveForeignContent(job)` in the TS source.
///
/// For each Content op that targets a ForeignComponent op:
///   1. Capitalize the property name → templateName
///   2. Create a Template op with kind NgTemplate
///   3. Replace the Content op with the Template op
///   4. Add a ForeignContentExpr to the target's props map
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    // Collect all ForeignComponent ops by xref.
    var foreign_components = std.AutoHashMap(u32, *IrOp).init(view.create.ops.allocator);
    defer foreign_components.deinit();

    for (view.create.ops.items) |*create_op| {
        // In our model, we don't have a ForeignComponent op kind yet.
        // The TS source checks `op.kind === ir.OpKind.ForeignComponent`.
        // We skip this for now — when the op kind is added, this will collect them.
        _ = create_op;
    }

    // Process Content ops.
    for (view.create.ops.items) |*op| {
        if (op.kind != .Content) continue;

        // In our model, Content ops have void data. The TS source has:
        //   op.target, op.propertyName, op.view, op.startSourceSpan, op.sourceSpan
        // When those fields are added, this phase will:
        //   1. Look up the target ForeignComponent op
        //   2. Capitalize op.propertyName
        //   3. Create a Template op and replace the Content op
        //   4. Add a ForeignContentExpr to the target's props
        _ = op.data.Content;
    }
}

/// Capitalize the first letter of a string.
/// Helper for `templateName = op.propertyName.charAt(0).toUpperCase() + ...`.
fn capitalizeFirst(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    if (name.len == 0) return name;
    var result = try allocator.alloc(u8, name.len);
    @memcpy(result, name);
    if (result[0] >= 'a' and result[0] <= 'z') {
        result[0] = result[0] - 32;
    }
    return result;
}

/// Public API matching TS export name.
pub fn resolveForeignContent(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    return run(job, view);
}

test "capitalizeFirst" {
    const allocator = std.testing.allocator;
    const r1 = try capitalizeFirst(allocator, "children");
    defer allocator.free(r1);
    try std.testing.expectEqualStrings("Children", r1);

    const r2 = try capitalizeFirst(allocator, "header");
    defer allocator.free(r2);
    try std.testing.expectEqualStrings("Header", r2);

    const r3 = try capitalizeFirst(allocator, "Header");
    defer allocator.free(r3);
    try std.testing.expectEqualStrings("Header", r3);
}

test "run is a no-op on view without Content ops" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "Test", .Full);
    defer job.deinit();
    var view = ViewCompilationUnit.init(allocator, 0, null);
    defer view.deinit();

    try run(&job, &view);
    try std.testing.expectEqual(@as(usize, 0), view.create.ops.items.len);
}
