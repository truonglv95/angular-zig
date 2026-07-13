/// pure_literal_structures phase
///
/// Port of: template/pipeline/src/phases/pure_literal_structures.ts
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
const getExpressionPtr = helpers.getExpressionPtr;
const helpers = @import("../helpers.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;


pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;
    const items = view.update.ops.items;

    for (items) |*op| {
        const expr = getExpressionPtr(op) orelse continue;
        try foldBinaryExpr(allocator, expr);
    }
}

/// Constant-fold simple binary expressions (e.g. 1 + 2 → 3).
fn foldBinaryExpr(allocator: std.mem.Allocator, expr: *IrExpr) !void {
    switch (expr.kind) {
        .BinaryExpr => {
            const bin = &expr.data.BinaryExpr;
            // Recurse into children first
            try foldBinaryExpr(allocator, bin.left);
            try foldBinaryExpr(allocator, bin.right);

            // Both must be LiteralExpr for folding
            if (bin.left.kind != .LiteralExpr or bin.right.kind != .LiteralExpr) return;

            const left_val = bin.left.data.LiteralExpr.value;
            const right_val = bin.right.data.LiteralExpr.value;
            const op_char = bin.op;

            // Only fold simple numeric literals
            const left_num = std.fmt.parseInt(i64, left_val, 10) catch return;
            const right_num = std.fmt.parseInt(i64, right_val, 10) catch return;

            const result_num: i64 = switch (op_char) {
                '+' => left_num + right_num,
                '-' => left_num - right_num,
                '*' => left_num * right_num,
                else => return,
            };

            // Build result literal string
            const result_str = try std.fmt.allocPrint(allocator, "{d}", .{result_num});
            const folded = try allocator.create(IrExpr);
            folded.* = .{
                .kind = .LiteralExpr,
                .span = expr.span,
                .data = .{ .LiteralExpr = .{ .value = result_str } },
            };
            expr.* = folded.*;
        },
        else => {},
    }
}
