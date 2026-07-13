/// R3 Module Compiler — Generate ɵɵdefineNgModule calls
///
/// Port of: compiler/src/render3/render3/.ts (434 LoC)
const std = @import("std");

/// R3NgModuleMetadata — metadata for NgModule compilation.
pub const R3NgModuleMetadata = struct {
    name: []const u8,
    declarations: []const []const u8 = &.{},
    imports: []const []const u8 = &.{},
    exports: []const []const u8 = &.{},
    bootstrap: []const []const u8 = &.{},
    schemas: []const []const u8 = &.{},
};

/// Compile ɵɵdefineNgModule() call.
pub fn compileNgModule(allocator: std.mem.Allocator, meta: R3NgModuleMetadata) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        "ɵɵdefineNgModule({{ type: {s} }})", .{meta.name});
}

/// Create the NgModule type declaration.
pub fn createNgModuleType(allocator: std.mem.Allocator, meta: R3NgModuleMetadata) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.appendSlice("class ");
    try buf.appendSlice(meta.name);
    try buf.appendSlice(" { static ɵmod = ");
    try buf.appendSlice(try compileNgModule(allocator, meta));
    try buf.appendSlice("; }");
    return buf.toOwnedSlice();
}
