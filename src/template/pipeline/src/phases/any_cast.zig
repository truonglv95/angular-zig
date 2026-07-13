/// any_cast phase — Remove $any() cast function calls
///
/// Port of: template/pipeline/src/phases/any_cast.ts
///
/// Angular's `$any(x)` is a compile-time cast to `any` type that has no
/// runtime effect. This phase finds all InvokeFunctionExpr calls to `$any`
/// and replaces them with their single argument.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;

const ir_expr = @import("../../ir/expression.zig");
const IrExpr = ir_expr.IrExpr;

/// Remove $any() casts from all expressions in the view.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    // Process create ops
    for (view.create.ops.items) |*op| {
        try removeAnysFromOp(op);
    }
    // Process update ops
    for (view.update.ops.items) |*op| {
        try removeAnysFromOp(op);
    }
}

/// Find and remove $any() calls from an op's expressions.
fn removeAnysFromOp(op: *IrOp) !void {
    // Get the expression pointer from the op, if it has one
    if (getExpressionPtr(op)) |expr_ptr| {
        removeAnysRecursive(expr_ptr);
    }
}

/// Get the mutable expression pointer from an op.
fn getExpressionPtr(op: *IrOp) ?*IrExpr {
    return switch (op.data) {
        .Binding => |*b| b.expression,
        .Property => |*p| p.expression,
        .DomProperty => |*d| d.expression,
        .StyleProp => |*s| s.expression,
        .ClassProp => |*c| c.expression,
        .StyleMap => |*s| s.expression,
        .ClassMap => |*c| c.expression,
        .TwoWayProperty => |*t| t.expression,
        // InterpolateText has multiple expressions — handled separately
        else => null,
    };
}

/// Recursively walk an expression tree and remove $any() calls.
fn removeAnysRecursive(expr: *IrExpr) void {
    switch (expr.data) {
        .CallExpr => |*call| {
            // Check if this is a $any() call
            const recv = call.receiver;
            if (recv.data == .ReadVariable and
                std.mem.eql(u8, recv.data.ReadVariable.name, "$any"))
            {
                // Replace this $any(arg) call with arg
                if (call.args.len == 1) {
                    expr.* = call.args[0].*;
                    // Recurse into the replacement (it might also have $any)
                    removeAnysRecursive(expr);
                    return;
                }
            }
            // Recurse into args
            for (call.args) |arg| {
                removeAnysRecursive(arg);
            }
        },
        .BinaryExpr => |*b| {
            removeAnysRecursive(b.left);
            removeAnysRecursive(b.right);
        },
        .ConditionalExpr => |*c| {
            removeAnysRecursive(c.condition);
            removeAnysRecursive(c.true_expr);
            removeAnysRecursive(c.false_expr);
        },
        .ReadPropExpr => |*rp| {
            removeAnysRecursive(rp.receiver);
        },
        .SafeKeyedRead => |*skr| {
            removeAnysRecursive(skr.receiver);
            removeAnysRecursive(skr.key);
        },
        .NotExpr => |*n| {
            removeAnysRecursive(n.expression);
        },
        else => {},
    }
}
