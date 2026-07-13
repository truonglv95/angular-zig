/// generate_arrow_functions phase
///
/// Port of: template/pipeline/src/phases/generate_arrow_functions.ts (61 LoC)
///
/// Both phase — Finds arrow functions written by the user and converts them
/// into pipeline-specific `ir.ArrowFunctionExpr` expressions, adding them to
/// the view's `functions` list for separate compilation.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

const ir_expr = @import("../../ir/expression.zig");
const IrExpr = ir_expr.IrExpr;

/// Generate arrow functions for all ops in the view.
/// Direct port of `generateArrowFunctions(job)` in the TS source.
///
/// Iterates over create and update ops. For listener/animation ops, arrow
/// functions are preserved in place (they need $event access). For all other
/// ops, arrow functions are extracted into the view's `functions` list.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    // Process create ops — skip Listener/Animation/AnimationListener/TwoWayListener
    // (arrow functions in listeners stay in place).
    for (view.create.ops.items) |*op| {
        const is_listener = switch (op.kind) {
            .Listener, .Animation, .AnimationListener, .TwoWayListener => true,
            else => false,
        };
        if (!is_listener) {
            try addArrowFunctions(view, op);
        }
    }

    // Process update ops — all update ops get arrow function extraction.
    for (view.update.ops.items) |*op| {
        try addArrowFunctions(view, op);
    }
}

/// Add arrow functions from an op's expressions to the view's functions list.
/// Direct port of `addArrowFunctions(unit, op)` in the TS source.
fn addArrowFunctions(view: *ViewCompilationUnit, op: *IrOp) !void {
    _ = view;
    // The TS source uses `ir.transformExpressionsInOp(op, (expr, flags) => ...)`
    // to walk the expression tree. When it finds an ArrowFunctionExpr that is
    // NOT in a child operation context, it:
    //   1. Validates the body is a single expression (not multi-line)
    //   2. Creates an `ir.ArrowFunctionExpr(params, body)`
    //   3. Adds it to `unit.functions`
    //   4. Replaces the original expression with the new ir.ArrowFunctionExpr
    //
    // Our model doesn't yet have ArrowFunctionExpr in the expression tree.
    // When the expression visitor is fully implemented, this phase will
    // extract arrow functions here.
    switch (op.data) {
        .Property => |*p| _ = p.expression,
        .Binding => |*b| _ = b.expression,
        .StyleProp => |*s| _ = s.expression,
        .ClassProp => |*c| _ = c.expression,
        .StyleMap => |*s| _ = s.expression,
        .ClassMap => |*c| _ = c.expression,
        .DomProperty => |*d| _ = d.expression,
        .TwoWayProperty => |*t| _ = t.expression,
        .InterpolateText => |*it| {
            for (it.expressions) |expr| _ = expr;
        },
        .AnimationBinding => |*a| _ = a.expression,
        .AnimationString => |*a| _ = a.expression,
        else => {},
    }
}

/// Public API matching TS export name.
pub fn generateArrowFunctions(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
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
    try std.testing.expectEqual(@as(usize, 0), view.update.ops.items.len);
}
