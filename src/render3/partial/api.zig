/// R3 Partial API — Partial declaration metadata interfaces
///
/// Port of: compiler/src/render3/partial/api.ts (607 LoC)
///
/// Defines the metadata interfaces for partial declarations — the data
/// structures that `ɵɵngDeclareComponent()`, `ɵɵngDeclareDirective()`, etc.
/// accept. These are used by the Angular linker to process compiled libraries.
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

/// R3PartialDeclaration — base interface for all partial declarations.
/// Direct port of `R3PartialDeclaration` interface in the TS source.
pub const R3PartialDeclaration = struct {
    /// The minimum version of the compiler that can process this declaration.
    min_version: []const u8,
    /// Version of the Angular compiler used to compile this declaration.
    version: []const u8,
    /// A reference to the `@angular/core` ES module.
    ng_import: []const u8,
    /// Reference to the decorated class.
    type: []const u8,
};

/// R3InputMapping — describes a single input on a directive/component.
/// Direct port of the input mapping type in the TS source.
pub const R3InputMapping = struct {
    class_property_name: []const u8,
    public_name: []const u8,
    is_signal: bool = false,
    is_required: bool = false,
    transform_function: ?[]const u8 = null,
};

/// R3HostBindings — host binding metadata for a directive/component.
/// Direct port of the `host` property in the TS source.
pub const R3HostBindings = struct {
    attributes: ?std.StringHashMap([]const u8) = null,
    listeners: ?std.StringHashMap([]const u8) = null,
    properties: ?std.StringHashMap([]const u8) = null,
    two_way_bindings: ?std.StringHashMap([]const u8) = null,
};

/// R3DeclareDirectiveMetadata — metadata for `ɵɵngDeclareDirective()`.
/// Direct port of `R3DeclareDirectiveMetadata` interface in the TS source.
pub const R3DeclareDirectiveMetadata = struct {
    base: R3PartialDeclaration,
    selector: ?[]const u8 = null,
    inputs: ?std.StringHashMap(R3InputMapping) = null,
    outputs: ?std.StringHashMap([]const u8) = null,
    host: ?R3HostBindings = null,
    export_as: ?[]const []const u8 = null,
    is_standalone: bool = false,
    is_signal: bool = false,
    queries: ?[]const R3QueryMetadata = null,
    view_queries: ?[]const R3QueryMetadata = null,
    uses_inheritance: bool = false,
    uses_on_changes: bool = false,
    ng_module_imports: ?[]const []const u8 = null,
    decorators: ?[]const []const u8 = null,
};

/// R3QueryMetadata — metadata for a content/view query.
pub const R3QueryMetadata = struct {
    property_name: []const u8,
    predicate: []const u8,
    descendants: bool = false,
    first: bool = false,
    read: ?[]const u8 = null,
    static: bool = false,
    is_signal: bool = false,
};

/// R3DeclareComponentMetadata — metadata for `ɵɵngDeclareComponent()`.
/// Direct port of `R3DeclareComponentMetadata` interface in the TS source.
pub const R3DeclareComponentMetadata = struct {
    base: R3PartialDeclaration,
    selector: ?[]const u8 = null,
    inputs: ?std.StringHashMap(R3InputMapping) = null,
    outputs: ?std.StringHashMap([]const u8) = null,
    host: ?R3HostBindings = null,
    export_as: ?[]const []const u8 = null,
    is_standalone: bool = false,
    is_signal: bool = false,
    queries: ?[]const R3QueryMetadata = null,
    view_queries: ?[]const R3QueryMetadata = null,
    uses_inheritance: bool = false,
    uses_on_changes: bool = false,
    ng_module_imports: ?[]const []const u8 = null,
    decorators: ?[]const []const u8 = null,
    template: []const u8 = "",
    decls: u32 = 0,
    vars: u32 = 0,
    encapsulation: u8 = 0,
    styles: ?[]const []const u8 = null,
    // Additional component-specific fields
    dependencies: ?[]const []const u8 = null,
    change_detection: u8 = 0,
    animations: ?[]const []const u8 = null,
    preserve_whitespaces: bool = false,
};

/// R3DeclarePipeMetadata — metadata for `ɵɵngDeclarePipe()`.
/// Direct port of `R3DeclarePipeMetadata` interface in the TS source.
pub const R3DeclarePipeMetadata = struct {
    base: R3PartialDeclaration,
    name: []const u8,
    pure: bool = true,
    is_standalone: bool = false,
};

