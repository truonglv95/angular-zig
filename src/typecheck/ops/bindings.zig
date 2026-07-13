/// TCB Ops Bindings — Binding TCB operations
///
/// Port of: compiler/src/typecheck/typecheck/ops/bindings.ts (189 LoC)
const std = @import("std");

/// BindingOp — type check property bindings.
pub fn checkBinding(allocator: std.mem.Allocator, prop_name: []const u8, expr: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s} = {s}", .{ prop_name, expr });
}
