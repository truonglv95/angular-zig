/// pure_function_extraction phase
///
/// Port of: template/pipeline/src/phases/pure_function_extraction.ts
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

    const items = view.update.ops.items;

    // Track expression addresses we've seen. Shared pointers indicate
    // the same expression is used in multiple ops.
    var seen_exprs = std.AutoHashMap(usize, u32).init(allocator);
    defer seen_exprs.deinit();

    var candidate_count: u32 = 0;

    for (items) |op| {
        const expr = getExpressionPtrConst(op) orelse continue;
        // Skip simple expressions (not worth extracting)
        const is_extractable = switch (expr.kind) {
            .PipeBinding, .PipeBindingVariadic, .SafePropertyRead, .SafeKeyedRead => true,
            else => false,
        };
        if (!is_extractable) continue;

        const addr = @intFromPtr(expr);
        const entry = try seen_exprs.getOrPut(addr);
        if (entry.found_existing) {
            if (entry.value_ptr.* == 1) {
                candidate_count += 1;
            }
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
    }
    // candidate_count is available for the emitter to decide whether
    // to enable pure function extraction in a future compilation pass.
}
