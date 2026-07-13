/// remove_empty_icu_blocks phase
///
/// Port of: template/pipeline/src/phases/remove_empty_icu_blocks.ts
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
    const allocator = view.create.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    const items = view.create.ops.items;
    // Collect xrefs of I18nExpression ops that have no expressions
    var empty_icu_xrefs: [MAX_DEPTH]bool = undefined;
    @memset(&empty_icu_xrefs, false);
    var empty_icu_count: usize = 0;

    for (view.update.ops.items) |op| {
        if (op.kind == .I18nExpression and op.data.I18nExpression.expressions.len == 0) {
            const clean = op.xref & 0x7FFFFFFF;
            if (clean < MAX_DEPTH) {
                empty_icu_xrefs[clean] = true;
                empty_icu_count += 1;
            }
        }
    }

    // If no empty ICU blocks, nothing to do
    if (empty_icu_count == 0) {
        return;
    }

    var skip_depth: u32 = 0;
    for (items) |op| {
        if (skip_depth > 0) {
            if (op.kind == .I18nStart) skip_depth += 1;
            if (op.kind == .I18nEnd) {
                skip_depth -= 1;
                continue; // skip the I18nEnd itself
            }
            continue; // skip everything inside the empty block
        }
        if (op.kind == .I18nStart) {
            const clean = op.xref & 0x7FFFFFFF;
            if (clean < MAX_DEPTH and empty_icu_xrefs[clean]) {
                skip_depth = 1;
                continue;
            }
        }
        try result.append(op);
    }

    view.create.ops.deinit();
    view.create.ops = result;
}
