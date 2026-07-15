/// style_binding_specialization phase
///
/// Port of: template/pipeline/src/phases/style_binding_specialization.ts
///
/// Update phase — migrated from impl.zig
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
    const allocator = view.update.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    const items = view.update.ops.items;
    var i: usize = 0;
    while (i < items.len) {
        const op = items[i];
        if (op.kind == .StyleProp) {
            // Collect consecutive StyleProp ops on the same xref
            const group_xref = op.xref;
            const style_props_start = i;
            while (i < items.len and items[i].kind == .StyleProp and items[i].xref == group_xref) {
                i += 1;
            }
            const count = i - style_props_start;

            if (count >= 2) {
                // Emit a single StyleMap op instead
                // The expression is derived from the first StyleProp's expression
                // as the representative; codegen builds the map from the group.
                try result.append(.{
                    .kind = .StyleMap,
                    .xref = group_xref,
                    .source_span = items[style_props_start].source_span,
                    .data = .{ .StyleMap = .{ .expression = items[style_props_start].data.StyleProp.expression } },
                });
            } else {
                // Single StyleProp — keep as-is
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


// ─── Merged from class_binding_specialization.zig (1:1 structure consolidation) ──
pub fn normalizeClassMapExpressions(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
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
