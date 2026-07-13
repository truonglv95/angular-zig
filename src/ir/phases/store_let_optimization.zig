/// store_let_optimization phase
///
/// Port of: template/pipeline/src/phases/store_let_optimization.ts
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
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;


pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    const items = view.update.ops.items;

    // Pass 1: all StoreLet ops first
    for (items) |op| {
        if (op.kind == .StoreLet) {
            try result.append(op);
        }
    }
    // Pass 2: all other ops
    for (items) |op| {
        if (op.kind != .StoreLet) {
            try result.append(op);
        }
    }

    view.update.ops.deinit();
    view.update.ops = result;
}
