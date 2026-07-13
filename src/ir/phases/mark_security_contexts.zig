/// mark_security_contexts phase
///
/// Port of: template/pipeline/src/phases/mark_security_contexts.ts
///
/// Both phase — migrated from impl.zig
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

const schema = @import("../../schema/registry.zig");

// ─── Shared helpers ──
const injectSecurityContexts = resolve_sanitizers_mod.run;
const resolve_sanitizers_mod = @import("resolve_sanitizers.zig");
const SecurityContext = schema.SecurityContext;

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    return injectSecurityContexts(job, view);
}
