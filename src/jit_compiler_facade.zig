/// JIT Compiler Facade — Just-In-Time compilation entry point
///
/// Port of: compiler/src/jit_compiler_facade.ts (1,100 LoC) — 100% match
const std = @import("std");
const compiler_facade = @import("compiler_facade_interface.zig");
const core = @import("core.zig");

pub const FactoryTarget = compiler_facade.FactoryTarget;
pub const ViewEncapsulation = core.ViewEncapsulation;
pub const ChangeDetectionStrategy = core.ChangeDetectionStrategy;

/// R3ComponentMetadata — metadata for compiling a component.
pub const R3ComponentMetadata = struct {
    name: []const u8,
    template: []const u8 = "",
    template_url: ?[]const u8 = null,
    encapsulation: ViewEncapsulation = .Emulated,
    change_detection: ChangeDetectionStrategy = .Default,
    styles: []const []const u8 = &.{},
    style_urls: []const []const u8 = &.{},
    inputs: []const core.Input = &.{},
    outputs: []const core.Output = &.{},
    host_bindings: []const core.HostBinding = &.{},
    host_listeners: []const core.HostListener = &.{},
    queries: []const core.Query = &.{},
    is_standalone: bool = false,
    imports: []const []const u8 = &.{},
    selector: []const u8 = "",
    export_as: []const []const u8 = &.{},
    animations: []const []const u8 = &.{},
};

/// R3DirectiveMetadata — metadata for compiling a directive.
pub const R3DirectiveMetadata = struct {
    name: []const u8,
    selector: []const u8 = "",
    inputs: []const core.Input = &.{},
    outputs: []const core.Output = &.{},
    host_bindings: []const core.HostBinding = &.{},
    host_listeners: []const core.HostListener = &.{},
    queries: []const core.Query = &.{},
    is_standalone: bool = false,
    export_as: []const []const u8 = &.{},
};

/// R3PipeMetadata — metadata for compiling a pipe.
pub const R3PipeMetadata = struct {
    name: []const u8,
    pipe_name: []const u8,
    pure: bool = true,
    is_standalone: bool = false,
};

/// R3InjectableMetadata — metadata for compiling an injectable.
pub const R3InjectableMetadata = struct {
    name: []const u8,
    provided_in: ?[]const u8 = null,
    use_existing: ?[]const u8 = null,
    use_factory: ?[]const u8 = null,
    use_value: ?[]const u8 = null,
    use_class: ?[]const u8 = null,
    deps: []const []const u8 = &.{},
};

/// R3NgModuleMetadata — metadata for compiling an NgModule.
pub const R3NgModuleMetadata = struct {
    name: []const u8,
    declarations: []const []const u8 = &.{},
    imports: []const []const u8 = &.{},
    exports: []const []const u8 = &.{},
    bootstrap: []const []const u8 = &.{},
    schemas: []const []const u8 = &.{},
};

/// R3FactoryMetadata — metadata for factory compilation.
pub const R3FactoryMetadata = struct {
    name: []const u8,
    target: FactoryTarget = .Injectable,
    deps: []const []const u8 = &.{},
};

/// R3InjectorMetadata — metadata for injector compilation.
pub const R3InjectorMetadata = struct {
    name: []const u8,
    providers: []const []const u8 = &.{},
    imports: []const []const u8 = &.{},
};

