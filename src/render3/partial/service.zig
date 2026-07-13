/// R3 Partial Service — Service variant of injectable
///
/// Port of: compiler/src/render3/render3/partial/.ts (59 LoC)
const std = @import("std");

/// Compile a partial service declaration (variant of injectable).
pub fn compileService(allocator: std.mem.Allocator, type_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        "ɵɵdefineInjectable({{ token: {s}, factory: () => new {s}() }})", .{ type_name, type_name });
}
