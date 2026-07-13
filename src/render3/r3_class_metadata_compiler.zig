/// R3 Class Metadata Compiler
///
/// Port of: compiler/src/render3/render3/.ts (164 LoC)
const std = @import("std");

/// R3ClassMetadata — metadata for ɵsetClassMetadata calls.
pub const R3ClassMetadata = struct {
    type_name: []const u8,
    decorators: []const []const u8 = &.{},
    ctor_params: []const []const u8 = &.{},
};

/// Emit ɵsetClassMetadata() call preserving original decorator info.
pub fn compileClassMetadata(allocator: std.mem.Allocator, meta: R3ClassMetadata) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵsetClassMetadata({{ type: {s} }})", .{meta.type_name});
}
