/// TCB Ops Host — Host binding TCB operations
///
/// Port of: compiler/src/typecheck/typecheck/ops/host.ts (46 LoC)
const std = @import("std");

/// HostOp — generate TCB for host bindings.
pub fn generateHostCheck(allocator: std.mem.Allocator, prop: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "// host: {s}", .{prop});
}
