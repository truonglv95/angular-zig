/// TCB Ops For Block — @for block TCB operations
///
/// Port of: compiler/src/typecheck/typecheck/ops/for_block.ts (108 LoC)
const std = @import("std");

/// ForBlockOp — generate TCB for @for blocks.
pub fn generateForCheck(allocator: std.mem.Allocator, item_name: []const u8, iterable: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "for (const {s} of {s}) {{ }}", .{ item_name, iterable });
}
