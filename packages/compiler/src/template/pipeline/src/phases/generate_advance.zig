/// generate_advance phase
///
/// Port of: template/pipeline/src/phases/generate_advance.ts
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
    const allocator = view.create.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    const items = view.create.ops.items;
    var depth: u32 = 0;
    // Track the last ElementEnd's (xref, depth_after_pop)
    var last_end_xref: ?u32 = null;
    var last_end_depth: u32 = 0;

    for (items) |op| {
        switch (op.kind) {
            .ElementStart => {
                // Sibling check: last ElementEnd was at the same depth
                if (last_end_xref != null and last_end_depth == depth) {
                    const delta = op.xref -| last_end_xref.?;
                    if (delta > 0) {
                        try result.append(.{
                            .kind = .Advance,
                            .xref = op.xref,
                            .source_span = op.source_span,
                            .data = .{ .Advance = delta },
                        });
                    }
                }
                depth += 1;
                last_end_xref = null;
                try result.append(op);
            },
            .ElementEnd => {
                if (depth > 0) depth -= 1;
                try result.append(op);
                last_end_xref = op.xref;
                last_end_depth = depth;
            },
            .ContainerStart => {
                depth += 1;
                // Container transitions don't trigger advances
                last_end_xref = null;
                try result.append(op);
            },
            .ContainerEnd => {
                if (depth > 0) depth -= 1;
                try result.append(op);
                last_end_xref = null;
            },
            else => {
                // Non-element ops between siblings don't clear the advance tracking
                try result.append(op);
            },
        }
    }

    view.create.ops.deinit();
    view.create.ops = result;
}
