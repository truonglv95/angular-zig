/// empty_elements phase
///
/// Port of: template/pipeline/src/phases/empty_elements.ts
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
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;


pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    var write: usize = 0;
    const items = view.create.ops.items;
    // Track which xrefs have already had a Text op
    var seen_text_xref: [4096]bool = undefined;
    @memset(&seen_text_xref, false);

    for (items) |op| {
        if (op.kind == .Text) {
            if (op.xref < 4096) {
                if (seen_text_xref[op.xref]) {
                    // Duplicate Text on same xref — skip
                    continue;
                }
                seen_text_xref[op.xref] = true;
            }
        }
        items[write] = op;
        write += 1;
    }
    view.create.ops.items.len = write;
}
