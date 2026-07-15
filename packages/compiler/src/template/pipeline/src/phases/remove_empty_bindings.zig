/// remove_empty_bindings phase
///
/// Port of: template/pipeline/src/phases/remove_empty_bindings.ts
///
/// Update phase — migrated from impl.zig
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;
const OpData = ir_ops.OpData;

const ir_enums = @import("../../ir/enums.zig");
const CompilationKind = ir_enums.CompilationKind;

const ir_expr = @import("../../ir/expression.zig");
const IrExpr = ir_expr.IrExpr;

const source_span = @import("../../../../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;


pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    var write: usize = 0;
    const items = view.update.ops.items;

    for (items) |op| {
        const should_keep = switch (op.data) {
            .InterpolateText => |it| it.expressions.len > 0,
            .Binding => |b| b.expression.kind != .EmptyExpr,
            .Property => |p| p.expression.kind != .EmptyExpr,
            .DomProperty => |d| d.expression.kind != .EmptyExpr,
            .StyleProp => |s| s.expression.kind != .EmptyExpr,
            .ClassProp => |c| c.expression.kind != .EmptyExpr,
            else => true,
        };
        if (should_keep) {
            items[write] = op;
            write += 1;
        }
    }

    view.update.ops.items.len = write;
    _ = job;
}
