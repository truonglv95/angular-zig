/// R3 Partial Pipe — Compile pipe definitions
///
/// Port of: compiler/src/render3/partial/pipe.ts (65 LoC)
const std = @import("std");
const api = @import("api.zig");

/// Compile a pipe into a partial declaration.
pub fn compilePipe(
    allocator: std.mem.Allocator,
    meta: api.R3DeclarePipeMetadata,
) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    try buf.appendSlice("ɵɵngDeclarePipe({ ");
    try buf.appendSlice("type: ");
    try buf.appendSlice(meta.base.type);
    try buf.appendSlice(", name: \"");
    try buf.appendSlice(meta.name);
    try buf.appendSlice("\"");

    if (meta.pure) {
        try buf.appendSlice(", pure: true");
    } else {
        try buf.appendSlice(", pure: false");
    }

    if (meta.is_standalone) {
        try buf.appendSlice(", standalone: true");
    }

    try buf.appendSlice(" })");
    return buf.toOwnedSlice();
}

test "compilePipe" {
    const allocator = std.testing.allocator;
    const meta = api.R3DeclarePipeMetadata{
        .base = .{
            .min_version = "14.0.0",
            .version = "16.0.0",
            .ng_import = "@angular/core",
            .type = "MyPipe",
        },
        .name = "myPipe",
    };
    const result = try compilePipe(allocator, meta);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "ɵɵngDeclarePipe") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "myPipe") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "pure: true") != null);
}
