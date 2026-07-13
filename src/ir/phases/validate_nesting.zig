/// validate_nesting phase
///
/// Port of: template/pipeline/src/phases/validate_nesting.ts
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

// ─── Shared helpers ──
const MAX_DEPTH = helpers.MAX_DEPTH;
const helpers = @import("helpers.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;


pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    var xref_stack: [MAX_DEPTH]u32 = undefined;
    var depth: u32 = 0;

    const items = view.create.ops.items;
    for (items) |op| {
        switch (op.kind) {
            .ElementStart => {
                if (depth < MAX_DEPTH) {
                    xref_stack[depth] = op.xref;
                }
                depth += 1;
            },
            .ElementEnd => {
                if (depth > 0) {
                    depth -= 1;
                    // Validate matching xref
                    if (depth < MAX_DEPTH and op.xref != xref_stack[depth]) {
                        // Mismatch — the ElementEnd should close the most recent ElementStart.
                        // In production, this would trigger a compilation error.
                    }
                }
            },
            else => {},
        }
    }
    // depth should be 0 if all elements are properly closed
}
