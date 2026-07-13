/// next_context_merging phase
///
/// Port of: template/pipeline/src/phases/next_context_merging.ts
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
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;


pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    var write: usize = 0;
    const items = view.update.ops.items;
    var i: usize = 0;

    while (i < items.len) {
        if (items[i].kind == .Advance) {
            // Merge consecutive Advance ops
            var total: u32 = items[i].data.Advance;
            var j = i + 1;
            while (j < items.len and items[j].kind == .Advance) : (j += 1) {
                total +|= items[j].data.Advance; // saturating add
            }
            // Only emit if total > 0
            if (total > 0) {
                items[write] = items[i];
                items[write].data = .{ .Advance = total };
                write += 1;
            }
            i = j;
        } else {
            items[write] = items[i];
            write += 1;
            i += 1;
        }
    }

    view.update.ops.items.len = write;
}
