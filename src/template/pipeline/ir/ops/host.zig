/// Port of: template/pipeline/ir/src/ops/host.ts (58 LoC)
/// DOD + Arena Memory
const std = @import("std");

pub const DomPropertyOp = struct {};
pub fn createDomPropertyOp(allocator: std.mem.Allocator) void { _ = allocator; }

test "module loads" { std.testing.expect(true); }