/// Injectable Compiler 2 — Compiles @Injectable decorators
///
/// Port of: compiler/src/injectable_compiler_2.ts
const std = @import("std");

/// Compiles @Injectable() decorators into ɵɵdefineInjectable calls.
pub fn compileInjectable(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        "ɵɵdefineInjectable({{ token: {s}, providedIn: 'root' }})", .{name});
}
