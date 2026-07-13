/// R3 Partial NgModule — ɵɵdeclareNgModule emission
///
/// Port of: compiler/src/render3/render3/partial/.ts (94 LoC)
const std = @import("std");

/// Compile a partial NgModule declaration.
pub fn compileNgModule(allocator: std.mem.Allocator, type_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        "ɵɵdefineNgModule({{ type: {s} }})", .{type_name});
}
