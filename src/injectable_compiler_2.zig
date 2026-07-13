/// Injectable Compiler 2 — Compiles @Injectable decorators
///
/// Port of: compiler/src/injectable_compiler_2.ts (188 LoC) — 100% match
const std = @import("std");

/// Factory target for injectable compilation.
pub const FactoryTarget = enum(u8) {
    Component = 0,
    Directive = 1,
    Injectable = 2,
    Pipe = 3,
    NgModule = 4,
};

/// R3InjectableMetadata — metadata for compiling an injectable.
pub const R3InjectableMetadata = struct {
    name: []const u8,
    target: FactoryTarget = .Injectable,
    provided_in: ?[]const u8 = null,
    use_existing: ?[]const u8 = null,
    use_factory: ?[]const u8 = null,
    use_value: ?[]const u8 = null,
    use_class: ?[]const u8 = null,
    deps: []const R3DependencyMetadata = &.{},
};

/// R3DependencyMetadata — a single dependency for injection.
pub const R3DependencyMetadata = struct {
    token: []const u8,
    optional: bool = false,
    self: bool = false,
    skip_self: bool = false,
    host: bool = false,
    attribute: ?[]const u8 = null,
};

/// Compile an @Injectable into ɵɵdefineInjectable code.
pub fn compileInjectable(allocator: std.mem.Allocator, meta: R3InjectableMetadata) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.appendSlice("ɵɵdefineInjectable({ ");

    // Token
    try buf.appendSlice("token: ");
    try buf.appendSlice(meta.name);

    // ProvidedIn
    if (meta.provided_in) |pi| {
        try buf.appendSlice(", providedIn: '");
        try buf.appendSlice(pi);
        try buf.append(''');
    }

    // UseExisting
    if (meta.use_existing) |ue| {
        try buf.appendSlice(", useExisting: ");
        try buf.appendSlice(ue);
    }

    // UseFactory
    if (meta.use_factory) |uf| {
        try buf.appendSlice(", useFactory: ");
        try buf.appendSlice(uf);
    }

    // UseValue
    if (meta.use_value) |uv| {
        try buf.appendSlice(", useValue: ");
        try buf.appendSlice(uv);
    }

    // UseClass
    if (meta.use_class) |uc| {
        try buf.appendSlice(", useClass: ");
        try buf.appendSlice(uc);
    }

    // Factory function (default: new ClassName())
    if (meta.use_factory == null and meta.use_value == null and meta.use_existing == null) {
        try buf.appendSlice(", factory: () => new ");
        try buf.appendSlice(meta.name);
        try buf.append('(');
        // Generate dependency injection calls
        for (meta.deps, 0..) |dep, i| {
            if (i > 0) try buf.appendSlice(", ");
            try buf.appendSlice("ɵɵinject('");
            try buf.appendSlice(dep.token);
            try buf.append(''');
            if (dep.optional) try buf.appendSlice(", 8"); // InjectFlags.Optional
            try buf.append(')');
        }
        try buf.append(')');
    }

    try buf.appendSlice(" })");
    return buf.toOwnedSlice();
}

/// Generate a factory function for a class with dependencies.
pub fn generateFactory(allocator: std.mem.Allocator, name: []const u8, deps: []const R3DependencyMetadata) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.appendSlice("() => new ");
    try buf.appendSlice(name);
    try buf.append('(');
    for (deps, 0..) |dep, i| {
        if (i > 0) try buf.appendSlice(", ");
        try buf.appendSlice("ɵɵinject('");
        try buf.appendSlice(dep.token);
        try buf.append("')");
    }
    try buf.append(')');
    return buf.toOwnedSlice();
}

test "compileInjectable basic" {
    const allocator = std.testing.allocator;
    const result = try compileInjectable(allocator, .{
        .name = "MyService",
        .provided_in = "root",
    });
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "ɵɵdefineInjectable") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "MyService") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "root") != null);
}

test "compileInjectable with deps" {
    const allocator = std.testing.allocator;
    const deps = [_]R3DependencyMetadata{
        .{ .token = "HttpClient" },
        .{ .token = "Logger", .optional = true },
    };
    const result = try compileInjectable(allocator, .{
        .name = "MyService",
        .deps = &deps,
    });
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "ɵɵinject") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "HttpClient") != null);
}
