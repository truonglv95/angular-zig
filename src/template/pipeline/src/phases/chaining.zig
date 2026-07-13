/// chaining — Process chain expressions (a; b; c)
const std = @import("std");
const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;
const ir_expr = @import("../../ir/expression.zig");
const helpers = @import("../helpers.zig");

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    for (view.update.ops.items) |*op| { if (helpers.getExpressionPtr(op)) |e| { processChains(e); } }
    for (view.create.ops.items) |*op| { if (helpers.getExpressionPtr(op)) |e| { processChains(e); } }
}

fn processChains(expr: *ir_expr.IrExpr) void {
    switch (expr.data) {
        .BinaryExpr => |*b| { processChains(b.left); processChains(b.right); },
        .ConditionalExpr => |*c| { processChains(c.condition); processChains(c.true_expr); processChains(c.false_expr); },
        .CallExpr => |*call| { processChains(call.receiver); for (call.args) |a| { processChains(@constCast(a)); } },
        else => {},
    }
}
