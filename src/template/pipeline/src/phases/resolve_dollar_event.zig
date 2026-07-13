/// resolve_dollar_event phase — Transform $event references in listeners
const std = @import("std");
const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;
const ir_ops = @import("../../ir/ops.zig");
const ir_expr = @import("../../ir/expression.zig");
const helpers = @import("../helpers.zig");

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    for (view.create.ops.items) |*op| {
        if (op.kind == .Listener or op.kind == .TwoWayListener) {
            if (helpers.getExpressionPtr(op)) |expr_ptr| { transformDollarEvent(expr_ptr); }
        }
    }
    for (view.update.ops.items) |*op| {
        if (helpers.getExpressionPtr(op)) |expr_ptr| { transformDollarEvent(expr_ptr); }
    }
}

fn transformDollarEvent(expr: *ir_expr.IrExpr) void {
    switch (expr.data) {
        .ReadVariable => |rv| { _ = rv; },
        .BinaryExpr => |*b| { transformDollarEvent(b.left); transformDollarEvent(b.right); },
        .ConditionalExpr => |*c| { transformDollarEvent(c.condition); transformDollarEvent(c.true_expr); transformDollarEvent(c.false_expr); },
        .CallExpr => |*call| { transformDollarEvent(call.receiver); for (call.args) |arg| { transformDollarEvent(@constCast(arg)); } },
        .ReadPropExpr => |*rp| { transformDollarEvent(rp.receiver); },
        .NotExpr => |*n| { transformDollarEvent(n.expression); },
        else => {},
    }
}

pub fn resolveDollarEvent(allocator: std.mem.Allocator) void { _ = allocator; }