/// R3DeclareInjectableMetadata — metadata for `ɵɵngDeclareInjectable()`.
/// Direct port of `R3DeclareInjectableMetadata` interface in the TS source.
pub const R3DeclareInjectableMetadata = struct {
    base: R3PartialDeclaration,
    token: ?[]const u8 = null,
    provided_in: ?[]const u8 = null,
    use_factory: ?[]const u8 = null,
    use_value: ?[]const u8 = null,
    use_class: ?[]const u8 = null,
    use_existing: ?[]const u8 = null,
    deps: ?[]const []const u8 = null,
};

/// R3DeclareNgModuleMetadata — metadata for `ɵɵngDeclareNgModule()`.
/// Direct port of `R3DeclareNgModuleMetadata` interface in the TS source.
pub const R3DeclareNgModuleMetadata = struct {
    base: R3PartialDeclaration,
    declarations: ?[]const []const u8 = null,
    imports: ?[]const []const u8 = null,
    exports: ?[]const []const u8 = null,
    bootstrap: ?[]const []const u8 = null,
    schemas: ?[]const []const u8 = null,
    is_standalone: bool = false,
    /// Unique ID or expression representing the unique ID of an NgModule.
    id: ?[]const u8 = null,
};

// ─── R3DeclareInjectorMetadata ─────────────────────────────

/// R3DeclareInjectorMetadata — metadata for `ɵɵngDeclareInjector()`.
/// Direct port of `R3DeclareInjectorMetadata` interface in the TS source.
pub const R3DeclareInjectorMetadata = struct {
    base: R3PartialDeclaration,
    providers: ?[]const []const u8 = null,
    imports: ?[]const []const u8 = null,
};

// ─── R3DeclareFactoryMetadata ──────────────────────────────

/// R3DeclareFactoryMetadata — metadata for `ɵɵngDeclareFactory()`.
/// Direct port of `R3DeclareFactoryMetadata` interface in the TS source.
pub const R3DeclareFactoryMetadata = struct {
    base: R3PartialDeclaration,
    /// Dependencies. Can be 'invalid' or null.
    deps_kind: DepsKind = .valid,
    deps: ?[]const R3DeclareDependencyMetadata = null,
    target: FactoryTarget,
};

/// DepsKind — kind of dependencies declaration.
pub const DepsKind = enum {
    valid,
    invalid,
    none,
};

// ─── R3DeclareDependencyMetadata ───────────────────────────

/// R3DeclareDependencyMetadata — metadata for a dependency.
/// Direct port of `R3DeclareDependencyMetadata` interface in the TS source.
pub const R3DeclareDependencyMetadata = struct {
    /// The token or value to be injected, or null if invalid.
    token: ?[]const u8 = null,
    /// Whether the dependency is an attribute value.
    attribute: bool = false,
    /// Whether the dependency has @Host qualifier.
    host: bool = false,
    /// Whether the dependency has @Optional qualifier.
    optional: bool = false,
    /// Whether the dependency has @Self qualifier.
    self: bool = false,
    /// Whether the dependency has @SkipSelf qualifier.
    skip_self: bool = false,
};

// ─── R3DeclareClassMetadata ────────────────────────────────

/// R3DeclareClassMetadata — metadata for `ɵɵngDeclareClassMetadata()`.
/// Direct port of `R3DeclareClassMetadata` interface in the TS source.
pub const R3DeclareClassMetadata = struct {
    base: R3PartialDeclaration,
    /// The Angular decorators of the class.
    decorators: []const u8,
    /// Constructor parameters (omitted if no constructor).
    ctor_parameters: ?[]const u8 = null,
    /// Property decorators (omitted if none).
    prop_decorators: ?[]const u8 = null,
};

// ─── R3DeclareClassMetadataAsync ───────────────────────────

/// R3DeclareClassMetadataAsync — metadata for `ɵɵngDeclareClassMetadataAsync()`.
/// Direct port of `R3DeclareClassMetadataAsync` interface in the TS source.
pub const R3DeclareClassMetadataAsync = struct {
    base: R3PartialDeclaration,
    /// Function that loads the deferred dependencies.
    resolve_deferred_deps: []const u8,
    /// Function that returns the class metadata.
    resolve_metadata: []const u8,
};

// ─── R3DeclareHostDirectiveMetadata ────────────────────────

/// R3DeclareHostDirectiveMetadata — metadata for a host directive.
/// Direct port of `R3DeclareHostDirectiveMetadata` interface in the TS source.
pub const R3DeclareHostDirectiveMetadata = struct {
    directive: []const u8,
    inputs: ?[]const []const u8 = null,
    outputs: ?[]const []const u8 = null,
};

