/// R3 Partial Injectable — Compile injectable definitions
///
/// Port of: compiler/src/render3/partial/injectable.ts (82 LoC)
const std = @import("std");
const api = @import("api.zig");

/// Compile an injectable into a partial declaration.
pub fn compileInjectable(
    allocator: std.mem.Allocator,
    meta: api.R3DeclareInjectableMetadata,
) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    try buf.appendSlice("ɵɵngDeclareInjectable({ ");
    try buf.appendSlice("type: ");
    try buf.appendSlice(meta.base.type);

    if (meta.provided_in) |pi| {
        try buf.appendSlice(", providedIn: ");
        try buf.appendSlice(pi);
    }

    try buf.appendSlice(" })");
    return buf.toOwnedSlice();
}

test "compileInjectable" {
    const allocator = std.testing.allocator;
    const meta = api.R3DeclareInjectableMetadata{
        .base = .{
            .min_version = "14.0.0",
            .version = "16.0.0",
            .ng_import = "@angular/core",
            .type = "MyService",
        },
        .provided_in = "root",
    };
    const result = try compileInjectable(allocator, meta);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "ɵɵngDeclareInjectable") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "root") != null);
}
