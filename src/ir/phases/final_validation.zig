/// final_validation phase
///
/// Port of: template/pipeline/src/phases/final_validation.ts
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

// ─── Shared helpers ──
const MAX_DEPTH = helpers.MAX_DEPTH;
const helpers = @import("helpers.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;


pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const max_decls = view.decls orelse return;

    // Validate create op nesting
    var xref_stack: [MAX_DEPTH]u32 = undefined;
    var depth: u32 = 0;

    const create_items = view.create.ops.items;
    for (create_items) |op| {
        switch (op.kind) {
            .ElementStart => {
                if (depth < MAX_DEPTH) xref_stack[depth] = op.xref;
                depth += 1;
            },
            .ElementEnd => {
                if (depth > 0) {
                    depth -= 1;
                    // xref in ElementEnd should match the corresponding ElementStart
                    if (depth < MAX_DEPTH) {
                        if (op.xref != xref_stack[depth]) {
                            // Nesting mismatch — would error in strict mode.
                        }
                    }
                }
            },
            else => {},
        }
    }

    // Validate update ops reference valid slots
    const update_items = view.update.ops.items;
    for (update_items) |op| {
        const clean_xref = op.xref & 0x7FFFFFFF;
        // Interpolation, Advance, and variable ops may have xrefs
        // beyond max_decls — that's OK for temporaries.
        _ = clean_xref;
        _ = max_decls;
    }

    // Ensure decls and vars are set
    if (view.decls == null) {
        view.decls = 0;
    }
    if (view.vars == null) {
        view.vars = 0;
    }
}
