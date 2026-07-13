/// R3 Partial Injectable — ɵɵdeclareInjectable emission
///
/// Port of: compiler/src/render3/render3/partial/.ts (82 LoC)
const std = @import("std");

/// Compile a partial injectable declaration.
pub fn compileInjectable(allocator: std.mem.Allocator, type_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        "ɵɵdefineInjectable({{ token: {s}, factory: () => new {s}() }})", .{ type_name, type_name });
}
