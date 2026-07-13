/// R3 HMR Compiler — Hot Module Replacement support
///
/// Port of: compiler/src/render3/render3/.ts (213 LoC)
const std = @import("std");

/// Compile HMR update function for a component.
pub fn compileHmrUpdate(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        "ɵɵreplaceComponent({{ type: {s} }})", .{name});
}
