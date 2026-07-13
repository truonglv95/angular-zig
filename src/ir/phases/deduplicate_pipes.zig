/// deduplicate_pipes phase
///
/// Port of: template/pipeline/src/phases/deduplicate_pipes.ts
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
    // Track (xref, name) pairs seen so far
    var seen_xref: [4096]?[]const u8 = @splat(null);

    for (items) |op| {
        if (op.kind == .Pipe) {
            const clean_xref = op.xref & 0x7FFFFFFF;
            const pipe_name = op.data.Pipe.name;
            if (clean_xref < 4096) {
                if (seen_xref[clean_xref]) |prev_name| {
                    if (std.mem.eql(u8, prev_name, pipe_name)) {
                        // Duplicate pipe — skip
                        continue;
                    }
                }
                seen_xref[clean_xref] = pipe_name;
            }
        }
        items[write] = op;
        write += 1;
    }
    view.update.ops.items.len = write;
}
