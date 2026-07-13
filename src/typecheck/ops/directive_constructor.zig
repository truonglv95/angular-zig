/// TCB Ops Directive Constructor — Directive constructor TCB ops
///
/// Port of: compiler/src/typecheck/typecheck/ops/directive_constructor.ts (209 LoC)
const std = @import("std");

/// DirectiveConstructorOp — generate TCB for directive constructor calls.
pub fn generateConstructor(allocator: std.mem.Allocator, directive_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "new {s}()", .{directive_name});
}
