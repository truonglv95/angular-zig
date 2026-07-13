/// TCB Ops Inputs — Input binding TCB operations
///
/// Port of: compiler/src/typecheck/typecheck/ops/inputs.ts (302 LoC)
const std = @import("std");

/// InputOp — type check input bindings on a directive.
pub fn checkInputBinding(allocator: std.mem.Allocator, input_name: []const u8, expr: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "({s} = {s})", .{ input_name, expr });
}
