/// TCB Ops Selectorless — Selectorless component TCB ops
///
/// Port of: compiler/src/typecheck/typecheck/ops/selectorless.ts (47 LoC)
const std = @import("std");

/// SelectorlessOp — handle selectorless component matching in TCB.
pub fn checkSelectorlessMatch(allocator: std.mem.Allocator, type_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "({s})", .{type_name});
}
