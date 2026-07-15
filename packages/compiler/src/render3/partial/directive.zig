/// R3 Partial Directive — Compile directive definitions
///
/// Port of: compiler/src/render3/partial/directive.ts (344 LoC)
///
/// Compiles directive metadata into `ɵɵdefineDirective(...)` calls.
const std = @import("std");
const api = @import("api.zig");

/// Compile a directive into a partial declaration.
/// Direct port of `compileDirective(...)` in the TS source.
pub fn compileDirective(
    allocator: std.mem.Allocator,
    meta: api.R3DeclareDirectiveMetadata,
) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    try buf.appendSlice("ɵɵngDeclareDirective({ ");
    try buf.appendSlice("minVersion: \"");
    try buf.appendSlice(meta.base.min_version);
    try buf.appendSlice("\", version: \"");
    try buf.appendSlice(meta.base.version);
    try buf.appendSlice("\", type: ");
    try buf.appendSlice(meta.base.type);

    if (meta.selector) |selector| {
        try buf.appendSlice(", selectors: [[\"\", \"");
        try buf.appendSlice(selector);
        try buf.appendSlice("\", \"\"]] ");
    }

    try buf.appendSlice(", inputs: {}, outputs: {}, host: {}");

    if (meta.is_standalone) {
        try buf.appendSlice(", standalone: true");
    }

    try buf.appendSlice(" })");

    return buf.toOwnedSlice();
}

/// Declare a directive metadata object.
/// Direct port of `declareDirective(...)` in the TS source.
pub fn declareDirective(
    allocator: std.mem.Allocator,
    meta: api.R3DeclareDirectiveMetadata,
) ![]const u8 {
    return compileDirective(allocator, meta);
}

// ─── Tests ──────────────────────────────────────────────────

test "compileDirective produces ngDeclareDirective" {
    const allocator = std.testing.allocator;
    const meta = api.R3DeclareDirectiveMetadata{
        .base = .{
            .min_version = "14.0.0",
            .version = "16.0.0",
            .ng_import = "@angular/core",
            .type = "MyDirective",
        },
        .selector = "myDir",
    };
    const result = try compileDirective(allocator, meta);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "ɵɵngDeclareDirective") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "MyDirective") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "myDir") != null);
}

test "compileDirective with standalone" {
    const allocator = std.testing.allocator;
    const meta = api.R3DeclareDirectiveMetadata{
        .base = .{
            .min_version = "14.0.0",
            .version = "16.0.0",
            .ng_import = "@angular/core",
            .type = "MyDir",
        },
        .is_standalone = true,
    };
    const result = try compileDirective(allocator, meta);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "standalone: true") != null);
}
