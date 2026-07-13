/// TCB Ops If Block — @if block TCB operations
///
/// Port of: compiler/src/typecheck/typecheck/ops/if_block.ts (137 LoC)
const std = @import("std");

/// IfBlockOp — generate TCB for @if blocks.
pub fn generateIfCheck(allocator: std.mem.Allocator, condition: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "if ({s}) {{ }}", .{condition});
}
