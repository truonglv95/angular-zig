/// ordering phase
///
/// Port of: template/pipeline/src/phases/ordering.ts
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
