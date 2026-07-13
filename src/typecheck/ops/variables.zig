/// TCB Ops Variables — Variable declaration TCB ops
///
/// Port of: compiler/src/typecheck/typecheck/ops/variables.ts (113 LoC)
const std = @import("std");

/// VariableOp — declare template variables in TCB scope.
pub fn declareVariable(allocator: std.mem.Allocator, name: []const u8, type_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "const {s}: {s} = null!;", .{ name, type_name });
}
