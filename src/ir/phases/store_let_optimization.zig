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
const helpers = @import("helpers.zig");
// ─── Shared helpers ──
const getExpressionPtrConst = helpers.getExpressionPtrConst;
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


// ─── Merged from remove_unused_store_lets.zig (1:1 structure consolidation) ──
pub fn removeUnusedStoreLets(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;
    const items = view.update.ops.items;

    // Pass 1: Collect all StoreLet variable names
    var store_let_names = std.StringHashMap(usize).init(allocator);
    defer store_let_names.deinit();

    for (items, 0..) |op, idx| {
        if (op.kind == .StoreLet) {
            const name = op.data.StoreLet.name;
            const entry = try store_let_names.getOrPut(name);
            if (!entry.found_existing) {
                entry.value_ptr.* = idx;
            }
        }
    }

    // Pass 2: Count ReadVariable usages for each StoreLet name
    var usage_count = std.StringHashMap(u32).init(allocator);
    defer usage_count.deinit();

    for (items) |op| {
        const expr = getExpressionPtrConst(op) orelse continue;
        if (expr.kind == .ReadVariable) {
            const name = expr.data.ReadVariable.name;
            if (store_let_names.contains(name)) {
                const entry = try usage_count.getOrPut(name);
                if (!entry.found_existing) {
                    entry.value_ptr.* = 0;
                }
                entry.value_ptr.* += 1;
            }
        }
    }

    // Pass 3: Remove StoreLet ops with 0 usages
    var write: usize = 0;
    for (items) |op| {
        if (op.kind == .StoreLet) {
            const name = op.data.StoreLet.name;
            const count = usage_count.get(name) orelse 0;
            if (count == 0) continue; // unused StoreLet — remove
        }
        items[write] = op;
        write += 1;
    }
    view.update.ops.items.len = write;
}
