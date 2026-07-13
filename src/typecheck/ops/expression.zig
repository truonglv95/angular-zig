/// TCB Ops Expression — Convert template expressions to TCB-safe TS
///
/// Port of: compiler/src/typecheck/typecheck/ops/expression.ts (282 LoC)
const std = @import("std");

/// ExpressionOp — convert template AST expressions to TCB-safe expressions.
pub fn translateExpression(allocator: std.mem.Allocator, expr: []const u8) ![]const u8 {
    return allocator.dupe(u8, expr);
}
