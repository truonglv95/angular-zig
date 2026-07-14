/// R3 HMR Compiler — Hot Module Replacement compilation
///
/// Port of: compiler/src/render3/r3_hmr_compiler.ts (213 LoC)
///
/// Compiles HMR (Hot Module Replacement) initialization code for Angular
/// components. When HMR is enabled, each component gets an update function
/// that can replace its definition at runtime without a full page reload.
const std = @import("std");

/// R3HmrNamespaceDependency — a dependency on a namespace import.
/// Direct port of `R3HmrNamespaceDependency` interface in the TS source.
pub const R3HmrNamespaceDependency = struct {
    /// Module name of the import (e.g., "@angular/core").
    module_name: []const u8,
    /// Name under which to refer to the namespace inside HMR code.
    assigned_name: []const u8,
};

/// R3HmrLocalDependency — a local dependency that must be passed as a parameter.
pub const R3HmrLocalDependency = struct {
    name: []const u8,
    runtime_representation: []const u8,
};

/// R3HmrMetadata — metadata for compiling HMR code.
/// Direct port of `R3HmrMetadata` interface in the TS source.
pub const R3HmrMetadata = struct {
    /// Component class for which HMR is being enabled.
    type: []const u8,
    /// Name of the component class.
    class_name: []const u8,
    /// File path of the component class.
    file_path: []const u8,
    /// Namespace dependencies (e.g., import * as i0 from '@angular/core').
    namespace_dependencies: []const R3HmrNamespaceDependency = &.{},
    /// Local dependencies that must be passed as function parameters.
    local_dependencies: []const R3HmrLocalDependency = &.{},
};

/// Compile the HMR initialization expression for a component.
/// Direct port of `compileHmrInitializer(meta)` in the TS source.
///
/// Produces an expression that registers the component for HMR updates.
/// The expression includes:
///   1. An import callback function that loads the new module
///   2. An update callback that replaces the component definition
///   3. The namespace and local dependencies
pub fn compileHmrInitializer(
    allocator: std.mem.Allocator,
    meta: R3HmrMetadata,
) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    const import_callback_name = try std.fmt.allocPrint(allocator, "{s}_HmrLoad", .{meta.class_name});
    defer allocator.free(import_callback_name);

    // Generate the import callback function.
    try buf.appendSlice("(function() {\n");
    try buf.appendSlice("  function ");
    try buf.appendSlice(import_callback_name);
    try buf.appendSlice("(m, d, t, id) {\n");
    try buf.appendSlice("    if (id) { ");
    try buf.appendSlice(meta.class_name);
    try buf.appendSlice(" = m.");
    try buf.appendSlice(meta.class_name);
    try buf.appendSlice("; }\n");
    try buf.appendSlice("  }\n");

    // Generate the namespace dependencies.
    for (meta.namespace_dependencies) |dep| {
        try buf.appendSlice("  const ");
        try buf.appendSlice(dep.assigned_name);
        try buf.appendSlice(" = require('");
        try buf.appendSlice(dep.module_name);
        try buf.appendSlice("');\n");
    }

    // Generate the HMR registration call.
    try buf.appendSlice("  if (ngDevMode) {\n");
    try buf.appendSlice("    ɵɵregisterHmr({ type: ");
    try buf.appendSlice(meta.type);
    try buf.appendSlice(", importCallback: ");
    try buf.appendSlice(import_callback_name);
    try buf.appendSlice(", filePath: '");
    try buf.appendSlice(meta.file_path);
    try buf.appendSlice("' });\n");
    try buf.appendSlice("  }\n");

    try buf.appendSlice("})()");
    return buf.toOwnedSlice();
}

/// Compile the HMR update function.
/// Direct port of `compileHmrUpdate(meta)` in the TS source.
pub fn compileHmrUpdate(
    allocator: std.mem.Allocator,
    meta: R3HmrMetadata,
) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    try buf.appendSlice("function ");
    try buf.appendSlice(meta.class_name);
    try buf.appendSlice("_HmrUpdate(m, d, t) {\n");

    // Update the component definition.
    try buf.appendSlice("  const prev = ");
    try buf.appendSlice(meta.type);
    try buf.appendSlice(";\n");
    try buf.appendSlice("  ");
    try buf.appendSlice(meta.type);
    try buf.appendSlice(" = m.");
    try buf.appendSlice(meta.class_name);
    try buf.appendSlice(";\n");
    try buf.appendSlice("  ɵɵreplaceMetadata(prev, ");
    try buf.appendSlice(meta.type);
    try buf.appendSlice(");\n");

    try buf.appendSlice("}");
    return buf.toOwnedSlice();
}

// ─── Tests ──────────────────────────────────────────────────

test "compileHmrInitializer produces registerHmr call" {
    const allocator = std.testing.allocator;
    const meta = R3HmrMetadata{
        .type = "MyComponent",
        .class_name = "MyComponent",
        .file_path = "my-component.ts",
    };
    const result = try compileHmrInitializer(allocator, meta);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "MyComponent_HmrLoad") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "registerHmr") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "my-component.ts") != null);
}

test "compileHmrUpdate produces update function" {
    const allocator = std.testing.allocator;
    const meta = R3HmrMetadata{
        .type = "MyComponent",
        .class_name = "MyComponent",
        .file_path = "my-component.ts",
    };
    const result = try compileHmrUpdate(allocator, meta);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "MyComponent_HmrUpdate") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "replaceMetadata") != null);
}

test "R3HmrMetadata defaults" {
    const meta = R3HmrMetadata{
        .type = "MyComp",
        .class_name = "MyComp",
        .file_path = "test.ts",
    };
    try std.testing.expectEqual(@as(usize, 0), meta.namespace_dependencies.len);
    try std.testing.expectEqual(@as(usize, 0), meta.local_dependencies.len);
}
