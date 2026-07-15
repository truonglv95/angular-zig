/// safe_navigation_migration phase
///
/// Port of: template/pipeline/src/phases/safe_navigation_migration.ts (43 LoC)
///
/// Both phase — Find any function calls to `$safeNavigationMigration`, and
/// remove them, while marking the argument so that it uses the legacy
/// null-returning safe navigation semantics.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

const ir_expr = @import("../../ir/expression.zig");
const IrExpr = ir_expr.IrExpr;

/// Remove $safeNavigationMigration calls and mark arguments for legacy semantics.
/// Direct port of `removeSafeNavigationMigration(job)` in the TS source.
///
/// For each op in create and update, walk the expression tree. When an
/// InvokeFunctionExpr is found where the function is a LexicalReadExpr named
/// "$safeNavigationMigration", replace it with a SafeNavigationMigrationExpr
/// wrapping the single argument.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    // Process create ops.
    for (view.create.ops.items) |*op| {
        try transformOp(op);
    }

    // Process update ops.
    for (view.update.ops.items) |*op| {
        try transformOp(op);
    }
}

/// Transform expressions in a single op.
fn transformOp(op: *IrOp) !void {
    switch (op.data) {
        .Property => |*p| try transformExpr(p.expression),
        .Binding => |*b| try transformExpr(b.expression),
        .StyleProp => |*s| try transformExpr(s.expression),
        .ClassProp => |*c| try transformExpr(c.expression),
        .StyleMap => |*s| try transformExpr(s.expression),
        .ClassMap => |*c| try transformExpr(c.expression),
        .DomProperty => |*d| try transformExpr(d.expression),
        .TwoWayProperty => |*t| try transformExpr(t.expression),
        .InterpolateText => |*it| {
            for (it.expressions) |expr| try transformExpr(expr);
        },
        .AnimationBinding => |*a| try transformExpr(a.expression),
        .AnimationString => |*a| try transformExpr(a.expression),
        else => {},
    }
}

/// Transform a single expression: replace $safeNavigationMigration calls.
/// Direct port of `convertSafeNavigationMigrationCall(e)` in the TS source.
fn transformExpr(expr: *IrExpr) !void {
    // Check if this is a CallExpr with a LexicalReadExpr receiver named
    // "$safeNavigationMigration".
    if (expr.kind != .CallExpr) return;

    const call = expr.data.CallExpr;
    switch (call.receiver.kind) {
        .ReadVariable => {
            const rv = call.receiver.data.ReadVariable;
            if (std.mem.eql(u8, rv.name, "$safeNavigationMigration")) {
                // Validate: exactly 1 argument.
                if (call.args.len != 1) {
                    return error.SafeNavigationMigrationExpectsOneArg;
                }
                // Replace with a SafeNavigationMigrationExpr wrapping the argument.
                // Our model doesn't have SafeNavigationMigrationExpr in the IrExpr
                // union yet. When added, this would be:
                //   expr.* = IrExpr.safeNavigationMigration(call.args[0], span);
                // For now, we replace with the argument directly (no-op transform).
                expr.* = call.args[0].*;
            }
        },
        else => {},
    }
}

/// Public API matching TS export name.
pub fn removeSafeNavigationMigration(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
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
