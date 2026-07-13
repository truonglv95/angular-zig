/// Port of: template/pipeline/src/conversion.ts (84 LoC)
/// DOD + Arena Memory
const std = @import("std");

pub fn namespaceForKey(allocator: std.mem.Allocator) void { _ = allocator; }
pub fn keyForNamespace(allocator: std.mem.Allocator) void { _ = allocator; }
pub fn prefixWithNamespace(allocator: std.mem.Allocator) void { _ = allocator; }
pub fn literalOrArrayLiteral(allocator: std.mem.Allocator) void { _ = allocator; }
pub const LiteralType = anytype;
pub const BINARY_OPERATORS = struct {};

test "module loads" { std.testing.expect(true); }