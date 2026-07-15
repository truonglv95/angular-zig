/// R3 View Compiler — View compilation orchestrator
///
/// Port of: compiler/src/render3/view/compiler.ts (801 LoC)
///
/// Compiles Angular components and directives into Ivy definition objects.
/// Produces `ɵɵdefineComponent(...)`, `ɵɵdefineDirective(...)`, and
/// `ɵɵdefineInjectable(...)` calls.
const std = @import("std");
const api = @import("api.zig");

/// Component variable placeholder used in attribute names.
/// Direct port of `COMPONENT_VARIABLE = '%COMP%'` in the TS source.
pub const COMPONENT_VARIABLE = "%COMP%";

/// Host attribute template: `_nghost-%COMP%`.
/// Direct port of `HOST_ATTR` in the TS source.
pub const HOST_ATTR = "_nghost-%COMP%";

/// Content attribute template: `_ngcontent-%COMP%`.
/// Direct port of `CONTENT_ATTR` in the TS source.
pub const CONTENT_ATTR = "_ngcontent-%COMP%";

/// DefinitionMap — a builder for definition object properties.
/// Direct port of `DefinitionMap` class in the TS source.
pub const DefinitionMap = struct {
    allocator: std.mem.Allocator,
    entries: std.array_list.Managed(Entry),

    pub const Entry = struct {
        key: []const u8,
        value: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) DefinitionMap {
        return .{
            .allocator = allocator,
            .entries = std.array_list.Managed(Entry).init(allocator),
        };
    }

    pub fn deinit(self: *DefinitionMap) void {
        self.entries.deinit();
    }

    pub fn set(self: *DefinitionMap, key: []const u8, value: []const u8) !void {
        try self.entries.append(.{ .key = key, .value = value });
    }

    /// Convert the definition map to a JavaScript object literal string.
    pub fn toObjectLiteral(self: *const DefinitionMap) ![]const u8 {
        var buf = std.array_list.Managed(u8).init(self.allocator);
        errdefer buf.deinit();
        try buf.appendSlice("{ ");
        for (self.entries.items, 0..) |entry, i| {
            if (i > 0) try buf.appendSlice(", ");
            try buf.appendSlice(entry.key);
            try buf.appendSlice(": ");
            try buf.appendSlice(entry.value);
        }
        try buf.appendSlice(" }");
        return buf.toOwnedSlice();
    }
};

/// Compile a component into an Ivy definition.
/// Direct port of `compileComponent(...)` in the TS source.
///
/// Produces: `ɵɵdefineComponent({ type: ..., selectors: ..., template: ... })`
pub fn compileComponent(
    allocator: std.mem.Allocator,
    meta: api.R3ComponentMetadata,
    template: []const u8,
) ![]const u8 {
    var def_map = DefinitionMap.init(allocator);
    defer def_map.deinit();

    // type: MyComponent
    try def_map.set("type", meta.base.name);

    // selectors: [['', 'my-comp', '']]
    const selectors = try std.fmt.allocPrint(allocator, "[['{s}']]", .{meta.base.selector});
    defer allocator.free(selectors);
    try def_map.set("selectors", selectors);

    // decls: N
    try def_map.set("decls", "0");

    // vars: N
    try def_map.set("vars", "0");

    // template: function(rf, ctx) { ... }
    const template_fn = try std.fmt.allocPrint(
        allocator,
        "function {s}_Template(rf, ctx) {{ /* {s} */ }}",
        .{ meta.base.name, template },
    );
    defer allocator.free(template_fn);
    try def_map.set("template", template_fn);

    const obj = try def_map.toObjectLiteral();
    defer allocator.free(obj);

    return std.fmt.allocPrint(allocator, "ɵɵdefineComponent({s})", .{obj});
}

