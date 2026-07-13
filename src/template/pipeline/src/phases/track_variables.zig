/// track_variables — Track @for track expression variables
const std = @import("std");
const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;
const helpers = @import("../helpers.zig");

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    for (view.update.ops.items) |op| {
        if (op.kind == .Repeater) {
            if (helpers.getExpressionPtrConst(op)) |expr| {
                const count = collectUsedVariables(expr);
                _ = count;
            }
        }
    }
}

fn collectUsedVariables(expr: *const @import("../../ir/expression.zig").IrExpr) u32 {
    return switch (expr.data) {
        .ReadVariable => 1,
        .BinaryExpr => |b| collectUsedVariables(b.left) + collectUsedVariables(b.right),
        .ConditionalExpr => |c| collectUsedVariables(c.condition) + collectUsedVariables(c.true_expr) + collectUsedVariables(c.false_expr),
        .CallExpr => |call| blk: { var n = collectUsedVariables(call.receiver); for (call.args) |a| { n += collectUsedVariables(a); } break :blk n; },
        .ReadPropExpr => |rp| collectUsedVariables(rp.receiver),
        else => 0,
    };
}