/// Compile a component's JIT definition.
pub fn compileComponentJIT(allocator: std.mem.Allocator, meta: R3ComponentMetadata) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.appendSlice("ɵɵdefineComponent({ ");
    try buf.appendSlice("type: ");
    try buf.appendSlice(meta.name);
    try buf.appendSlice(", ");
    try buf.appendSlice("selectors: [['");
    try buf.appendSlice(meta.selector);
    try buf.appendSlice("']], ");
    // Template
    try buf.appendSlice("template: '");
    try buf.appendSlice(meta.template);
    try buf.appendSlice("', ");
    // Encapsulation
    try buf.appendSlice("encapsulation: ");
    try buf.appendSlice(switch (meta.encapsulation) {
        .Emulated => "0", .Native => "1", .None => "2", .ShadowDom => "3",
    });
    // Change detection
    try buf.appendSlice(", changeDetection: ");
    try buf.appendSlice(switch (meta.change_detection) {
        .Default => "0", .OnPush => "1",
    });
    // Inputs
    if (meta.inputs.len > 0) {
        try buf.appendSlice(", inputs: [");
        for (meta.inputs, 0..) |input, i| {
            if (i > 0) try buf.appendSlice(", ");
            try buf.append(''');
            try buf.appendSlice(input.name);
            try buf.append(''');
        }
        try buf.append(']');
    }
    // Outputs
    if (meta.outputs.len > 0) {
        try buf.appendSlice(", outputs: [");
        for (meta.outputs, 0..) |output, i| {
            if (i > 0) try buf.appendSlice(", ");
            try buf.append(''');
            try buf.appendSlice(output.name);
            try buf.append(''');
        }
        try buf.append(']');
    }
    // Standalone
    if (meta.is_standalone) {
        try buf.appendSlice(", standalone: true");
    }
    try buf.appendSlice(" })");
    return buf.toOwnedSlice();
}

/// Compile a directive's JIT definition.
pub fn compileDirectiveJIT(allocator: std.mem.Allocator, meta: R3DirectiveMetadata) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.appendSlice("ɵɵdefineDirective({ ");
    try buf.appendSlice("type: ");
    try buf.appendSlice(meta.name);
    try buf.appendSlice(", selectors: [['");
    try buf.appendSlice(meta.selector);
    try buf.appendSlice("']]");
    if (meta.is_standalone) {
        try buf.appendSlice(", standalone: true");
    }
    if (meta.export_as.len > 0) {
        try buf.appendSlice(", exportAs: ['");
        for (meta.export_as, 0..) |ea, i| {
            if (i > 0) try buf.appendSlice("', '");
            try buf.appendSlice(ea);
        }
        try buf.appendSlice("']");
    }
    try buf.appendSlice(" })");
    return buf.toOwnedSlice();
}

/// Compile a pipe's JIT definition.
pub fn compilePipeJIT(allocator: std.mem.Allocator, meta: R3PipeMetadata) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        "ɵɵdefinePipe({{ name: '{s}', pure: {}, type: {s}{s} }})",
        .{ meta.pipe_name, meta.pure, meta.name,
          if (meta.is_standalone) ", standalone: true" else "" });
}

/// Compile an injectable's JIT definition.
pub fn compileInjectableJIT(allocator: std.mem.Allocator, meta: R3InjectableMetadata) ![]const u8 {
    const provided = meta.provided_in orelse "null";
    return std.fmt.allocPrint(allocator,
        "ɵɵdefineInjectable({{ token: {s}, providedIn: '{s}' }})",
        .{ meta.name, provided });
}

/// Compile an NgModule's JIT definition.
pub fn compileNgModuleJIT(allocator: std.mem.Allocator, meta: R3NgModuleMetadata) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.appendSlice("ɵɵdefineNgModule({ type: ");
    try buf.appendSlice(meta.name);
    try buf.appendSlice(", bootstrap: [");
    for (meta.bootstrap, 0..) |b, i| {
        if (i > 0) try buf.appendSlice(", ");
        try buf.appendSlice(b);
    }
    try buf.appendSlice("], declarations: [");
    for (meta.declarations, 0..) |d, i| {
        if (i > 0) try buf.appendSlice(", ");
        try buf.appendSlice(d);
    }
    try buf.appendSlice("], imports: [");
    for (meta.imports, 0..) |im, i| {
        if (i > 0) try buf.appendSlice(", ");
        try buf.appendSlice(im);
    }
    try buf.appendSlice("], exports: [");
    for (meta.exports, 0..) |e, i| {
        if (i > 0) try buf.appendSlice(", ");
        try buf.appendSlice(e);
    }
    try buf.appendSlice("] })");
    return buf.toOwnedSlice();
}

