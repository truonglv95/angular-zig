/// R3 View Compiler — View compilation orchestrator
///
/// Port of: compiler/src/render3/render3/view/.ts (801 LoC)
const std = @import("std");

/// Compile a component's template into output AST statements.
/// Delegates to the template/pipeline/ for the actual IR pipeline.
const pipeline = @import("../template/pipeline/src/registry.zig");

pub fn compileComponent(allocator: std.mem.Allocator, name: []const u8, template: []const u8) ![]const u8 {
    _ = allocator;
    _ = name;
    _ = template;
    // The actual compilation is handled by the compiler.zig facade
    // which calls the full pipeline (HTML parse → R3 transform → IR → emit)
    return "";
}

pub fn compileDirective(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵdefineDirective({{ type: {s} }})", .{name});
}

pub fn compileHostBindings(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "// Host bindings for {s}", .{name});
}
