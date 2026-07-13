/// attribute_extraction phase
///
/// Port of: template/pipeline/src/phases/attribute_extraction.ts
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
    const items = view.create.ops.items;
    // Track (xref, name) pairs — use a simple scan-back for dedup
    // since attribute count per element is typically small (< 20).

    for (items) |op| {
        if (op.kind == .Attribute) {
            const attr_name = op.data.Attribute.name;
            // Scan back to check for duplicate
            var dup = false;
            var j: usize = 0;
            while (j < write) : (j += 1) {
                if (items[j].kind == .Attribute and
                    items[j].xref == op.xref and
                    std.mem.eql(u8, items[j].data.Attribute.name, attr_name))
                {
                    dup = true;
                    break;
                }
            }
            if (dup) continue;
        }
        items[write] = op;
        write += 1;
    }
    view.create.ops.items.len = write;
}
