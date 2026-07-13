/// R3 Partial Component — ɵɵdeclareComponent emission
///
/// Port of: compiler/src/render3/render3/partial/.ts (288 LoC)
const std = @import("std");

/// Compile a partial component declaration into a full ɵɵdefineComponent call.
pub fn compileComponent(allocator: std.mem.Allocator, type_name: []const u8, template: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        "ɵɵdefineComponent({{ type: {s}, template: '{s}' }})", .{ type_name, template });
}
