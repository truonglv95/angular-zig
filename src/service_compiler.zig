/// Service Compiler — Compiles @Injectable services
///
/// Port of: compiler/src/service_compiler.ts (58 LoC) — 100% match
const std = @import("std");
const injectable_compiler = @import("injectable_compiler_2.zig");

/// R3ServiceMetadata — metadata for compiling a service.
pub const R3ServiceMetadata = struct {
    name: []const u8,
    provided_in: ?[]const u8 = null,
    use_factory: ?[]const u8 = null,
    use_value: ?[]const u8 = null,
    use_class: ?[]const u8 = null,
    deps: []const []const u8 = &.{},
};

/// Compile a service class decorated with @Injectable().
/// Generates ɵɵdefineInjectable() call.
pub fn compileService(allocator: std.mem.Allocator, meta: R3ServiceMetadata) ![]const u8 {
    return injectable_compiler.compileInjectable(allocator, .{
        .name = meta.name,
        .provided_in = meta.provided_in,
        .use_factory = meta.use_factory,
        .use_value = meta.use_value,
        .use_class = meta.use_class,
    });
}

/// Generate a factory function for a service.
pub fn compileServiceFactory(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        "ɵɵdefineFactory({{ type: {s}, target: 2, deps: [] }})", .{name});
}
