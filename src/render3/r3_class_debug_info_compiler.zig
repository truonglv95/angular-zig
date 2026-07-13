/// R3 Class Debug Info Compiler
///
/// Port of: compiler/src/render3/render3/.ts (82 LoC)
const std = @import("std");

/// Emit ɵsetClassDebugInfo() call for runtime error localization.
pub fn compileClassDebugInfo(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵsetClassDebugInfo({{ className: '{s}' }})", .{name});
}
