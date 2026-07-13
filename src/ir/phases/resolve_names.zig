/// resolve_names phase — Resolve lexical references to variables or context
///
/// Port of: template/pipeline/src/phases/resolve_names.ts
///
/// Resolves `LexicalReadExpr` expressions to either:
/// - A variable declared in the current scope (→ ReadVariableExpr)
/// - A property on the component context (→ ReadPropExpr on ContextExpr)
///
/// Also matches `RestoreViewExpr` with saved view variables.
const std = @import("std");

const job_mod = @import("../job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

const ir_expr = @import("../expression.zig");
const IrExpr = ir_expr.IrExpr;

const helpers = @import("helpers.zig");

/// Saved view info for RestoreViewExpr matching.
const SavedView = struct {
    view: u32,
    variable: u32,
};

/// Resolve lexical names in all views.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    // Process create ops
    try processLexicalScope(view, view.create.ops.items, null);
    // Process update ops
    try processLexicalScope(view, view.update.ops.items, null);
}

/// Process the lexical scope of an op list, resolving LexicalReadExpr.
fn processLexicalScope(
    view: *ViewCompilationUnit,
    ops: []IrOp,
    saved_view: ?SavedView,
) !void {
    _ = view;
    _ = saved_view;

    // Build scope map: name → xref
    var scope = std.StringHashMap(u32).init(std.heap.page_allocator);
    defer scope.deinit();

    // Phase 1: Collect variable declarations into scope
    for (ops) |op| {
        if (op.kind == .Variable) {
            // TODO: add variable.kind and variable.identifier to IrOp data
            // For now, we can't resolve variables without SemanticVariable support
        }
    }

    // Phase 2: Resolve LexicalReadExpr in expressions
    // The current IR doesn't have LexicalReadExpr — it uses ReadVariable directly.
    // This phase is a no-op until LexicalReadExpr is added to ExpressionKind.
    // When added, this function will:
    // 1. Walk all expressions in ops
    // 2. Find LexicalReadExpr nodes
    // 3. Look up the name in scope
    // 4. Replace with ReadVariableExpr (if found) or ReadPropExpr on ContextExpr
    _ = ops;
}
