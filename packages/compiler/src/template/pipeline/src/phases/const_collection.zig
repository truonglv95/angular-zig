/// const_collection phase
///
/// Port of: template/pipeline/src/phases/const_collection.ts
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

// ─── Shared helpers ──
const getExpressionPtrConst = helpers.getExpressionPtrConst;
const helpers = @import("../helpers.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    const items = view.update.ops.items;

    // Pass 1: ops with constant expressions
    for (items) |op| {
        const expr = getExpressionPtrConst(op) orelse {
            continue;
        };
        if (expr.kind == .ConstCollected or expr.kind == .LiteralExpr) {
            try result.append(op);
        }
    }
    // Pass 2: all other ops (stable order)
    for (items) |op| {
        const expr = getExpressionPtrConst(op) orelse {
            try result.append(op);
            continue;
        };
        if (expr.kind != .ConstCollected and expr.kind != .LiteralExpr) {
            try result.append(op);
        }
    }

    view.update.ops.deinit();
    view.update.ops = result;
}

pub fn collectElementConsts(allocator: std.mem.Allocator) void {
    _ = allocator;
}
