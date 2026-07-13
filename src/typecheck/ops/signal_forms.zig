/// TCB Ops Signal Forms — Signal unwrapping for TCB
///
/// Port of: compiler/src/typecheck/typecheck/ops/signal_forms.ts (496 LoC)
const std = @import("std");

/// SignalFormOp — unwrap signal calls in TCB expressions.
pub fn unwrapSignal(allocator: std.mem.Allocator, signal_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}()", .{signal_name});
}

/// Check if an expression is a signal (callable).
pub fn isSignal(expr: []const u8) bool {
    // TODO: check if expr references a signal property
    _ = expr;
    return false;
}
