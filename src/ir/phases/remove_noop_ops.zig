/// remove_noop_ops phase
///
/// Port of: template/pipeline/src/phases/remove_noop_ops.ts
///
/// Post phase — migrated from impl.zig
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

    // Process create ops
    {
        var write: usize = 0;
        var disable_depth: u32 = 0;
        const items = view.create.ops.items;
        for (items) |op| {
            var skip = false;
            switch (op.kind) {
                .SourceLocation => skip = true, // metadata only
                .Statement => skip = op.data.Statement.len == 0,
                .DisableBindings => {
                    disable_depth += 1;
                },
                .EnableBindings => {
                    if (disable_depth > 0) {
                        disable_depth -= 1;
                    }
                },
                else => {},
            }
            if (!skip) {
                items[write] = op;
                write += 1;
            }
        }
        view.create.ops.items.len = write;
    }

    // Process update ops
    {
        var write: usize = 0;
        const items = view.update.ops.items;
        for (items) |op| {
            var skip = false;
            switch (op.kind) {
                .Advance => skip = op.data.Advance == 0,
                .SourceLocation => skip = true,
                else => {},
            }
            if (!skip) {
                items[write] = op;
                write += 1;
            }
        }
        view.update.ops.items.len = write;
    }
}
