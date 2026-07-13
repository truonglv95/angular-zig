/// defer_configs phase
///
/// Port of: template/pipeline/src/phases/defer_configs.ts
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
    var i: usize = 0;
    while (i < items.len) {
        const op = items[i];
        try result.append(op);

        if (op.kind == .Defer) {
            // Check if next op is DeferOn or DeferWhen
            const has_trigger = if (i + 1 < items.len)
                items[i + 1].kind == .DeferOn or items[i + 1].kind == .DeferWhen
            else
                false;

            if (!has_trigger) {
                // Insert default DeferOn(.Idle)
                try result.append(.{
                    .kind = .DeferOn,
                    .xref = op.xref,
                    .source_span = op.source_span,
                    .data = .{ .DeferOn = .Idle },
                });
            }
        }

        i += 1;
    }

    view.create.ops.deinit();
    view.create.ops = result;
}