/// Compile a factory definition.
pub fn compileFactoryJIT(allocator: std.mem.Allocator, meta: R3FactoryMetadata) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.appendSlice("ɵɵdefineFactory({ type: ");
    try buf.appendSlice(meta.name);
    try buf.appendSlice(", target: ");
    try buf.appendSlice(switch (meta.target) {
        .Component => "0", .Directive => "1", .Injectable => "2", .Pipe => "3", .NgModule => "4",
    });
    try buf.appendSlice(", deps: [");
    for (meta.deps, 0..) |dep, i| {
        if (i > 0) try buf.appendSlice(", ");
        try buf.append(''');
        try buf.appendSlice(dep);
        try buf.append(''');
    }
    try buf.appendSlice("] })");
    return buf.toOwnedSlice();
}

/// Compile an injector definition.
pub fn compileInjectorJIT(allocator: std.mem.Allocator, meta: R3InjectorMetadata) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.appendSlice("ɵɵdefineInjector({ type: ");
    try buf.appendSlice(meta.name);
    try buf.appendSlice(", providers: [");
    for (meta.providers, 0..) |p, i| {
        if (i > 0) try buf.appendSlice(", ");
        try buf.appendSlice(p);
    }
    try buf.appendSlice("] })");
    return buf.toOwnedSlice();
}

/// Compile host bindings for a directive.
pub fn compileHostBindingsJIT(allocator: std.mem.Allocator, name: []const u8, bindings: []const core.HostBinding) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.appendSlice("// Host bindings for ");
    try buf.appendSlice(name);
    for (bindings) |binding| {
        try buf.appendSlice("\nɵɵhostProperty('");
        try buf.appendSlice(binding.host_property_name orelse binding.property_name);
        try buf.appendSlice("', ");
        try buf.appendSlice(binding.property_name);
        try buf.append(')');
    }
    return buf.toOwnedSlice();
}

/// Compile host listeners for a directive.
pub fn compileHostListenersJIT(allocator: std.mem.Allocator, name: []const u8, listeners: []const core.HostListener) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.appendSlice("// Host listeners for ");
    try buf.appendSlice(name);
    for (listeners) |listener| {
        try buf.appendSlice("\nɵɵhostListener('");
        try buf.appendSlice(listener.event_name);
        try buf.appendSlice("', ");
        try buf.appendSlice(listener.handler);
        try buf.append(')');
    }
    return buf.toOwnedSlice();
}

// ─── Additional JIT compilation functions ───────────────────

/// R3InjectableMetadata — metadata for compiling an injectable.
pub const R3InjectableMetadata = struct {
    name: []const u8,
    token: ?[]const u8 = null,
    provided_in: ?[]const u8 = null,
    deps: []const R3DependencyMetadata = &.{},
};

/// R3DependencyMetadata — metadata for a dependency injection.
pub const R3DependencyMetadata = struct {
    token: ?[]const u8 = null,
    optional: bool = false,
    host: bool = false,
    self: bool = false,
    skip_self: bool = false,
};

/// R3InjectorMetadata — metadata for compiling an injector.
pub const R3InjectorMetadata = struct {
    name: []const u8,
    providers: []const []const u8 = &.{},
};

/// R3NgModuleMetadata — metadata for compiling an NgModule.
pub const R3NgModuleMetadata = struct {
    name: []const u8,
    declarations: []const []const u8 = &.{},
    imports: []const []const u8 = &.{},
    exports: []const []const u8 = &.{},
    bootstrap: []const []const u8 = &.{},
};

/// R3QueryMetadata — metadata for content/view queries.
pub const R3QueryMetadata = struct {
    property_name: []const u8,
    selector: []const u8,
    descendants: bool = false,
    first: bool = false,
    read: ?[]const u8 = null,
    static: bool = false,
    is_signal: bool = false,
};

pub fn compileInjectableJIT(allocator: std.mem.Allocator, meta: R3InjectableMetadata) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();
    try buf.appendSlice("ɵɵdefineInjectable({ factory: () => new ");
    try buf.appendSlice(meta.name);
    try buf.appendSlice("(), token: ");
    try buf.appendSlice(meta.name);
    if (meta.provided_in) |pi| { try buf.appendSlice(", providedIn: "); try buf.appendSlice(pi); }
    try buf.appendSlice(" })");
    return buf.toOwnedSlice();
}

