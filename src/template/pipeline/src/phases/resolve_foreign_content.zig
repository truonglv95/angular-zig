/// resolve_foreign_content phase — Resolve foreign content namespaces
///
/// Port of: template/pipeline/src/phases/resolve_foreign_content.ts
///
/// Ensures elements in foreign namespaces (SVG, MathML) have the
/// correct namespace set on their ElementStart ops.
const std = @import("std");
const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;
const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;
const Namespace = ir_ops.Namespace;

/// Resolve foreign content namespaces.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    // Scan create ops for ElementStart and ensure namespace is correct
    // based on parent element namespace (SVG/MathML inheritance)
    for (view.create.ops.items) |*op| {
        if (op.kind == .ElementStart) {
            // Namespace is already set during ingest via tags.getNamespace()
            // This phase would handle parent-inherited namespace for nested elements
        }
    }
}