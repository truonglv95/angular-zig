/// variable_optimization phase
///
/// Port of: template/pipeline/src/phases/variable_optimization.ts
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
const getVariableName = helpers.getVariableName;
const getExpressionPtrConst = helpers.getExpressionPtrConst;
const helpers = @import("../helpers.zig");
const getExpressionPtr = helpers.getExpressionPtr;
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


// ─── Merged from inline_simple_variables.zig (1:1 structure consolidation) ──
pub fn inlineSimpleVariables(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;
    const items = view.update.ops.items;

    // Pass 1: Count usages of each Variable
    var var_usage = std.StringHashMap(struct {
        decl_idx: usize,
        usage_count: u32,
        value: *IrExpr,
    }).init(allocator);
    defer var_usage.deinit();

    for (items, 0..) |op, idx| {
        const name = getVariableName(op) orelse continue;
        if (op.kind != .Variable) continue;
        const entry = try var_usage.getOrPut(name);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{ .decl_idx = idx, .usage_count = 0, .value = op.data.Variable.value };
        }
    }

    // Count ReadVariable usages
    for (items) |op| {
        const expr = getExpressionPtrConst(op) orelse continue;
        if (expr.kind == .ReadVariable) {
            const name = expr.data.ReadVariable.name;
            if (var_usage.getPtr(name)) |info| {
                info.usage_count += 1;
            }
        }
    }

    // Pass 2: For single-use variables, replace the usage expression
    // and remove the Variable declaration
    var inline_names = std.StringHashMap(void).init(allocator);
    defer inline_names.deinit();

    var var_it = var_usage.iterator();
    while (var_it.next()) |entry| {
        if (entry.value_ptr.usage_count == 1) {
            try inline_names.put(entry.key_ptr.*, {});
        }
    }

    // Replace ReadVariable references with the inlined value
    for (items) |*op| {
        const expr = getExpressionPtr(op) orelse continue;
        if (expr.kind == .ReadVariable) {
            const name = expr.data.ReadVariable.name;
            if (inline_names.contains(name)) {
                if (var_usage.get(name)) |info| {
                    expr.* = info.value.*;
                }
            }
        }
    }

    // Remove the inlined Variable ops
    var write: usize = 0;
    for (items) |op| {
        const name = getVariableName(op) orelse {
            items[write] = op;
            write += 1;
            continue;
        };
        if (op.kind == .Variable and inline_names.contains(name)) {
            continue; // remove inlined variable
        }
        items[write] = op;
        write += 1;
    }
    view.update.ops.items.len = write;
}

pub fn optimizeVariables(allocator: std.mem.Allocator) void { _ = allocator; }