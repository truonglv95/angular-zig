/// order_update_ops phase
///
/// Port of: template/pipeline/src/phases/order_update_ops.ts
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
const bindingPriority = helpers.bindingPriority;
const helpers = @import("helpers.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;


pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
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
