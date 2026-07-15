/// R3 Module Compiler — Compile NgModule definitions
///
/// Port of: compiler/src/render3/r3_module_compiler.ts (434 LoC)
///
/// Compiles NgModule metadata into `ɵɵdefineNgModule(...)` calls.
/// Handles declaration, import, and export arrays.
const std = @import("std");

/// How the selector scope of an NgModule should be emitted.
/// Direct port of `R3SelectorScopeMode` enum in the TS source.
pub const R3SelectorScopeMode = enum(u8) {
    /// Emit declarations inline into the module definition.
    Inline,
    /// Emit declarations using `ɵɵsetNgModuleScope`, guarded by `ngJitMode`.
    SideEffect,
    /// Don't generate selector scopes at all.
    Omit,
};

/// The type of the NgModule metadata.
/// Direct port of `R3NgModuleMetadataKind` enum in the TS source.
pub const R3NgModuleMetadataKind = enum(u8) {
    /// Used for full and partial compilation modes (R3References).
    Global,
    /// Used for local compilation mode (raw expressions).
    Local,
    /// Isolated module (no scope).
    Isolated,
};

/// R3Reference — a reference to a class or module.
pub const R3Reference = struct {
    name: []const u8,
    module_name: ?[]const u8 = null,
};

/// R3NgModuleMetadata — metadata for compiling an NgModule.
/// Direct port of `R3NgModuleMetadata` interface in the TS source.
pub const R3NgModuleMetadata = struct {
    kind: R3NgModuleMetadataKind = .Global,
    type: R3Reference,
    declarations: []const R3Reference = &.{},
    imports: []const R3Reference = &.{},
    exports: []const R3Reference = &.{},
    bootstrap: []const R3Reference = &.{},
    schemas: []const []const u8 = &.{},
    id: ?[]const u8 = null,
};

/// Compile an NgModule into an Ivy definition.
/// Direct port of `compileNgModule(...)` in the TS source.
///
/// Produces: `ɵɵdefineNgModule({ type: ..., declarations: [...], imports: [...], exports: [...] })`
pub fn compileNgModule(
    allocator: std.mem.Allocator,
    meta: R3NgModuleMetadata,
) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    try buf.appendSlice("ɵɵdefineNgModule({ type: ");
    try buf.appendSlice(meta.type.name);

    // Bootstrap
    if (meta.bootstrap.len > 0) {
        try buf.appendSlice(", bootstrap: [");
        try refsToArray(allocator, &buf, meta.bootstrap);
        try buf.append(']');
    }

    // Declarations
    if (meta.declarations.len > 0) {
        try buf.appendSlice(", declarations: [");
        try refsToArray(allocator, &buf, meta.declarations);
        try buf.append(']');
    }

    // Imports
    if (meta.imports.len > 0) {
        try buf.appendSlice(", imports: [");
        try refsToArray(allocator, &buf, meta.imports);
        try buf.append(']');
    }

    // Exports
    if (meta.exports.len > 0) {
        try buf.appendSlice(", exports: [");
        try refsToArray(allocator, &buf, meta.exports);
        try buf.append(']');
    }

    try buf.appendSlice(" })");
    return buf.toOwnedSlice();
}

/// Compile the NgModule scope (declarations, imports, exports).
/// Direct port of `compileNgModuleScope(...)` in the TS source.
pub fn compileNgModuleScope(
    allocator: std.mem.Allocator,
    meta: R3NgModuleMetadata,
) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    try buf.appendSlice("ɵɵsetNgModuleScope(");
    try buf.appendSlice(meta.type.name);
    try buf.appendSlice(", { ");

    var first = true;
    if (meta.declarations.len > 0) {
        try buf.appendSlice("declarations: [");
        try refsToArray(allocator, &buf, meta.declarations);
        try buf.append(']');
        first = false;
    }
    if (meta.imports.len > 0) {
        if (!first) try buf.appendSlice(", ");
        try buf.appendSlice("imports: [");
        try refsToArray(allocator, &buf, meta.imports);
        try buf.append(']');
        first = false;
    }
    if (meta.exports.len > 0) {
        if (!first) try buf.appendSlice(", ");
        try buf.appendSlice("exports: [");
        try refsToArray(allocator, &buf, meta.exports);
        try buf.append(']');
    }

    try buf.appendSlice(" })");
    return buf.toOwnedSlice();
}

/// Helper: convert an array of R3References to a comma-separated string.
fn refsToArray(allocator: std.mem.Allocator, buf: *std.array_list.Managed(u8), refs: []const R3Reference) !void {
    _ = allocator;
    for (refs, 0..) |ref, i| {
        if (i > 0) try buf.appendSlice(", ");
        try buf.appendSlice(ref.name);
    }
}

// ─── Tests ──────────────────────────────────────────────────

test "compileNgModule basic" {
    const allocator = std.testing.allocator;
    const meta = R3NgModuleMetadata{
        .type = .{ .name = "MyModule" },
    };
    const result = try compileNgModule(allocator, meta);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "ɵɵdefineNgModule") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "MyModule") != null);
}

test "compileNgModule with declarations and imports" {
    const allocator = std.testing.allocator;
    const decls = [_]R3Reference{ .{ .name = "MyComp" }, .{ .name = "MyDir" } };
    const imports = [_]R3Reference{.{ .name = "CommonModule" }};
    const meta = R3NgModuleMetadata{
        .type = .{ .name = "MyModule" },
        .declarations = &decls,
        .imports = &imports,
    };
    const result = try compileNgModule(allocator, meta);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "MyComp") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "CommonModule") != null);
}

test "R3SelectorScopeMode values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(R3SelectorScopeMode.Inline));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(R3SelectorScopeMode.SideEffect));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(R3SelectorScopeMode.Omit));
}

test "R3NgModuleMetadataKind values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(R3NgModuleMetadataKind.Global));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(R3NgModuleMetadataKind.Local));
}
