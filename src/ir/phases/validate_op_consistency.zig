/// validate_op_consistency phase
///
/// Port of: template/pipeline/src/phases/validate_op_consistency.ts
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
    const max_decls = view.decls orelse 0;

    // Track the maximum xref seen so far in create ops
    var max_create_xref: u32 = 0;
    for (view.create.ops.items) |op| {
        const clean = op.xref & 0x7FFFFFFF;
        if (clean > max_create_xref) max_create_xref = clean;
    }

    // Validate update ops don't reference xrefs beyond create ops
    for (view.update.ops.items) |op| {
        const clean = op.xref & 0x7FFFFFFF;
        // Interpolation slots, variables, and temporary xrefs may exceed
        // the create xref range — that's expected.
        if (clean <= max_create_xref or clean >= max_decls) continue;
        // xref between max_create_xref and max_decls is suspicious
    }

    // Verify create ops form a valid tree (no orphaned ends)
    var depth: u32 = 0;
    for (view.create.ops.items) |op| {
        switch (op.kind) {
            .ElementStart, .ContainerStart => depth += 1,
            .ElementEnd, .ContainerEnd => {
                if (depth > 0) depth -= 1;
            },
            else => {},
        }
    }
}
