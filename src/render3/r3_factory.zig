/// R3 Factory — Compile factory functions for Angular classes
///
/// Port of: compiler/src/render3/r3_factory.ts (344 LoC)
///
/// Generates `ɵɵdefineFactory(...)` calls for components, directives, pipes,
/// injectables, and NgModules. The factory function creates new instances
/// of the class with injected dependencies.
const std = @import("std");

/// FactoryTarget — the kind of Angular factory being compiled.
/// Direct port of `FactoryTarget` from compiler_facade_interface.ts.
pub const FactoryTarget = enum(u8) {
    Component,
    Directive,
    Injectable,
    Pipe,
    NgModule,
    Factory,
};

/// R3FactoryDelegateType — whether the factory delegates to a class or function.
/// Direct port of `R3FactoryDelegateType` enum in the TS source.
pub const R3FactoryDelegateType = enum(u8) {
    Class = 0,
    Function = 1,
};

/// R3DependencyMetadata — metadata for a single dependency injection.
/// Direct port of `R3DependencyMetadata` interface in the TS source.
pub const R3DependencyMetadata = struct {
    /// An expression representing the token or value to be injected.
    token: ?[]const u8 = null,
    /// If an @Attribute decorator is present, the literal type of the attribute name.
    attribute_name_type: ?[]const u8 = null,
    /// Whether this dependency is optional.
    optional: bool = false,
    /// Whether this dependency should be resolved from the host node.
    host: bool = false,
    /// Whether this dependency should be resolved from the self injector.
    self: bool = false,
    /// Whether this dependency should skip the self injector.
    skip_self: bool = false,
};

/// R3Reference — a reference to a class or function.
pub const R3Reference = struct {
    name: []const u8,
    module_name: ?[]const u8 = null,
};

/// R3ConstructorFactoryMetadata — metadata for a constructor-based factory.
/// Direct port of `R3ConstructorFactoryMetadata` interface in the TS source.
pub const R3ConstructorFactoryMetadata = struct {
    name: []const u8,
    type: R3Reference,
    type_argument_count: u32 = 0,
    deps: ?[]const R3DependencyMetadata = null,
    target: FactoryTarget,
    is_delegated: bool = false,
    delegate: ?[]const u8 = null,
    delegate_type: ?R3FactoryDelegateType = null,
    delegate_deps: ?[]const R3DependencyMetadata = null,
    expression: ?[]const u8 = null,
};

/// Compile a factory function.
/// Direct port of `compileFactoryFunction(...)` in the TS source.
///
/// Produces: `ɵɵdefineFactory({ type: ..., factory: () => new Type(deps...) })`
pub fn compileFactoryFunction(
    allocator: std.mem.Allocator,
    meta: R3ConstructorFactoryMetadata,
) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    try buf.appendSlice("ɵɵdefineFactory({ ");
    try buf.appendSlice("type: ");
    try buf.appendSlice(meta.type.name);
    try buf.appendSlice(", factory: () => ");

    if (meta.expression) |expr| {
        // Expression-based factory (useValue)
        try buf.appendSlice(expr);
    } else if (meta.is_delegated and meta.delegate != null) {
        // Delegated factory (useClass/useFactory)
        try buf.appendSlice(meta.delegate.?);
        try buf.append('(');
        if (meta.delegate_deps) |deps| {
            try emitDeps(allocator, &buf, deps);
        }
        try buf.append(')');
    } else if (meta.deps) |deps| {
        // Constructor-based factory
        try buf.appendSlice("new ");
        try buf.appendSlice(meta.type.name);
        try buf.append('(');
        try emitDeps(allocator, &buf, deps);
        try buf.append(')');
    } else {
        // No deps
        try buf.appendSlice("new ");
        try buf.appendSlice(meta.type.name);
        try buf.appendSlice("()");
    }

    try buf.appendSlice(" })");
    return buf.toOwnedSlice();
}

/// Emit dependency injection calls for a list of deps.
fn emitDeps(
    allocator: std.mem.Allocator,
    buf: *std.array_list.Managed(u8),
    deps: []const R3DependencyMetadata,
) !void {
    _ = allocator;
    for (deps, 0..) |dep, i| {
        if (i > 0) try buf.appendSlice(", ");
        if (dep.token) |token| {
            if (dep.optional) {
                try buf.appendSlice("inject(");
                try buf.appendSlice(token);
                try buf.appendSlice(", InjectFlags.Optional)");
            } else if (dep.host) {
                try buf.appendSlice("inject(");
                try buf.appendSlice(token);
                try buf.appendSlice(", InjectFlags.Host)");
            } else if (dep.skip_self) {
                try buf.appendSlice("inject(");
                try buf.appendSlice(token);
                try buf.appendSlice(", InjectFlags.SkipSelf)");
            } else {
                try buf.appendSlice("inject(");
                try buf.appendSlice(token);
                try buf.append(')');
            }
        } else {
            try buf.appendSlice("null");
        }
    }
}

/// Type with parameters — generates a type string with type arguments.
/// Direct port of `typeWithParameters(type, typeArgumentCount)` in the TS source.
pub fn typeWithParameters(
    allocator: std.mem.Allocator,
    type_name: []const u8,
    type_arg_count: u32,
) ![]const u8 {
    if (type_arg_count == 0) {
        return allocator.dupe(u8, type_name);
    }
    // e.g., `MyType<any, any, any>` for 3 type args
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();
    try buf.appendSlice(type_name);
    try buf.appendSlice("<any");
    var i: u32 = 1;
    while (i < type_arg_count) : (i += 1) {
        try buf.appendSlice(", any");
    }
    try buf.append('>');
    return buf.toOwnedSlice();
}

// ─── Tests ──────────────────────────────────────────────────

test "compileFactoryFunction no deps" {
    const allocator = std.testing.allocator;
    const meta = R3ConstructorFactoryMetadata{
        .name = "MyService",
        .type = .{ .name = "MyService" },
        .target = .Injectable,
    };
    const result = try compileFactoryFunction(allocator, meta);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "ɵɵdefineFactory") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "new MyService()") != null);
}

test "compileFactoryFunction with deps" {
    const allocator = std.testing.allocator;
    const deps = [_]R3DependencyMetadata{
        .{ .token = "Http" },
        .{ .token = "Config", .optional = true },
    };
    const meta = R3ConstructorFactoryMetadata{
        .name = "MyService",
        .type = .{ .name = "MyService" },
        .deps = &deps,
        .target = .Injectable,
    };
    const result = try compileFactoryFunction(allocator, meta);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "inject(Http)") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "InjectFlags.Optional") != null);
}

test "typeWithParameters" {
    const allocator = std.testing.allocator;
    const r0 = try typeWithParameters(allocator, "MyType", 0);
    defer allocator.free(r0);
    try std.testing.expectEqualStrings("MyType", r0);

    const r2 = try typeWithParameters(allocator, "MyType", 2);
    defer allocator.free(r2);
    try std.testing.expectEqualStrings("MyType<any, any>", r2);
}

test "FactoryTarget values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(FactoryTarget.Component));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(FactoryTarget.Pipe));
}

test "R3FactoryDelegateType values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(R3FactoryDelegateType.Class));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(R3FactoryDelegateType.Function));
}
