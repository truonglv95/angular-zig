/// R3 Partial Factory — ɵɵdeclareFactory emission
///
/// Port of: compiler/src/render3/render3/partial/.ts (41 LoC)
const std = @import("std");

/// Compile a partial factory declaration.
pub fn compileFactory(allocator: std.mem.Allocator, type_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        "ɵɵdeclareFactory({{ type: {s}, factory: () => new {s}() }})", .{ type_name, type_name });
}
