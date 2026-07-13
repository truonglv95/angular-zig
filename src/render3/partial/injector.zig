/// R3 Partial Injector — ɵɵdeclareInjector emission
///
/// Port of: compiler/src/render3/render3/partial/.ts (53 LoC)
const std = @import("std");

/// Compile a partial injector declaration.
pub fn compileInjector(allocator: std.mem.Allocator, type_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        "ɵɵdefineInjector({{ type: {s} }})", .{type_name});
}
