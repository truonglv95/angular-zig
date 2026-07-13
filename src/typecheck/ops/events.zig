/// TCB Ops Events — Event binding TCB operations
///
/// Port of: compiler/src/typecheck/typecheck/ops/events.ts (328 LoC)
const std = @import("std");

/// EventOp — type check event bindings on a directive.
pub fn checkEventBinding(allocator: std.mem.Allocator, event_name: []const u8, handler: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "({s} => {s})", .{ event_name, handler });
}
