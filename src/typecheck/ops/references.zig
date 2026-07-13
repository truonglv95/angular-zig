/// TCB Ops References — Template reference variable TCB ops
///
/// Port of: compiler/src/typecheck/typecheck/ops/references.ts (124 LoC)
const std = @import("std");

/// ReferenceOp — resolve template reference variables in TCB.
pub fn resolveReference(allocator: std.mem.Allocator, ref_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "_ref_{s}", .{ref_name});
}
