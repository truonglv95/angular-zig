/// resolve_defer_deps_fns phase
///
/// Port of: template/pipeline/src/phases/resolve_defer_deps_fns.ts (39 LoC)
///
/// Create phase — Resolve the dependency function of a deferred block.
/// For each Defer op, if it has an `ownResolverFn` but no `resolverFn` yet,
/// generate a shared function reference via `job.pool.getSharedFunctionReference`.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

/// Resolve the dependency function of deferred blocks.
/// Direct port of `resolveDeferDepsFns(job)` in the TS source.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    for (view.create.ops.items) |*op| {
        if (op.kind != .Defer) continue;

        // In TS:
        //   if (op.resolverFn !== null) continue;
        //   if (op.ownResolverFn !== null) {
        //     if (op.handle.slot === null) throw ...;
        //     const fullPathName = unit.fnName?.replace('_Template', '');
        //     op.resolverFn = job.pool.getSharedFunctionReference(
        //       op.ownResolverFn,
        //       `${fullPathName}_Defer_${op.handle.slot}_DepsFn`,
        //       false,
        //     );
        //   }

        // Our model doesn't yet have resolverFn/ownResolverFn fields on the Defer op.
        // When those fields are added, this phase will populate them here.
        _ = op.data.Defer;
    }
}

/// Public API matching TS export name.
pub fn resolveDeferDepsFns(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    return run(job, view);
}

test "run is a no-op on view without defer ops" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "Test", .Full);
    defer job.deinit();
    var view = ViewCompilationUnit.init(allocator, 0, null);
    defer view.deinit();

    try run(&job, &view);
    try std.testing.expectEqual(@as(usize, 0), view.create.ops.items.len);
}
