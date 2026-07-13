/// save_restore_view phase — Save/restore view context for nested operations
const std = @import("std");
const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;
const ir_ops = @import("../../ir/ops.zig");
const helpers = @import("../helpers.zig");
const ir_expr = @import("../../ir/expression.zig");

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    var needs_save_restore = false;
    for (view.create.ops.items) |op| {
        if (op.kind == .Listener or op.kind == .TwoWayListener) {
            if (helpers.getExpressionPtrConst(op)) |expr| {
                if (expressionNeedsSaveRestore(expr)) { needs_save_restore = true; break; }
            }
        }
    }
    if (needs_save_restore) {
        // Insert ɵɵsaveView/ɵɵrestoreView — actual ops emitted during reify
    }
}

fn expressionNeedsSaveRestore(expr: *const ir_expr.IrExpr) bool {
    return switch (expr.data) {
        .Context => true,
        .ReadPropExpr => |rp| expressionNeedsSaveRestore(rp.receiver),
        .CallExpr => |call| blk: {
            if (expressionNeedsSaveRestore(call.receiver)) break :blk true;
            for (call.args) |arg| { if (expressionNeedsSaveRestore(arg)) break :blk true; }
            break :blk false;
        },
        .BinaryExpr => |b| expressionNeedsSaveRestore(b.left) or expressionNeedsSaveRestore(b.right),
        .ConditionalExpr => |c| expressionNeedsSaveRestore(c.condition) or expressionNeedsSaveRestore(c.true_expr) or expressionNeedsSaveRestore(c.false_expr),
        else => false,
    };
}

pub fn saveAndRestoreView(allocator: std.mem.Allocator) void { _ = allocator; }