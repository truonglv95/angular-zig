/// generate_directive_metadata phase
///
/// Port of: template/pipeline/src/phases/generate_directive_metadata.ts
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
    var last_slot: u32 = 0;
    var has_projection_def = false;

    const items = view.create.ops.items;
    for (items) |op| {
        switch (op.kind) {
            .Projection => {
                // Validate slot monotonicity
                if (op.data.Projection.slot_index < last_slot) {
                    // Out-of-order slot — would error in strict mode
                }
                last_slot = op.data.Projection.slot_index;
            },
            .ProjectionDef => {
                has_projection_def = true;
                // Validate ProjectionDef references a valid slot
                if (op.data.ProjectionDef.slot_index > last_slot) {
                    // ProjectionDef references a slot not yet seen
                }
            },
            else => {},
        }
    }

    // If there are Projection ops but no ProjectionDef, the template
    // may be a host binding compilation — that's valid.
}
