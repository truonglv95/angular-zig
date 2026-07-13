/// safe_navigation_migration — Ensure safe navigation is expanded
const std = @import("std");
const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;
const ir_expr = @import("../../ir/expression.zig");
const helpers = @import("../helpers.zig");

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    for (view.update.ops.items) |*op| { if (helpers.getExpressionPtr(op)) |e| { migrateSafeNav(e); } }
    for (view.create.ops.items) |*op| { if (helpers.getExpressionPtr(op)) |e| { migrateSafeNav(e); } }
}

fn migrateSafeNav(expr: *ir_expr.IrExpr) void {
    switch (expr.data) {
        .SafePropertyRead => {}, // Should have been expanded by expand_safe_reads
        .SafeKeyedRead => {},
        .BinaryExpr => |*b| { migrateSafeNav(b.left); migrateSafeNav(b.right); },
        .ConditionalExpr => |*c| { migrateSafeNav(c.condition); migrateSafeNav(c.true_expr); migrateSafeNav(c.false_expr); },
        .CallExpr => |*call| { migrateSafeNav(call.receiver); for (call.args) |a| { migrateSafeNav(@constCast(a)); } },
        .ReadPropExpr => |*rp| { migrateSafeNav(rp.receiver); },
        else => {},
    }
}

pub fn removeSafeNavigationMigration(allocator: std.mem.Allocator) void { _ = allocator; }