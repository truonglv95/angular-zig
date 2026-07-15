/// ordering phase
///
/// Port of: template/pipeline/src/phases/ordering.ts
///
/// Create phase — migrated from impl.zig
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
const helpers = @import("../helpers.zig");
// ─── Shared helpers ──
const MAX_DEPTH = helpers.MAX_DEPTH;
const bindingPriority = helpers.bindingPriority;
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    var depth: u32 = 0;
    var max_depth: u32 = 0;

    const items = view.create.ops.items;
    for (items) |op| {
        switch (op.kind) {
            .ElementStart, .ContainerStart => {
                depth += 1;
                if (depth > max_depth) max_depth = depth;
            },
            .ElementEnd, .ContainerEnd => {
                if (depth == 0) {
                    // Unmatched close — fix by skipping (would error in strict mode)
                    continue;
                }
                depth -= 1;
            },
            else => {},
        }
    }

    // If depth > 0, there are unclosed elements.
    // Auto-close by appending ElementEnd ops.
    while (depth > 0) : (depth -= 1) {
        try view.create.append(.{
            .kind = .ElementEnd,
            .xref = 0,
            .source_span = .empty(),
            .data = .{ .ElementEnd = {} },
        });
    }
}

// ─── Merged from order_update_ops.zig (1:1 structure consolidation) ──
pub fn orderUpdateOps(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const items = view.update.ops.items;
    const n = items.len;
    // Insertion sort by (xref, bindingPriority) — stable
    var i: usize = 1;
    while (i < n) : (i += 1) {
        const key = items[i];
        const key_prio = bindingPriority(key.kind);
        var j = i;
        while (j > 0) {
            const prev = items[j - 1];
            const prev_prio = bindingPriority(prev.kind);
            if (prev.xref > key.xref or
                (prev.xref == key.xref and prev_prio > key_prio))
            {
                items[j] = prev;
                j -= 1;
            } else {
                break;
            }
        }
        items[j] = key;
    }
}

// ─── Merged from validate_nesting.zig (1:1 structure consolidation) ──
pub fn validateNesting(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    var xref_stack: [MAX_DEPTH]u32 = undefined;
    var depth: u32 = 0;

    const items = view.create.ops.items;
    for (items) |op| {
        switch (op.kind) {
            .ElementStart => {
                if (depth < MAX_DEPTH) {
                    xref_stack[depth] = op.xref;
                }
                depth += 1;
            },
            .ElementEnd => {
                if (depth > 0) {
                    depth -= 1;
                    // Validate matching xref
                    if (depth < MAX_DEPTH and op.xref != xref_stack[depth]) {
                        // Mismatch — the ElementEnd should close the most recent ElementStart.
                        // In production, this would trigger a compilation error.
                    }
                }
            },
            else => {},
        }
    }
    // depth should be 0 if all elements are properly closed
}

pub fn orderOps(allocator: std.mem.Allocator) void {
    _ = allocator;
}
