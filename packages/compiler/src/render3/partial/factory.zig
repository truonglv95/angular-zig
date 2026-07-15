/// R3 Partial Factory — Compile factory definitions
///
/// Port of: compiler/src/render3/partial/factory.ts (41 LoC)
const std = @import("std");

/// FactoryTarget — the kind of Angular factory being compiled.
pub const FactoryTarget = enum(u8) {
    Component,
    Directive,
    Injectable,
    Pipe,
    NgModule,
    Factory,
};

/// Compile a factory function for a class.
pub fn compileFactory(
    allocator: std.mem.Allocator,
    type_name: []const u8,
    deps: []const []const u8,
    target: FactoryTarget,
) ![]const u8 {
    _ = target;
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    try buf.appendSlice("ɵɵdefineFactory({ type: ");
    try buf.appendSlice(type_name);
    try buf.appendSlice(", factory: () => new ");

    if (deps.len == 0) {
        try buf.appendSlice(type_name);
        try buf.appendSlice("() }");
    } else {
        try buf.appendSlice(type_name);
        try buf.append('(');
        for (deps, 0..) |dep, i| {
            if (i > 0) try buf.appendSlice(", ");
            try buf.appendSlice("inject(");
            try buf.appendSlice(dep);
            try buf.append(')');
        }
        try buf.appendSlice(") }");
    }

    return buf.toOwnedSlice();
}

test "compileFactory without deps" {
    const allocator = std.testing.allocator;
    const result = try compileFactory(allocator, "MyService", &.{}, .Injectable);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "new MyService()") != null);
}

test "compileFactory with deps" {
    const allocator = std.testing.allocator;
    const deps = [_][]const u8{"Http"};
    const result = try compileFactory(allocator, "MyService", &deps, .Injectable);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "inject(Http)") != null);
}
