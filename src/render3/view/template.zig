/// R3 View Template — Legacy template compile entry point
const std = @import("std");
const compiler = @import("compiler.zig");

pub fn compileTemplate(allocator: std.mem.Allocator, name: []const u8, template: []const u8) ![]const u8 {
    return compiler.compileComponent(allocator, .{ .base = .{ .name = name } }, template);
}
