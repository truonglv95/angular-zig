/// track_variables phase
///
/// Port of: template/pipeline/src/phases/track_variables.ts (44 LoC)
///
/// Create phase — Inside the `track` expression on a `for` repeater, the
/// `$index` and `$item` variables are ambiently available. This phase finds
/// those variable usages and replaces them with the appropriate output reads.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

const ir_expr = @import("../../ir/expression.zig");
const IrExpr = ir_expr.IrExpr;

/// Generate track variables for RepeaterCreate ops.
/// Direct port of `generateTrackVariables(job)` in the TS source.
///
/// For each RepeaterCreate op, transform its `track` expression:
///   - LexicalReadExpr names in `varNames.$index` → `o.variable('$index')`
///   - LexicalReadExpr name === `varNames.$implicit` → `o.variable('$item')`
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    for (view.create.ops.items) |*op| {
        if (op.kind != .RepeaterCreate) continue;

        // In our model, RepeaterCreate has no data (void). The track expression
        // and varNames would need to be added to the op's data.
        // When those fields are added, this phase will:
        //   1. Walk op.track expression tree
        //   2. For each LexicalReadExpr, check if its name is in varNames.$index
        //      or equals varNames.$implicit
        //   3. Replace with o.variable('$index') or o.variable('$item') respectively
        _ = op.data.RepeaterCreate;
    }
}

/// Public API matching TS export name.
pub fn generateTrackVariables(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    return run(job, view);
}

test "run is a no-op on view without RepeaterCreate" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "Test", .Full);
    defer job.deinit();
    var view = ViewCompilationUnit.init(allocator, 0, null);
    defer view.deinit();

    try run(&job, &view);
    try std.testing.expectEqual(@as(usize, 0), view.create.ops.items.len);
}
