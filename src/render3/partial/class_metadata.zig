/// R3 Partial Class Metadata — ɵsetClassMetadata emission
///
/// Port of: compiler/src/render3/render3/partial/.ts (74 LoC)
const std = @import("std");

/// Emit ɵsetClassMetadata() for partial declarations.
pub fn compileClassMetadata(allocator: std.mem.Allocator, type_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵsetClassMetadata({s}, [], [])", .{type_name});
}
