/// track_fn_optimization phase
///
/// Port of: template/pipeline/src/phases/track_fn_optimization.ts
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
    _ = job;
    const allocator = view.update.allocator;
    const items = view.update.ops.items;

    for (items) |*op| {
        if (op.kind != .Repeater) continue;
        const repeater = &op.data.Repeater;
        if (repeater.track_by_fn != null) continue;

        // Generate default trackBy: uses $index identity
        const track_expr = try allocator.create(IrExpr);
        track_expr.* = .{
            .kind = .ReadVariable,
            .span = .empty(),
            .data = .{ .ReadVariable = .{ .name = "$index", .xref = 0 } },
        };
        repeater.track_by_fn = track_expr;
    }
}
