/// R3 Class Metadata Compiler — Compile class metadata for TestBed
///
/// Port of: compiler/src/render3/r3_class_metadata_compiler.ts (164 LoC)
///
/// Compiles class metadata that captures the original Angular decorators
/// applied to a class. This metadata is preserved in generated code to allow
/// TestBed APIs to recompile the class with overrides.
const std = @import("std");

/// R3ClassMetadata — metadata of a class capturing original Angular decorators.
/// Direct port of `R3ClassMetadata` interface in the TS source.
pub const R3ClassMetadata = struct {
    /// The class type for which the metadata is captured.
    type: []const u8,
    /// An expression representing the Angular decorators applied on the class.
    decorators: []const u8,
    /// An expression representing the Angular decorators applied to constructor
    /// parameters, or null if there is no constructor.
    ctor_parameters: ?[]const u8 = null,
    /// An expression representing the Angular decorators applied on the
    /// properties of the class, or null if no properties have decorators.
    prop_decorators: ?[]const u8 = null,
};

/// Compile class metadata into a `ɵɵsetClassMetadata(...)` call.
/// Direct port of `compileClassMetadata(metadata)` in the TS source.
///
/// Produces an expression that calls `ɵɵsetClassMetadata` with the class type,
/// decorators, constructor parameters, and property decorators. The call is
/// wrapped in `ngDevMode` guard so it's removed in production builds.
pub fn compileClassMetadata(
    allocator: std.mem.Allocator,
    meta: R3ClassMetadata,
) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    // Wrap in ngDevMode guard (dev-only)
    try buf.appendSlice("(ngDevMode && ɵɵsetClassMetadata(");
    try buf.appendSlice(meta.type);
    try buf.appendSlice(", ");
    try buf.appendSlice(meta.decorators);
    try buf.appendSlice(", ");
    try buf.appendSlice(meta.ctor_parameters orelse "null");
    try buf.appendSlice(", ");
    try buf.appendSlice(meta.prop_decorators orelse "null");
    try buf.appendSlice("))");

    return buf.toOwnedSlice();
}

/// Compile class metadata without the ngDevMode guard wrapper.
/// Direct port of `internalCompileClassMetadata(metadata)` in the TS source.
pub fn compileClassMetadataRaw(
    allocator: std.mem.Allocator,
    meta: R3ClassMetadata,
) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    try buf.appendSlice("ɵɵsetClassMetadata(");
    try buf.appendSlice(meta.type);
    try buf.appendSlice(", ");
    try buf.appendSlice(meta.decorators);
    try buf.appendSlice(", ");
    try buf.appendSlice(meta.ctor_parameters orelse "null");
    try buf.appendSlice(", ");
    try buf.appendSlice(meta.prop_decorators orelse "null");
    try buf.append(')');

    return buf.toOwnedSlice();
}

// ─── Tests ──────────────────────────────────────────────────

test "compileClassMetadata produces setClassMetadata call" {
    const allocator = std.testing.allocator;
    const meta = R3ClassMetadata{
        .type = "MyComp",
        .decorators = "decorators",
        .ctor_parameters = "ctorParams",
        .prop_decorators = "propDecorators",
    };
    const result = try compileClassMetadata(allocator, meta);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "ɵɵsetClassMetadata") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "MyComp") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "ngDevMode") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "ctorParams") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "propDecorators") != null);
}

test "compileClassMetadata with null ctor/prop" {
    const allocator = std.testing.allocator;
    const meta = R3ClassMetadata{
        .type = "MyComp",
        .decorators = "decorators",
    };
    const result = try compileClassMetadata(allocator, meta);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "null") != null);
}

test "compileClassMetadataRaw without ngDevMode guard" {
    const allocator = std.testing.allocator;
    const meta = R3ClassMetadata{
        .type = "MyComp",
        .decorators = "decorators",
    };
    const result = try compileClassMetadataRaw(allocator, meta);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "ɵɵsetClassMetadata") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "ngDevMode") == null);
}