// ─── R3DeclareServiceMetadata ──────────────────────────────

/// R3DeclareServiceMetadata — metadata for `ɵɵngDeclareService()`.
/// Direct port of `R3DeclareServiceMetadata` interface in the TS source.
pub const R3DeclareServiceMetadata = struct {
    base: R3PartialDeclaration,
    /// Whether the service should be provided automatically.
    auto_provided: bool = false,
    /// Factory function for creating instances.
    factory: ?[]const u8 = null,
};

// ─── R3DeclareDirectiveDependencyMetadata ──────────────────

/// R3DeclareDirectiveDependencyMetadata — directive/component dependency.
/// Direct port of `R3DeclareDirectiveDependencyMetadata` interface in the TS source.
pub const R3DeclareDirectiveDependencyMetadata = struct {
    kind: DirectiveDependencyKind = .directive,
    selector: []const u8 = "",
    type: []const u8,
    inputs: ?[]const []const u8 = null,
    outputs: ?[]const []const u8 = null,
    export_as: ?[]const []const u8 = null,
};

/// DirectiveDependencyKind — kind of directive dependency.
pub const DirectiveDependencyKind = enum {
    directive,
    component,
};

// ─── R3DeclarePipeDependencyMetadata ───────────────────────

/// R3DeclarePipeDependencyMetadata — pipe dependency.
/// Direct port of `R3DeclarePipeDependencyMetadata` interface in the TS source.
pub const R3DeclarePipeDependencyMetadata = struct {
    kind: []const u8 = "pipe",
    name: []const u8,
    type: []const u8,
};

// ─── R3DeclareNgModuleDependencyMetadata ───────────────────

/// R3DeclareNgModuleDependencyMetadata — NgModule dependency.
/// Direct port of `R3DeclareNgModuleDependencyMetadata` interface in the TS source.
pub const R3DeclareNgModuleDependencyMetadata = struct {
    kind: []const u8 = "ngmodule",
    type: []const u8,
};

// ─── R3DeclareQueryMetadata (expanded) ─────────────────────

/// R3DeclareQueryMetadata — metadata for a query in partial declarations.
/// Direct port of `R3DeclareQueryMetadata` interface in the TS source.
pub const R3DeclareQueryMetadata = struct {
    /// Name of the property on the class to update with query results.
    property_name: []const u8,
    /// Whether to read only the first matching result.
    first: bool = false,
    /// Predicate: either a type expression or string selectors.
    predicate_kind: PredicateKind = .string,
    predicate_string: []const u8 = "",
    predicate_strings: []const []const u8 = &.{},
    /// Whether to include only direct children or all descendants.
    descendants: bool = false,
    /// Whether to emit distinct changes only.
    emit_distinct_changes_only: bool = false,
    /// Type to read from each matched node, or null.
    read: ?[]const u8 = null,
    /// Whether the query collects only static results.
    static: bool = false,
    /// Whether the query is signal-based.
    is_signal: bool = false,
};

/// PredicateKind — kind of query predicate.
pub const PredicateKind = enum {
    string,
    expression,
};

// ─── ViewEncapsulation and ChangeDetectionStrategy ─────────

/// ViewEncapsulation — encapsulation modes for component styles.
pub const ViewEncapsulation = enum(u8) {
    Emulated = 0,
    Native = 1,
    ShadowDom = 2,
    None = 3,
};

/// ChangeDetectionStrategy — change detection strategies.
pub const ChangeDetectionStrategy = enum(u8) {
    Default = 0,
    OnPush = 1,
};

// ─── LegacyInputPartialMapping ─────────────────────────────

/// LegacyInputPartialMapping — legacy input mapping format.
/// Direct port of `LegacyInputPartialMapping` type in the TS source.
pub const LegacyInputPartialMapping = union(enum) {
    string: []const u8,
    tuple: struct {
        binding_property_name: []const u8,
        class_property_name: []const u8,
        transform_function: ?[]const u8 = null,
    },
};

// ─── Helper functions ───────────────────────────────────────

/// Convert FactoryTarget to string.
pub fn factoryTargetToString(t: FactoryTarget) []const u8 {
    return switch (t) {
        .Component => "Component",
        .Directive => "Directive",
        .Injectable => "Injectable",
        .Pipe => "Pipe",
        .NgModule => "NgModule",
        .Factory => "Factory",
    };
}

