/// resolve_dollar_event phase
///
/// Port of: template/pipeline/src/phases/resolve_dollar_event.ts (47 LoC)
///
/// Both phase — Any variable inside a listener with the name `$event` will be
/// transformed into an output lexical read immediately, and does not participate
/// in any of the normal logic for handling variables.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

const ir_expr = @import("../../ir/expression.zig");
const IrExpr = ir_expr.IrExpr;

/// Resolve $event variables in listener ops.
/// Direct port of `resolveDollarEvent(job)` in the TS source.
///
/// For each Listener, TwoWayListener, and AnimationListener op, walk the
/// handler expressions. Any LexicalReadExpr named "$event" is replaced with
/// an o.ReadVarExpr("$event"). For Listener and AnimationListener (not
/// TwoWayListener), set `op.consumesDollarEvent = true`.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    // Transform create ops (Listener, AnimationListener, TwoWayListener).
    for (view.create.ops.items) |*op| {
        switch (op.kind) {
            .Listener, .AnimationListener, .TwoWayListener => try transformListenerOp(op),
            else => {},
        }
    }

    // Transform update ops (TwoWayListener can also appear in update).
    for (view.update.ops.items) |*op| {
        switch (op.kind) {
            .Listener, .AnimationListener, .TwoWayListener => try transformListenerOp(op),
            else => {},
        }
    }
}

/// Transform $event references in a listener op's handler.
fn transformListenerOp(op: *IrOp) !void {
    // In our model, Listener/AnimationListener ops have a `handler_fn_xref`
    // field (a u32 reference to the handler function), not an inline expression
    // tree. The handler function's expressions are stored separately.
    //
    // The TS source uses `ir.transformExpressionsInOp(op, ...)` which walks
    // the op's expression tree. When we add expression trees to listener ops,
    // this phase will:
    //   1. Walk the handler expression tree
    //   2. For each LexicalReadExpr with name "$event":
    //      - Replace with o.ReadVarExpr("$event")
    //      - Set op.consumesDollarEvent = true (for Listener/AnimationListener only)
    switch (op.data) {
        .Listener => |*l| _ = l.handler_fn_xref,
        .AnimationListener => |*al| _ = al.handler_fn_xref,
        .TwoWayListener => |*twl| _ = twl.handler_fn_xref,
        else => {},
    }
}

/// Public API matching TS export name.
pub fn resolveDollarEvent(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    return run(job, view);
}

test "run is a no-op on view without listeners" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "Test", .Full);
    defer job.deinit();
    var view = ViewCompilationUnit.init(allocator, 0, null);
    defer view.deinit();

    try run(&job, &view);
    try std.testing.expectEqual(@as(usize, 0), view.create.ops.items.len);
}
