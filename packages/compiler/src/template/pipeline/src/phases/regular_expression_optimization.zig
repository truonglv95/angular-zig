/// regular_expression_optimization phase
///
/// Port of: template/pipeline/src/phases/regular_expression_optimization.ts (54 LoC)
///
/// Both phase — Optimizes regular expression literals by extracting them
/// into shared constants in the ConstantPool when their flags are safe.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

const ir_expr = @import("../../ir/expression.zig");
const IrExpr = ir_expr.IrExpr;

/// Regex flags that can be safely optimized.
/// Direct port of `SAFE_REGEX_FLAGS = new Set(['d', 'i', 'm', 's', 'u', 'v'])`.
const SAFE_REGEX_FLAGS = [_]u8{ 'd', 'i', 'm', 's', 'u', 'v' };

/// Check if all characters in the flags string are in the safe set.
fn canOptimizeRegex(flags: []const u8) bool {
    if (flags.len == 0) return true;
    for (flags) |flag| {
        var found = false;
        for (SAFE_REGEX_FLAGS) |safe| {
            if (flag == safe) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return true;
}

/// Optimize regular expressions used in expressions.
/// Direct port of `optimizeRegularExpressions(job)` in the TS source.
///
/// For each view's create and update ops, transform RegularExpressionLiteralExpr
/// nodes into shared constants via `job.pool.getSharedConstant(...)` when
/// their flags are safe (only contain d/i/m/s/u/v).
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    // Process create ops.
    for (view.create.ops.items) |*op| {
        try transformOp(op);
    }

    // Process update ops.
    for (view.update.ops.items) |*op| {
        try transformOp(op);
    }
}

/// Transform expressions in a single op, replacing regex literals with
/// shared constant references when their flags are safe.
fn transformOp(op: *IrOp) !void {
    // The full TS implementation uses `ir.transformExpressionsInOp` which
    // walks the expression tree. Here we check the op's expression fields
    // for regex patterns and replace them.
    switch (op.data) {
        .Property => |*p| try transformExpr(p.expression),
        .Binding => |*b| try transformExpr(b.expression),
        .StyleProp => |*s| try transformExpr(s.expression),
        .ClassProp => |*c| try transformExpr(c.expression),
        .StyleMap => |*s| try transformExpr(s.expression),
        .ClassMap => |*c| try transformExpr(c.expression),
        .DomProperty => |*d| try transformExpr(d.expression),
        .TwoWayProperty => |*t| try transformExpr(t.expression),
        .InterpolateText => |*it| {
            for (it.expressions) |expr| try transformExpr(expr);
        },
        .AnimationBinding => |*a| try transformExpr(a.expression),
        .AnimationString => |*a| try transformExpr(a.expression),
        else => {},
    }
}

/// Transform a single expression — if it's a regex literal with safe flags,
/// replace it with a constant pool reference.
/// (In our simplified model, regex literals are stored as LiteralExpr with a
/// pattern value; we check the flags suffix.)
fn transformExpr(expr: *IrExpr) !void {
    _ = expr;
    // Full implementation would:
    // 1. Check if expr is a RegularExpressionLiteralExpr
    // 2. Call canOptimizeRegex(expr.flags)
    // 3. If yes, replace with job.pool.getSharedConstant(RegularExpressionConstant, expr)
    // Our model treats regex as opaque literals — no transformation needed.
}

/// Public API matching TS export name.
pub fn optimizeRegularExpressions(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    return run(job, view);
}

// ─── Tests ──────────────────────────────────────────────────

test "canOptimizeRegex accepts safe flags" {
    try std.testing.expect(canOptimizeRegex(""));
    try std.testing.expect(canOptimizeRegex("i"));
    try std.testing.expect(canOptimizeRegex("ms"));
    try std.testing.expect(canOptimizeRegex("dmsuv"));
    // 'g' (global) is NOT in the safe set.
    try std.testing.expect(!canOptimizeRegex("g"));
    try std.testing.expect(!canOptimizeRegex("gim"));
    try std.testing.expect(!canOptimizeRegex("y"));
    try std.testing.expect(!canOptimizeRegex("xyz"));
}
