/// TCB Ops Content Projection — ng-content TCB operations
///
/// Port of: compiler/src/typecheck/typecheck/ops/content_projection.ts (157 LoC)
const std = @import("std");

/// ContentProjectionOp — handle ng-content in TCB.
pub fn generateProjectionCheck(allocator: std.mem.Allocator, slot: u32) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵprojection({d})", .{slot});
}
