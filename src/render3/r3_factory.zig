/// R3 Factory — Generate ɵɵdeclareFactory calls
///
/// Port of: compiler/src/render3/render3/.ts (344 LoC)
const std = @import("std");

/// R3FactoryMetadata — metadata for factory generation.
pub const R3FactoryMetadata = struct {
    name: []const u8,
    target: u8 = 0, // FactoryTarget
    deps: []const []const u8 = &.{},
};

/// Generate ɵɵdeclareFactory() call.
pub fn compileFactory(allocator: std.mem.Allocator, meta: R3FactoryMetadata) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        "ɵɵdeclareFactory({{ type: {s}, deps: [] }})", .{meta.name});
}