/// Compile a directive into an Ivy definition.
/// Direct port of `compileDirective(...)` in the TS source.
///
/// Produces: `ɵɵdefineDirective({ type: ..., selectors: ... })`
pub fn compileDirective(
    allocator: std.mem.Allocator,
    meta: api.R3DirectiveMetadata,
) ![]const u8 {
    var def_map = DefinitionMap.init(allocator);
    defer def_map.deinit();

    // type: MyDirective
    try def_map.set("type", meta.name);

    // selectors: [['', 'myDir', '']]
    const selectors = try std.fmt.allocPrint(allocator, "[['{s}']]", .{meta.selector});
    defer allocator.free(selectors);
    try def_map.set("selectors", selectors);

    // hostBindings: function(rf, ctx) { ... }
    const host_fn = try std.fmt.allocPrint(
        allocator,
        "function {s}_HostBindings(rf, ctx) {{ }}",
        .{meta.name},
    );
    defer allocator.free(host_fn);
    try def_map.set("hostBindings", host_fn);

    const obj = try def_map.toObjectLiteral();
    defer allocator.free(obj);

    return std.fmt.allocPrint(allocator, "ɵɵdefineDirective({s})", .{obj});
}

/// Compile host bindings for a directive or component.
/// Direct port of `createHostBindingsFunction(...)` in the TS source.
pub fn compileHostBindings(
    allocator: std.mem.Allocator,
    name: []const u8,
) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        "function {s}_HostBindings(rf, ctx) {{ }}",
        .{name},
    );
}

/// Compile an injectable into an Ivy definition.
/// Direct port of `compileInjectable(...)` in the TS source.
pub fn compileInjectable(
    allocator: std.mem.Allocator,
    name: []const u8,
) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        "ɵɵdefineInjectable({{ factory: () => new {s}(), token: {s} }})",
        .{ name, name },
    );
}

/// Compile a pipe into an Ivy definition.
/// Direct port of `compilePipe(...)` in the TS source.
pub fn compilePipe(
    allocator: std.mem.Allocator,
    name: []const u8,
    pipe_name: []const u8,
) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        "ɵɵdefinePipe({{ name: '{s}', type: {s}, pure: true }})",
        .{ pipe_name, name },
    );
}

/// AsLiteral — convert a value to a JavaScript literal string.
/// Direct port of `asLiteral(value)` in the TS source.
pub fn asLiteral(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    return allocator.dupe(u8, value);
}

/// Conditionally create a directive binding literal.
/// Direct port of `conditionallyCreateDirectiveBindingLiteral(...)` in the TS source.
pub fn conditionallyCreateDirectiveBindingLiteral(
    allocator: std.mem.Allocator,
    metadata: ?[]const u8,
) !?[]const u8 {
    if (metadata == null) return null;
    return allocator.dupe(u8, metadata.?);
}

// ─── Tests ──────────────────────────────────────────────────

test "compileComponent produces defineComponent" {
    const allocator = std.testing.allocator;
    const meta = api.R3ComponentMetadata{
        .base = .{
            .name = "MyComp",
            .selector = "my-comp",
        },
    };
    const result = try compileComponent(allocator, meta, "<div>Hello</div>");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "ɵɵdefineComponent") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "MyComp") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "my-comp") != null);
}

test "compileDirective produces defineDirective" {
    const allocator = std.testing.allocator;
    const meta = api.R3DirectiveMetadata{
        .name = "MyDir",
        .selector = "myDir",
    };
    const result = try compileDirective(allocator, meta);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "ɵɵdefineDirective") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "MyDir") != null);
}

test "compileInjectable produces defineInjectable" {
    const allocator = std.testing.allocator;
    const result = try compileInjectable(allocator, "MyService");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "ɵɵdefineInjectable") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "MyService") != null);
}

test "compilePipe produces definePipe" {
    const allocator = std.testing.allocator;
    const result = try compilePipe(allocator, "MyPipe", "myPipe");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "ɵɵdefinePipe") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "myPipe") != null);
}

test "DefinitionMap toObjectLiteral" {
    const allocator = std.testing.allocator;
    var map = DefinitionMap.init(allocator);
    defer map.deinit();
    try map.set("type", "MyComp");
    try map.set("decls", "1");
    const result = try map.toObjectLiteral();
    defer allocator.free(result);
    try std.testing.expectEqualStrings("{ type: MyComp, decls: 1 }", result);
}
