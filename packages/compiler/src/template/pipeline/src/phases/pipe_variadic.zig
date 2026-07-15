/// pipe_variadic phase — Convert pipes with >4 args to variadic form
///
/// Port of: template/pipeline/src/phases/pipe_variadic.ts
///
/// Pipes with more than 4 arguments use a different runtime instruction
/// (ɵɵpipeBindV instead of ɵɵpipeBind1..4). This phase detects PipeBindingExpr
/// with >4 args and converts them to PipeBindingVariadicExpr.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;

const ir_expr = @import("../../ir/expression.zig");
const IrExpr = ir_expr.IrExpr;
const ExpressionKind = @import("../../ir/enums.zig").ExpressionKind;

const helpers = @import("../helpers.zig");

/// Maximum number of arguments for fixed-arity pipeBind instructions.
const MAX_FIXED_PIPE_ARGS = 4;

/// Convert pipes with >4 args to variadic form.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    // Process update ops — pipes are in the update phase
    for (view.update.ops.items) |*op| {
        if (helpers.getExpressionPtr(op)) |expr_ptr| {
            convertVariadicPipes(expr_ptr);
        }
    }
}

/// Recursively walk expression tree and convert pipes with >4 args.
fn convertVariadicPipes(expr: *IrExpr) void {
    switch (expr.data) {
        .PipeBinding => |*pb| {
            if (pb.args.len > MAX_FIXED_PIPE_ARGS) {
                // Convert to variadic form
                // TODO: add PipeBindingVariadic to ExpressionKind
                // For now, this is a no-op — the pipe stays as PipeBinding
                // and will be handled by the emitter with a fallback
            }
            // Recurse into args
            for (pb.args) |arg| {
                convertVariadicPipes(@constCast(arg));
            }
        },
        .BinaryExpr => |*b| {
            convertVariadicPipes(b.left);
            convertVariadicPipes(b.right);
        },
        .ConditionalExpr => |*c| {
            convertVariadicPipes(c.condition);
            convertVariadicPipes(c.true_expr);
            convertVariadicPipes(c.false_expr);
        },
        .CallExpr => |*call| {
            convertVariadicPipes(call.receiver);
            for (call.args) |arg| {
                convertVariadicPipes(@constCast(arg));
            }
        },
        .ReadPropExpr => |*rp| {
            convertVariadicPipes(rp.receiver);
        },
        else => {},
    }
}
