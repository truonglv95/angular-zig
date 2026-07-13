/// R3 Injector Compiler — Generate ɵɵdefineInjector calls
///
/// Port of: compiler/src/render3/render3/.ts (44 LoC)
const std = @import("std");

/// R3InjectorMetadata — metadata for injector compilation.
pub const R3InjectorMetadata = struct {
    name: []const u8,
    providers: []const []const u8 = &.{},
};

/// Compile ɵɵdefineInjector() call.
pub fn compileInjector(allocator: std.mem.Allocator, meta: R3InjectorMetadata) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        "ɵɵdefineInjector({{ type: {s} }})", .{meta.name});
}