/// Convert ViewEncapsulation to string.
pub fn viewEncapsulationToString(e: ViewEncapsulation) []const u8 {
    return switch (e) {
        .Emulated => "Emulated",
        .Native => "Native",
        .ShadowDom => "ShadowDom",
        .None => "None",
    };
}

/// Convert ChangeDetectionStrategy to string.
pub fn changeDetectionStrategyToString(s: ChangeDetectionStrategy) []const u8 {
    return switch (s) {
        .Default => "Default",
        .OnPush => "OnPush",
    };
}

/// Convert DirectiveDependencyKind to string.
pub fn directiveDependencyKindToString(k: DirectiveDependencyKind) []const u8 {
    return switch (k) {
        .directive => "directive",
        .component => "component",
    };
}

/// Check if a partial declaration is standalone.
pub fn isStandalone(decl: *const R3DeclareDirectiveMetadata) bool {
    return decl.is_standalone;
}

/// Check if a partial declaration is signal-based.
pub fn isSignal(decl: *const R3DeclareDirectiveMetadata) bool {
    return decl.is_signal;
}

/// Get the selector of a directive declaration.
pub fn getSelector(decl: *const R3DeclareDirectiveMetadata) []const u8 {
    return decl.selector orelse "";
}

// ─── Tests ──────────────────────────────────────────────────

test "FactoryTarget values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(FactoryTarget.Component));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(FactoryTarget.Directive));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(FactoryTarget.Pipe));
}

test "R3PartialDeclaration defaults" {
    const decl = R3PartialDeclaration{
        .min_version = "14.0.0",
        .version = "16.0.0",
        .ng_import = "@angular/core",
        .type = "MyComp",
    };
    try std.testing.expectEqualStrings("14.0.0", decl.min_version);
    try std.testing.expectEqualStrings("MyComp", decl.type);
}

test "R3InputMapping defaults" {
    const input = R3InputMapping{
        .class_property_name = "myProp",
        .public_name = "myProp",
    };
    try std.testing.expect(!input.is_signal);
    try std.testing.expect(!input.is_required);
    try std.testing.expect(input.transform_function == null);
}

test "R3InputMapping with signal" {
    const input = R3InputMapping{
        .class_property_name = "count",
        .public_name = "count",
        .is_signal = true,
        .is_required = true,
    };
    try std.testing.expect(input.is_signal);
    try std.testing.expect(input.is_required);
}

test "R3DeclarePipeMetadata defaults" {
    const pipe = R3DeclarePipeMetadata{
        .base = .{
            .min_version = "14.0.0",
            .version = "16.0.0",
            .ng_import = "@angular/core",
            .type = "MyPipe",
        },
        .name = "myPipe",
    };
    try std.testing.expect(pipe.pure);
    try std.testing.expect(!pipe.is_standalone);
}

test "R3DeclareDirectiveMetadata defaults" {
    const dir = R3DeclareDirectiveMetadata{
        .base = .{
            .min_version = "14.0.0",
            .version = "16.0.0",
            .ng_import = "@angular/core",
            .type = "MyDir",
        },
    };
    try std.testing.expect(dir.selector == null);
    try std.testing.expect(!dir.is_standalone);
    try std.testing.expect(!dir.is_signal);
}

test "R3DeclareComponentMetadata defaults" {
    const comp = R3DeclareComponentMetadata{
        .base = .{
            .min_version = "14.0.0",
            .version = "16.0.0",
            .ng_import = "@angular/core",
            .type = "MyComp",
        },
    };
    try std.testing.expectEqualStrings("", comp.template);
    try std.testing.expectEqual(@as(u32, 0), comp.decls);
    try std.testing.expect(!comp.preserve_whitespaces);
}

test "R3DeclareInjectableMetadata defaults" {
    const inj = R3DeclareInjectableMetadata{
        .base = .{
            .min_version = "14.0.0",
            .version = "16.0.0",
            .ng_import = "@angular/core",
            .type = "MyService",
        },
    };
    try std.testing.expect(inj.token == null);
    try std.testing.expect(inj.provided_in == null);
}

test "R3DeclareNgModuleMetadata defaults" {
    const ngmod = R3DeclareNgModuleMetadata{
        .base = .{
            .min_version = "14.0.0",
            .version = "16.0.0",
            .ng_import = "@angular/core",
            .type = "MyModule",
        },
    };
    try std.testing.expect(ngmod.declarations == null);
    try std.testing.expect(ngmod.id == null);
}

