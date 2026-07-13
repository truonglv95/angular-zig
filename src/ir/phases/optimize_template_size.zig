/// optimize_template_size phase
///
/// Port of: template/pipeline/src/phases/optimize_template_size.ts
///
/// Post phase — migrated from impl.zig
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
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;


pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    // In Full mode, strip SourceLocation ops to reduce template size.
    // In DomOnly mode, keep them for debugging.
    const strip = switch (job.mode) {
        .Full => true,
        .DomOnly => false,
    };

    if (!strip) return;

    var write: usize = 0;
    const items = view.create.ops.items;
    for (items) |op| {
        if (op.kind == .SourceLocation) continue;
        items[write] = op;
        write += 1;
    }
    view.create.ops.items.len = write;

    // Also strip from update ops
    write = 0;
    const update_items = view.update.ops.items;
    for (update_items) |op| {
        if (op.kind == .SourceLocation) continue;
        update_items[write] = op;
        write += 1;
    }
    view.update.ops.items.len = write;
}
