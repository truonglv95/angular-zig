/// transform_two_way_binding_set phase
///
/// Port of: template/pipeline/src/phases/transform_two_way_binding_set.ts
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
    const allocator = view.update.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    const items = view.update.ops.items;
    for (items) |op| {
        try result.append(op);

        if (op.kind == .TwoWayProperty) {
            const prop = op.data.TwoWayProperty;
            // Allocate a handler function xref for the write-back listener
            const handler_xref = job.slots.allocXref();
            // Emit TwoWayListener: listens for "nameChange" and writes back
            try result.append(.{
                .kind = .TwoWayListener,
                .xref = op.xref,
                .source_span = op.source_span,
                .data = .{ .TwoWayListener = .{
                    .name = prop.name,
                    .handler_fn_xref = handler_xref,
                } },
            });
        }
    }

    view.update.ops.deinit();
    view.update.ops = result;
}
