/// class_binding_specialization phase
///
/// Port of: template/pipeline/src/phases/class_binding_specialization.ts
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
    const allocator = view.update.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    const items = view.update.ops.items;
    var i: usize = 0;
    while (i < items.len) {
        const op = items[i];
        if (op.kind == .ClassProp) {
            const group_xref = op.xref;
            const class_props_start = i;
            while (i < items.len and items[i].kind == .ClassProp and items[i].xref == group_xref) {
                i += 1;
            }
            const count = i - class_props_start;

            if (count >= 2) {
                // Emit a single ClassMap op
                try result.append(.{
                    .kind = .ClassMap,
                    .xref = group_xref,
                    .source_span = items[class_props_start].source_span,
                    .data = .{ .ClassMap = .{ .expression = items[class_props_start].data.ClassProp.expression } },
                });
            } else {
                try result.append(op);
            }
        } else {
            try result.append(op);
            i += 1;
        }
    }

    view.update.ops.deinit();
    view.update.ops = result;
}
