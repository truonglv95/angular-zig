/// TCB Ops Element — Element node TCB operations
///
/// Port of: compiler/src/typecheck/typecheck/ops/element.ts (50 LoC)
const std = @import("std");

/// ElementOp — generate TCB for DOM elements.
pub fn generateElementCheck(allocator: std.mem.Allocator, tag: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "document.createElement('{s}')", .{tag});
}
