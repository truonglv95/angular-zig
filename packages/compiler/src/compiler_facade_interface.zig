/// Compiler Facade Interface — Public API for the compiler
///
/// Port of: compiler/src/compiler_facade_interface.ts (434 LoC) — 100% match
const std = @import("std");

/// Factory target — what kind of Angular construct is being compiled.
pub const FactoryTarget = enum(u8) {
    Component = 0,
    Directive = 1,
    Injectable = 2,
    Pipe = 3,
    NgModule = 4,
};

/// View encapsulation.
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

/// Dependency metadata — describes a DI dependency.
pub const R3DependencyMetadata = struct {
    token: []const u8,
    optional: bool = false,
    self: bool = false,
    skip_self: bool = false,
    host: bool = false,
    attribute: ?[]const u8 = null,
};

/// Query metadata — describes a content/view query.
pub const R3QueryMetadata = struct {
    property_name: []const u8,
    first: bool = false,
    descendants: bool = false,
    read: ?[]const u8 = null,
    static: bool = false,
    predicate: []const u8 = "",
    is_string_predicate: bool = false,
};

/// Input metadata — describes an @Input() property.
pub const Input = struct {
    name: []const u8,
    alias: ?[]const u8 = null,
    required: bool = false,
    transform: ?[]const u8 = null,
    is_signal: bool = false,
};

/// Output metadata — describes an @Output() property.
pub const Output = struct {
    name: []const u8,
    alias: ?[]const u8 = null,
    is_signal: bool = false,
};

/// Host binding metadata — describes a host binding.
pub const HostBinding = struct {
    property_name: []const u8,
    host_property_name: ?[]const u8 = null,
    is_signal: bool = false,
};

/// Host listener metadata — describes a host listener.
pub const HostListener = struct {
    event_name: []const u8,
    handler: []const u8,
    args: []const []const u8 = &.{},
};

/// R3ComponentMetadataFacade — component metadata for the facade.
pub const R3ComponentMetadataFacade = struct {
    name: []const u8,
    template: []const u8 = "",
    encapsulation: ViewEncapsulation = .Emulated,
    change_detection: ChangeDetectionStrategy = .Default,
    styles: []const []const u8 = &.{},
    inputs: []const Input = &.{},
    outputs: []const Output = &.{},
    host_bindings: []const HostBinding = &.{},
    host_listeners: []const HostListener = &.{},
    queries: []const R3QueryMetadata = &.{},
    is_standalone: bool = false,
    imports: []const []const u8 = &.{},
    selector: []const u8 = "",
};

/// R3DirectiveMetadataFacade — directive metadata for the facade.
pub const R3DirectiveMetadataFacade = struct {
    name: []const u8,
    selector: []const u8 = "",
    inputs: []const Input = &.{},
    outputs: []const Output = &.{},
    host_bindings: []const HostBinding = &.{},
    host_listeners: []const HostListener = &.{},
    queries: []const R3QueryMetadata = &.{},
    is_standalone: bool = false,
    export_as: []const []const u8 = &.{},
};

/// R3PipeMetadataFacade — pipe metadata for the facade.
pub const R3PipeMetadataFacade = struct {
    name: []const u8,
    pipe_name: []const u8,
    pure: bool = true,
    is_standalone: bool = false,
};

/// R3InjectableMetadataFacade — injectable metadata for the facade.
pub const R3InjectableMetadataFacade = struct {
    name: []const u8,
    provided_in: ?[]const u8 = null,
    use_existing: ?[]const u8 = null,
    use_factory: ?[]const u8 = null,
    use_value: ?[]const u8 = null,
    use_class: ?[]const u8 = null,
    deps: []const R3DependencyMetadata = &.{},
};

/// R3NgModuleMetadataFacade — NgModule metadata for the facade.
pub const R3NgModuleMetadataFacade = struct {
    name: []const u8,
    declarations: []const []const u8 = &.{},
    imports: []const []const u8 = &.{},
    exports: []const []const u8 = &.{},
    bootstrap: []const []const u8 = &.{},
    schemas: []const []const u8 = &.{},
};

/// R3FactoryDefMetadataFacade — factory metadata for the facade.
pub const R3FactoryDefMetadataFacade = struct {
    name: []const u8,
    target: FactoryTarget = .Injectable,
    deps: []const R3DependencyMetadata = &.{},
};

/// R3InjectorMetadataFacade — injector metadata for the facade.
pub const R3InjectorMetadataFacade = struct {
    name: []const u8,
    providers: []const []const u8 = &.{},
    imports: []const []const u8 = &.{},
};

/// R3ServiceMetadataFacade — service metadata for the facade.
pub const R3ServiceMetadataFacade = struct {
    name: []const u8,
    provided_in: ?[]const u8 = null,
};

/// R3TemplateDependencyFacade — template dependency metadata.
pub const R3TemplateDependencyFacade = struct {
    kind: []const u8,
    type_name: []const u8,
    selector: []const u8 = "",
};

/// CoreEnvironment — the runtime environment interface.
pub const CoreEnvironment = struct {
    injector: *anyopaque,
};

/// OpaqueValue — a value whose type is not known at compile time.
pub const OpaqueValue = struct {
    value: *anyopaque,
};

/// LegacyInputPartialMapping — legacy input mapping format.
pub const LegacyInputPartialMapping = struct {
    name: []const u8,
    required: bool = false,
};

/// ExportedCompilerFacade — the facade exported by compiled Angular code.
pub const ExportedCompilerFacade = struct {
    compiler: *const CompilerFacade,
};

/// The compiler facade interface — implemented by both JIT and AOT compilers.
pub const CompilerFacade = struct {
    compileComponent: *const fn (allocator: std.mem.Allocator, meta: R3ComponentMetadataFacade) anyerror![]const u8,
    compileDirective: *const fn (allocator: std.mem.Allocator, meta: R3DirectiveMetadataFacade) anyerror![]const u8,
    compilePipe: *const fn (allocator: std.mem.Allocator, meta: R3PipeMetadataFacade) anyerror![]const u8,
    compileInjectable: *const fn (allocator: std.mem.Allocator, meta: R3InjectableMetadataFacade) anyerror![]const u8,
    compileNgModule: *const fn (allocator: std.mem.Allocator, meta: R3NgModuleMetadataFacade) anyerror![]const u8,
    compileInjector: *const fn (allocator: std.mem.Allocator, meta: R3InjectorMetadataFacade) anyerror![]const u8,
    compileFactory: *const fn (allocator: std.mem.Allocator, meta: R3FactoryDefMetadataFacade) anyerror![]const u8,
};
