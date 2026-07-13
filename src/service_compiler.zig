/// Service Compiler — Compiles @Injectable services
///
/// Port of: compiler/src/service_compiler.ts
const std = @import("std");

/// Compiles service classes decorated with @Injectable().
pub fn compileService(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        "ɵɵdefineInjectable({{ factory: () => new {s}() }})", .{name});
}