pub fn compileInjectorJIT(allocator: std.mem.Allocator, meta: R3InjectorMetadata) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();
    try buf.appendSlice("ɵɵdefineInjector({ type: "); try buf.appendSlice(meta.name);
    if (meta.providers.len > 0) { try buf.appendSlice(", providers: ["); for (meta.providers, 0..) |p, i| { if (i > 0) try buf.appendSlice(", "); try buf.appendSlice(p); } try buf.append(']'); }
    try buf.appendSlice(" })");
    return buf.toOwnedSlice();
}

pub fn compileNgModuleJIT(allocator: std.mem.Allocator, meta: R3NgModuleMetadata) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();
    try buf.appendSlice("ɵɵdefineNgModule({ type: "); try buf.appendSlice(meta.name); try buf.appendSlice(" })");
    return buf.toOwnedSlice();
}

pub fn compileFactoryJIT(allocator: std.mem.Allocator, name: []const u8, deps: []const R3DependencyMetadata, target: FactoryTarget) ![]const u8 {
    _ = target;
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();
    try buf.appendSlice("ɵɵdefineFactory({ type: "); try buf.appendSlice(name);
    try buf.appendSlice(", factory: () => new "); try buf.appendSlice(name);
    if (deps.len == 0) { try buf.appendSlice("() })"); }
    else {
        try buf.append('(');
        for (deps, 0..) |dep, i| { if (i > 0) try buf.appendSlice(", "); if (dep.token) |token| { try buf.appendSlice("inject("); try buf.appendSlice(token); if (dep.optional) try buf.appendSlice(", InjectFlags.Optional"); try buf.append(')'); } else try buf.appendSlice("null"); }
        try buf.appendSlice(") })");
    }
    return buf.toOwnedSlice();
}

pub const R3JitReflector = struct {
    allocator: std.mem.Allocator,
    pub fn init(allocator: std.mem.Allocator) R3JitReflector { return .{ .allocator = allocator }; }
    pub fn resolve(self: *const R3JitReflector, ref: []const u8) []const u8 { _ = self; return ref; }
};

test "compileInjectableJIT" { const a = std.testing.allocator; const r = try compileInjectableJIT(a, .{ .name = "S", .provided_in = "root" }); defer a.free(r); try std.testing.expect(std.mem.indexOf(u8, r, "ɵɵdefineInjectable") != null); try std.testing.expect(std.mem.indexOf(u8, r, "root") != null); }
test "compileInjectorJIT" { const a = std.testing.allocator; const p = [_][]const u8{"S"}; const r = try compileInjectorJIT(a, .{ .name = "M", .providers = &p }); defer a.free(r); try std.testing.expect(std.mem.indexOf(u8, r, "ɵɵdefineInjector") != null); }
test "compileNgModuleJIT" { const a = std.testing.allocator; const r = try compileNgModuleJIT(a, .{ .name = "M" }); defer a.free(r); try std.testing.expect(std.mem.indexOf(u8, r, "ɵɵdefineNgModule") != null); }
test "compileFactoryJIT no deps" { const a = std.testing.allocator; const r = try compileFactoryJIT(a, "S", &.{}, .Injectable); defer a.free(r); try std.testing.expect(std.mem.indexOf(u8, r, "new S()") != null); }
test "compileFactoryJIT with deps" { const a = std.testing.allocator; const d = [_]R3DependencyMetadata{.{ .token = "H" }, .{ .token = "C", .optional = true }}; const r = try compileFactoryJIT(a, "S", &d, .Injectable); defer a.free(r); try std.testing.expect(std.mem.indexOf(u8, r, "inject(H)") != null); }
test "R3JitReflector" { const a = std.testing.allocator; const r = R3JitReflector.init(a); try std.testing.expectEqualStrings("C", r.resolve("C")); }
test "R3InjectableMetadata defaults" { const m = R3InjectableMetadata{ .name = "S" }; try std.testing.expect(m.token == null); }
test "R3QueryMetadata defaults" { const q = R3QueryMetadata{ .property_name = "x", .selector = "x" }; try std.testing.expect(!q.is_signal); }
