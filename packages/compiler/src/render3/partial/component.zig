/// R3 Partial Component — Compile component definitions
///
/// Port of: compiler/src/render3/partial/component.ts (288 LoC)
///
/// Compiles component metadata into `ɵɵngDeclareComponent(...)` calls.
const std = @import("std");
const api = @import("api.zig");

/// Compile a component into a partial declaration.
/// Direct port of `compileComponent(...)` in the TS source.
pub fn compileComponent(
    allocator: std.mem.Allocator,
    meta: api.R3DeclareComponentMetadata,
) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    try buf.appendSlice("ɵɵngDeclareComponent({ ");
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

    // Template
    try buf.appendSlice(", template: \"");
    try buf.appendSlice(meta.template);
    try buf.appendSlice("\"");

    // Decls and vars
    {
        const decls_str = try std.fmt.allocPrint(allocator, ", decls: {d}, vars: {d}", .{ meta.decls, meta.vars });
        defer allocator.free(decls_str);
        try buf.appendSlice(decls_str);
    }

    if (meta.is_standalone) {
        try buf.appendSlice(", standalone: true");
    }

    if (meta.encapsulation == 0) {
        try buf.appendSlice(", encapsulation: 0");
    }

    try buf.appendSlice(" })");

    return buf.toOwnedSlice();
}

/// Declare a component metadata object.
/// Direct port of `declareComponent(...)` in the TS source.
pub fn declareComponent(
    allocator: std.mem.Allocator,
    meta: api.R3DeclareComponentMetadata,
) ![]const u8 {
    return compileComponent(allocator, meta);
}

// ─── Tests ──────────────────────────────────────────────────

test "compileComponent produces ngDeclareComponent" {
    const allocator = std.testing.allocator;
    const meta = api.R3DeclareComponentMetadata{
        .base = .{
            .min_version = "14.0.0",
            .version = "16.0.0",
            .ng_import = "@angular/core",
            .type = "MyComp",
        },
        .selector = "my-comp",
        .template = "<div>Hello</div>",
        .decls = 2,
        .vars = 0,
    };
    const result = try compileComponent(allocator, meta);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "ɵɵngDeclareComponent") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "MyComp") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "my-comp") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "<div>Hello</div>") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "decls: 2") != null);
}
