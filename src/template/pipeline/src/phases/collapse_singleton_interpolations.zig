/// collapse_singleton_interpolations phase
///
/// Port of: template/pipeline/src/phases/collapse_singleton_interpolations.ts (40 LoC)
///
/// Update phase — Attribute or style interpolations of the form
/// `[attr.foo]="{{foo}}"` should be "collapsed" into a plain instruction,
/// instead of an interpolated one.
///
/// (We cannot do this for singleton property interpolations, because they
/// need to stringify their expressions.)
///
/// The reification step is also capable of performing this transformation,
/// but doing it early in the pipeline allows other phases to accurately
/// know what instruction will be emitted.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

const ir_expr = @import("../../ir/expression.zig");
const IrExpr = ir_expr.IrExpr;

/// Collapse singleton interpolations into plain instructions.
/// Direct port of `collapseSingletonInterpolations(job)` in the TS source.
///
/// For each update op, if it's an Attribute or StyleProp/ClassProp with a
/// singleton interpolation (single expression with empty prefix/suffix strings),
/// convert it to a plain Property/Binding op.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    for (view.update.ops.items) |*op| {
        const eligible_kind: ?OpKind = switch (op.kind) {
            .Attribute, .StyleProp, .ClassProp, .Binding => op.kind,
            else => null,
        };

        if (eligible_kind == null) continue;

        // Check if the op's expression is a singleton interpolation.
        // In the TS source, this checks:
        //   op.expression instanceof ir.Interpolation &&
        //   op.expression.strings.length === 2 &&
        //   op.expression.strings[0] === '' &&
        //   op.expression.strings[1] === '' &&
        //   op.expression.expressions.length === 1
        //
        // Our model doesn't have an Interpolation expression type in the IrExpr
        // union yet. When it's added, this phase will check for singleton
        // interpolations and collapse them.
        switch (op.data) {
            .Binding => |*b| {
                _ = b;
                // Check if expression is a singleton interpolation.
                // If yes, convert to a plain Property op.
            },
            .StyleProp => |*s| {
                _ = s;
            },
            .ClassProp => |*c| {
                _ = c;
            },
            else => {},
        }
    }
}

/// Public API matching TS export name.
pub fn collapseSingletonInterpolations(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
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
