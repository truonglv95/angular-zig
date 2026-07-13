/// variable_optimization phase
///
/// Port of: template/pipeline/src/phases/variable_optimization.ts
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
const getVariableName = helpers.getVariableName;
const getExpressionPtrConst = helpers.getExpressionPtrConst;
const helpers = @import("helpers.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;


pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;

    const items = view.update.ops.items;

    // Pass 1: Collect all declared variable names
    var var_info = std.StringHashMap(struct {
        decl_idx: usize,
        usage_count: u32,
    }).init(allocator);
    defer var_info.deinit();

    for (items, 0..) |op, idx| {
        const name = getVariableName(op) orelse continue;
        const entry = try var_info.getOrPut(name);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{ .decl_idx = idx, .usage_count = 0 };
        }
    }

    // Pass 2: Count usages (ReadVariable expressions)
    for (items) |op| {
        const expr = getExpressionPtrConst(op) orelse continue;
        if (expr.kind == .ReadVariable) {
            const name = expr.data.ReadVariable.name;
            if (var_info.getPtr(name)) |info| {
                info.usage_count += 1;
            }
        }
    }

    // Pass 3: Remove unused variables
    var write: usize = 0;
    for (items) |op| {
        const name = getVariableName(op) orelse {
            items[write] = op;
            write += 1;
            continue;
        };
        if (var_info.get(name)) |info| {
            if (info.usage_count == 0) {
                // Unused variable — remove
                continue;
            }
            // Used variable — keep (single-use inlining would require
            // replacing the usage expression, which is a pointer swap)
        }
        items[write] = op;
        write += 1;
    }
    view.update.ops.items.len = write;
}
