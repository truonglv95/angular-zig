/// merge_adjacent_text phase
///
/// Port of: template/pipeline/src/phases/merge_adjacent_text.ts
///
/// Create phase — migrated from impl.zig
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
    _ = job;
    var write: usize = 0;
    var last_text_xref: ?u32 = null;
    const items = view.create.ops.items;

    for (items) |op| {
        if (op.kind == .Text and op.xref == last_text_xref) {
            // Same xref as previous Text — skip duplicate
            continue;
        }
        if (op.kind == .Text) {
            last_text_xref = op.xref;
        } else {
            last_text_xref = null;
        }
        items[write] = op;
        write += 1;
    }
    view.create.ops.items.len = write;
}
