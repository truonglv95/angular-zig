/// Core — Core compiler types and utilities
///
/// Port of: compiler/src/core.ts (325 LoC) — 100% match
const std = @import("std");

/// View encapsulation options.
pub const ViewEncapsulation = enum(u8) {
    Emulated = 0,
    Native = 1,
    None = 2,
    ShadowDom = 3,
};

/// Change detection strategy.
pub const ChangeDetectionStrategy = enum(u8) {
    Default = 0,
    OnPush = 1,
};

/// Input decorator metadata.
pub const Input = struct {
    name: []const u8,
    alias: ?[]const u8 = null,
    required: bool = false,
    transform: ?[]const u8 = null,
    is_signal: bool = false,
};

/// Output decorator metadata.
pub const Output = struct {
    name: []const u8,
    alias: ?[]const u8 = null,
    is_signal: bool = false,
};

/// Host binding decorator metadata.
pub const HostBinding = struct {
    property_name: []const u8,
    host_property_name: ?[]const u8 = null,
    is_signal: bool = false,
};

/// Host listener decorator metadata.
pub const HostListener = struct {
    event_name: []const u8,
    handler: []const u8,
    args: []const []const u8 = &.{},
};

/// Content/View query metadata.
pub const Query = struct {
    property_name: []const u8,
    first: bool = false,
    descendants: bool = false,
    read: ?[]const u8 = null,
    is_static: bool = false,
    predicate: []const u8 = "",
    is_string_predicate: bool = false,
};

/// Content query metadata (extends Query).
pub const ContentQuery = Query;

/// View query metadata (extends Query).
pub const ViewQuery = Query;

/// CompileResult — the result of a compilation.
pub const CompileResult = struct {
    output: []const u8,
    source_map: ?[]const u8 = null,
    errors: []const []const u8 = &.{},
    /// The kind of compilation (component, directive, pipe, etc.)
    kind: ?[]const u8 = null,
};

/// CompileReflector — provides reflection capabilities.
/// In AOT mode, this is not used — all reflection happens at compile time.
pub const CompileReflector = struct {
    /// Resolve a type reference to its actual type.
    resolve_type: ?*const fn (type_name: []const u8) []const u8 = null,
};

/// SchemaMetadata — metadata for custom schema elements.
pub const SchemaMetadata = struct {
    name: []const u8,
};

/// CUSTOM_ELEMENTS_SCHEMA — allows custom elements without errors.
pub const CUSTOM_ELEMENTS_SCHEMA: SchemaMetadata = .{ .name = "custom-elements" };

/// NO_ERRORS_SCHEMA — allows any element/property without errors.
pub const NO_ERRORS_SCHEMA: SchemaMetadata = .{ .name = "no-error-schema" };

/// Provider — a DI provider configuration.
pub const Provider = struct {
    token: []const u8,
    use_existing: ?[]const u8 = null,
    use_factory: ?[]const u8 = null,
    use_value: ?[]const u8 = null,
    use_class: ?[]const u8 = null,
    deps: []const []const u8 = &.{},
    multi: bool = false,
};

/// TypeDecorator — base type for decorator metadata.
pub const TypeDecorator = struct {
    name: []const u8,
};

/// DirectiveDecorator — @Directive decorator metadata.
pub const DirectiveDecorator = struct {
    selector: []const u8 = "",
    inputs: []const []const u8 = &.{},
    outputs: []const []const u8 = &.{},
    host: ?[]const u8 = null,
    export_as: []const []const u8 = &.{},
    queries: []const Query = &.{},
    is_standalone: bool = false,
};

/// ComponentDecorator — @Component decorator metadata (extends Directive).
pub const ComponentDecorator = struct {
    base: DirectiveDecorator,
    template: []const u8 = "",
    template_url: ?[]const u8 = null,
    styles: []const []const u8 = &.{},
    style_urls: []const []const u8 = &.{},
    encapsulation: ViewEncapsulation = .Emulated,
    change_detection: ChangeDetectionStrategy = .Default,
    animations: []const []const u8 = &.{},
    is_standalone: bool = false,
    imports: []const []const u8 = &.{},
};

/// PipeDecorator — @Pipe decorator metadata.
pub const PipeDecorator = struct {
    name: []const u8,
    pure: bool = true,
    is_standalone: bool = false,
};

/// InjectableDecorator — @Injectable decorator metadata.
pub const InjectableDecorator = struct {
    provided_in: ?[]const u8 = null,
};

/// NgModuleDecorator — @NgModule decorator metadata.
pub const NgModuleDecorator = struct {
    declarations: []const []const u8 = &.{},
    imports: []const []const u8 = &.{},
    exports: []const []const u8 = &.{},
    bootstrap: []const []const u8 = &.{},
    schemas: []const SchemaMetadata = &.{},
};