test "R3DeclareInjectorMetadata defaults" {
    const inj = R3DeclareInjectorMetadata{
        .base = .{
            .min_version = "14.0.0",
            .version = "16.0.0",
            .ng_import = "@angular/core",
            .type = "MyInjector",
        },
    };
    try std.testing.expect(inj.providers == null);
    try std.testing.expect(inj.imports == null);
}

test "R3DeclareFactoryMetadata defaults" {
    const fac = R3DeclareFactoryMetadata{
        .base = .{
            .min_version = "14.0.0",
            .version = "16.0.0",
            .ng_import = "@angular/core",
            .type = "MyFactory",
        },
        .target = .Component,
    };
    try std.testing.expectEqual(FactoryTarget.Component, fac.target);
    try std.testing.expectEqual(DepsKind.valid, fac.deps_kind);
}

test "R3DeclareDependencyMetadata defaults" {
    const dep = R3DeclareDependencyMetadata{};
    try std.testing.expect(dep.token == null);
    try std.testing.expect(!dep.attribute);
    try std.testing.expect(!dep.host);
    try std.testing.expect(!dep.optional);
    try std.testing.expect(!dep.self);
    try std.testing.expect(!dep.skip_self);
}

test "R3DeclareDependencyMetadata with all flags" {
    const dep = R3DeclareDependencyMetadata{
        .token = "MyService",
        .attribute = true,
        .host = true,
        .optional = true,
        .self = true,
        .skip_self = true,
    };
    try std.testing.expectEqualStrings("MyService", dep.token.?);
    try std.testing.expect(dep.attribute);
    try std.testing.expect(dep.host);
    try std.testing.expect(dep.optional);
    try std.testing.expect(dep.self);
    try std.testing.expect(dep.skip_self);
}

test "R3DeclareClassMetadata defaults" {
    const cm = R3DeclareClassMetadata{
        .base = .{
            .min_version = "14.0.0",
            .version = "16.0.0",
            .ng_import = "@angular/core",
            .type = "MyClass",
        },
        .decorators = "[]",
    };
    try std.testing.expectEqualStrings("[]", cm.decorators);
    try std.testing.expect(cm.ctor_parameters == null);
}

test "R3DeclareClassMetadataAsync defaults" {
    const cma = R3DeclareClassMetadataAsync{
        .base = .{
            .min_version = "14.0.0",
            .version = "16.0.0",
            .ng_import = "@angular/core",
            .type = "MyClass",
        },
        .resolve_deferred_deps = "fn()",
        .resolve_metadata = "fn()",
    };
    try std.testing.expectEqualStrings("fn()", cma.resolve_deferred_deps);
}

test "R3DeclareHostDirectiveMetadata defaults" {
    const hd = R3DeclareHostDirectiveMetadata{
        .directive = "MyHostDir",
    };
    try std.testing.expectEqualStrings("MyHostDir", hd.directive);
    try std.testing.expect(hd.inputs == null);
    try std.testing.expect(hd.outputs == null);
}

test "R3DeclareServiceMetadata defaults" {
    const svc = R3DeclareServiceMetadata{
        .base = .{
            .min_version = "14.0.0",
            .version = "16.0.0",
            .ng_import = "@angular/core",
            .type = "MyService",
        },
    };
    try std.testing.expect(!svc.auto_provided);
    try std.testing.expect(svc.factory == null);
}

test "R3DeclareDirectiveDependencyMetadata defaults" {
    const dep = R3DeclareDirectiveDependencyMetadata{
        .type = "NgIf",
        .selector = "[ngIf]",
    };
    try std.testing.expectEqual(DirectiveDependencyKind.directive, dep.kind);
    try std.testing.expectEqualStrings("[ngIf]", dep.selector);
}

test "R3DeclarePipeDependencyMetadata defaults" {
    const dep = R3DeclarePipeDependencyMetadata{
        .name = "date",
        .type = "DatePipe",
    };
    try std.testing.expectEqualStrings("pipe", dep.kind);
    try std.testing.expectEqualStrings("date", dep.name);
}

test "R3DeclareNgModuleDependencyMetadata defaults" {
    const dep = R3DeclareNgModuleDependencyMetadata{
        .type = "CommonModule",
    };
    try std.testing.expectEqualStrings("ngmodule", dep.kind);
}

test "R3DeclareQueryMetadata defaults" {
    const q = R3DeclareQueryMetadata{
        .property_name = "items",
    };
    try std.testing.expect(!q.first);
    try std.testing.expect(!q.descendants);
    try std.testing.expect(!q.is_signal);
    try std.testing.expectEqual(PredicateKind.string, q.predicate_kind);
}

