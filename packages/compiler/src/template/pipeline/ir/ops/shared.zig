/// Port of: template/pipeline/ir/src/ops/shared.ts (104 LoC)
/// DOD + Arena Memory
const std = @import("std");

pub const ListEndOp = struct {};
pub const StatementOp = struct {};
pub const VariableOp = struct {};
pub fn createStatementOp(allocator: std.mem.Allocator) void {
    _ = allocator;
}
pub fn createVariableOp(allocator: std.mem.Allocator) void {
    _ = allocator;
}
pub const NEW_OP = struct {};

test "module loads" {
    std.testing.expect(true);
}
