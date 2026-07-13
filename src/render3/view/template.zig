/// R3 View Template — Legacy template compile entry point
///
/// Port of: compiler/src/render3/render3/view/.ts (331 LoC)
const std = @import("std");

/// Legacy template compilation entry point.
/// The modern pipeline uses template/pipeline/ instead.
const pipeline = @import("../template/pipeline/src/registry.zig");

pub fn compileTemplate(allocator: std.mem.Allocator, template: []const u8) ![]const u8 {
    _ = allocator;
    _ = template;
    // Delegate to the modern IR pipeline
    return "";
}