test "ViewEncapsulation values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(ViewEncapsulation.Emulated));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(ViewEncapsulation.None));
}

test "ChangeDetectionStrategy values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(ChangeDetectionStrategy.Default));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(ChangeDetectionStrategy.OnPush));
}

test "DepsKind values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(DepsKind.valid));
}

test "PredicateKind values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(PredicateKind.string));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(PredicateKind.expression));
}

test "factoryTargetToString" {
    try std.testing.expectEqualStrings("Component", factoryTargetToString(.Component));
    try std.testing.expectEqualStrings("Directive", factoryTargetToString(.Directive));
    try std.testing.expectEqualStrings("Injectable", factoryTargetToString(.Injectable));
    try std.testing.expectEqualStrings("Pipe", factoryTargetToString(.Pipe));
    try std.testing.expectEqualStrings("NgModule", factoryTargetToString(.NgModule));
    try std.testing.expectEqualStrings("Factory", factoryTargetToString(.Factory));
}

test "viewEncapsulationToString" {
    try std.testing.expectEqualStrings("Emulated", viewEncapsulationToString(.Emulated));
    try std.testing.expectEqualStrings("ShadowDom", viewEncapsulationToString(.ShadowDom));
    try std.testing.expectEqualStrings("None", viewEncapsulationToString(.None));
}

test "changeDetectionStrategyToString" {
    try std.testing.expectEqualStrings("Default", changeDetectionStrategyToString(.Default));
    try std.testing.expectEqualStrings("OnPush", changeDetectionStrategyToString(.OnPush));
}

test "directiveDependencyKindToString" {
    try std.testing.expectEqualStrings("directive", directiveDependencyKindToString(.directive));
    try std.testing.expectEqualStrings("component", directiveDependencyKindToString(.component));
}

test "isStandalone — false by default" {
    const dir = R3DeclareDirectiveMetadata{
        .base = .{
            .min_version = "14.0.0",
            .version = "16.0.0",
            .ng_import = "@angular/core",
            .type = "MyDir",
        },
    };
    try std.testing.expect(!isStandalone(&dir));
}

test "isStandalone — true when set" {
    const dir = R3DeclareDirectiveMetadata{
        .base = .{
            .min_version = "14.0.0",
            .version = "16.0.0",
            .ng_import = "@angular/core",
            .type = "MyDir",
        },
        .is_standalone = true,
    };
    try std.testing.expect(isStandalone(&dir));
}

test "isSignal — false by default" {
    const dir = R3DeclareDirectiveMetadata{
        .base = .{
            .min_version = "14.0.0",
            .version = "16.0.0",
            .ng_import = "@angular/core",
            .type = "MyDir",
        },
    };
    try std.testing.expect(!isSignal(&dir));
}

test "getSelector — returns empty when null" {
    const dir = R3DeclareDirectiveMetadata{
        .base = .{
            .min_version = "14.0.0",
            .version = "16.0.0",
            .ng_import = "@angular/core",
            .type = "MyDir",
        },
    };
    try std.testing.expectEqualStrings("", getSelector(&dir));
}

test "getSelector — returns selector" {
    const dir = R3DeclareDirectiveMetadata{
        .base = .{
            .min_version = "14.0.0",
            .version = "16.0.0",
            .ng_import = "@angular/core",
            .type = "MyDir",
        },
        .selector = "[appDir]",
    };
    try std.testing.expectEqualStrings("[appDir]", getSelector(&dir));
}

test "R3HostBindings defaults" {
    const hb = R3HostBindings{};
    try std.testing.expect(hb.attributes == null);
    try std.testing.expect(hb.listeners == null);
}

test "R3QueryMetadata defaults" {
    const q = R3QueryMetadata{
        .property_name = "items",
        .predicate = "Item",
    };
    try std.testing.expect(!q.first);
    try std.testing.expect(!q.descendants);
    try std.testing.expect(!q.is_signal);
}

test "LegacyInputPartialMapping — string variant" {
    const m = LegacyInputPartialMapping{ .string = "myProp" };
    try std.testing.expectEqualStrings("myProp", m.string);
}

test "LegacyInputPartialMapping — tuple variant" {
    const m = LegacyInputPartialMapping{ .tuple = .{
        .binding_property_name = "myProp",
        .class_property_name = "myProp",
    } };
    try std.testing.expectEqualStrings("myProp", m.tuple.binding_property_name);
    try std.testing.expect(m.tuple.transform_function == null);
}
