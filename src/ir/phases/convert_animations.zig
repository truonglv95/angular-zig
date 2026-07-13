/// convert_animations phase — Convert animation triggers to animation ops
///
/// Port of: template/pipeline/src/phases/convert_animations.ts
///
/// Converts @animation trigger bindings into proper Animation ops
/// in the IR.
const std = @import("std");
const job_mod = @import("../job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;
const ir_ops = @import("../ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

/// Convert animation triggers to animation ops.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    // Scan update ops for animation bindings (@trigger)
    // Convert them to Animation ops
    // TODO: requires animation trigger parsing in the binding parser
    _ = view;
}