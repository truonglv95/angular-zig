/// expand_safe_reads phase
///
/// Port of: template/pipeline/src/phases/expand_safe_reads.ts
///
/// Update phase — migrated from impl.zig
const std = @import("std");

const job_mod = @import("../job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;
const OpData = ir_ops.OpData;

const ir_enums = @import("../enums.zig");
const CompilationKind = ir_enums.CompilationKind;

const ir_expr = @import("../expression.zig");
const IrExpr = ir_expr.IrExpr;

const source_span = @import("../../source_span.zig");

// ─── Shared helpers ──
const updateOpExpression = helpers.updateOpExpression;
const getExpressionPtr = helpers.getExpressionPtr;
const helpers = @import("helpers.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;


pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;
    const items = view.update.ops.items;

    for (items) |*op| {
        const expr = getExpressionPtr(op) orelse continue;
        if (expr.kind == .SafePropertyRead or expr.kind == .SafeKeyedRead) {
            // Allocate a new ConditionalCase expression
            const new_expr = try allocator.create(IrExpr);
            new_expr.* = .{
                .kind = .ConditionalCase,
                .span = expr.span,
                .data = .{
                    .ConditionalCase = .{
                        .condition = expr, // The original safe read serves as condition context
                        .value = expr, // Same — emitter knows to extract the property
                    },
                },
            };
            // Update the op's expression to point to the wrapper
            updateOpExpression(op, new_expr);
        }
    }
}
