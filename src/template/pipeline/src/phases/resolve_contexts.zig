/// resolve_contexts phase
///
/// Port of: template/pipeline/src/phases/resolve_contexts.ts
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

    // Pass 1: Collect locally declared variable names
    var local_vars = std.StringHashMap(void).init(allocator);
    defer local_vars.deinit();

    const items = view.update.ops.items;
    for (items) |op| {
        if (op.kind == .StoreLet) {
            try local_vars.put(op.data.StoreLet.name, {});
        } else if (op.kind == .Variable) {
            try local_vars.put(op.data.Variable.name, {});
        }
    }

    // Also add context variables (from parent) as "known" — they DON'T need
    // NextContext because they're already passed via the context chain.
    var ctx_it = view.context_variables.iterator();
    while (ctx_it.next()) |entry| {
        try local_vars.put(entry.key_ptr.*, {});
    }

    // Pass 2: For ops referencing unknown variables, encode context navigation.
    // We set bit 31 of xref to indicate "needs context resolution."
    // The emitter interprets this as emitting a NextContext(0) before the binding.
    const CONTEXT_NEEDED: u32 = 0x80000000;

    for (items) |*op| {
        const expr = getExpressionPtr(op) orelse continue;
        if (expr.kind == .ReadVariable) {
            const var_name = expr.data.ReadVariable.name;
            // If the variable isn't locally declared, it needs context navigation
            if (!local_vars.contains(var_name)) {
                // Mark this op as needing context resolution
                op.xref = op.xref | CONTEXT_NEEDED;
            }
        }
    }
}
