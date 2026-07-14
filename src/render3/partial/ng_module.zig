/// R3 Partial NgModule — Compile NgModule definitions
///
/// Port of: compiler/src/render3/partial/ng_module.ts (94 LoC)
const std = @import("std");
const api = @import("api.zig");

/// Compile an NgModule into a partial declaration.
pub fn compileNgModule(
    allocator: std.mem.Allocator,
    meta: api.R3DeclareNgModuleMetadata,
) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    try buf.appendSlice("ɵɵngDeclareNgModule({ ");
    try buf.appendSlice("type: ");
    try buf.appendSlice(meta.base.type);

    if (meta.imports) |imports| {
        try buf.appendSlice(", imports: [");
        for (imports, 0..) |imp, i| {
            if (i > 0) try buf.appendSlice(", ");
            try buf.appendSlice(imp);
        }
        try buf.append(']');
    }

    if (meta.declarations) |decls| {
        try buf.appendSlice(", declarations: [");
        for (decls, 0..) |decl, i| {
            if (i > 0) try buf.appendSlice(", ");
            try buf.appendSlice(decl);
        }
        try buf.append(']');
    }

    if (meta.exports) |exports| {
        try buf.appendSlice(", exports: [");
        for (exports, 0..) |exp, i| {
            if (i > 0) try buf.appendSlice(", ");
            try buf.appendSlice(exp);
        }
        try buf.append(']');
    }

    try buf.appendSlice(" })");
    return buf.toOwnedSlice();
}

test "compileNgModule" {
    const allocator = std.testing.allocator;
    const imports = [_][]const u8{"CommonModule"};
    const meta = api.R3DeclareNgModuleMetadata{
        .base = .{
            .min_version = "14.0.0",
            .version = "16.0.0",
            .ng_import = "@angular/core",
            .type = "MyModule",
        },
        .imports = &imports,
    };
    const result = try compileNgModule(allocator, meta);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "ɵɵngDeclareNgModule") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "CommonModule") != null);
}
