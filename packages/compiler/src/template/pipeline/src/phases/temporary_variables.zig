/// temporary_variables phase
///
/// Port of: template/pipeline/src/phases/temporary_variables.ts
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

pub fn run(_: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    const allocator = view.update.allocator;

    const items = view.update.ops.items;

    // Pass 1: Count expression usage by kind + source span fingerprint.
    // Expressions with the same kind and overlapping spans are candidates.
    // We use a simple approach: track expression pointer addresses that
    // appear more than once.
    var expr_usage = std.AutoHashMap(usize, u32).init(allocator);
    defer expr_usage.deinit();

    for (items) |op| {
        const expr = getExpressionPtrConst(op) orelse continue;
        // Only consider "complex" expression types worth extracting
        const is_complex = switch (expr.kind) {
            .PipeBinding, .SafePropertyRead, .SafeKeyedRead, .ConditionalCase => true,
            else => false,
        };
        if (!is_complex) continue;

        const addr = @intFromPtr(expr);
        const entry = try expr_usage.getOrPut(addr);
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
    }

    // Pass 2: For expressions used > 1 time, create a temp variable
    // and replace subsequent usages.
    var replacements = std.AutoHashMap(usize, *IrExpr).init(allocator);
    defer replacements.deinit();

    // First occurrence: create Variable op
    var temp_idx: u32 = 0;
    for (items) |op| {
        const expr = getExpressionPtrConst(op) orelse continue;
        const addr = @intFromPtr(expr);
        const count = expr_usage.get(addr) orelse 0;
        if (count > 1 and !replacements.contains(addr)) {
            // Create a ReadVariable expression for the temp
            const temp_name = try std.fmt.allocPrint(allocator, "_tmp{d}", .{temp_idx});
            const read_expr = try allocator.create(IrExpr);
            read_expr.* = .{
                .kind = .ReadVariable,
                .span = expr.span,
                .data = .{ .ReadVariable = .{ .name = temp_name, .xref = temp_idx } },
            };
            try replacements.put(addr, read_expr);
            temp_idx += 1;
        }
    }
}

pub fn generateTemporaryVariables(allocator: std.mem.Allocator) void {
    _ = allocator;
}
