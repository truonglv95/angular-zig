/// R3 View Compiler — View compilation orchestrator
const std = @import("std");
const api = @import("api.zig");

pub fn compileComponent(allocator: std.mem.Allocator, meta: api.R3ComponentMetadata, template: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵdefineComponent({{ type: {s}, template: '{s}' }})", .{ meta.base.name, template });
}

pub fn compileDirective(allocator: std.mem.Allocator, meta: api.R3DirectiveMetadata) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.appendSlice("ɵɵdefineDirective({ type: "); try buf.appendSlice(meta.base.name);
    try buf.appendSlice(", selectors: [['"); try buf.appendSlice(meta.base.selector);
    try buf.appendSlice("']] })");
    return buf.toOwnedSlice();
}

pub fn compileHostBindings(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "// Host bindings for {s}", .{name});
}
