/// TCB Ops Let — @let declaration TCB operations
///
/// Port of: compiler/src/typecheck/typecheck/ops/let.ts (44 LoC)
const std = @import("std");

/// LetOp — handle @let declarations in TCB.
pub fn declareLet(allocator: std.mem.Allocator, name: []const u8, expr: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "const {s} = {s};", .{ name, expr });
}
