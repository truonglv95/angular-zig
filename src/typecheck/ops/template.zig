/// TCB Ops Template — Template node TCB operations
///
/// Port of: compiler/src/typecheck/typecheck/ops/template.ts (199 LoC)
const std = @import("std");

/// TemplateOp — generate TCB for ng-template nodes.
pub fn generateTemplateCheck(allocator: std.mem.Allocator, slot: u32) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵtemplate({d})", .{slot});
}
