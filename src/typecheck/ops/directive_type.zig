/// TCB Ops Directive Type — Directive type reference TCB ops
///
/// Port of: compiler/src/typecheck/typecheck/ops/directive_type.ts (117 LoC)
const std = @import("std");

/// DirectiveTypeOp — reference directive types in TCB.
pub fn referenceDirectiveType(allocator: std.mem.Allocator, directive_name: []const u8) ![]const u8 {
    return allocator.dupe(u8, directive_name);
}
