/// R3 View API — Metadata interfaces for view compilation
///
/// Port of: compiler/src/render3/view/api.ts (595 LoC)
///
/// Defines the metadata structures used by the view compiler to compile
/// components, directives, pipes, and injectables.
const std = @import("std");

/// ViewEncapsulation — encapsulation modes for component styles.
/// Direct port of `ViewEncapsulation` enum from core.
pub const ViewEncapsulation = enum(u8) {
    Emulated = 0, // Default: styles are scoped to the component
    Native = 1, // Shadow DOM encapsulation
    ShadowDom = 2, // Shadow DOM encapsulation (modern name)
    None = 3, // No encapsulation
};

/// ChangeDetectionStrategy — change detection strategies.
/// Direct port of `ChangeDetectionStrategy` enum from core.
pub const ChangeDetectionStrategy = enum(u8) {
    Default = 0,
    OnPush = 1,
};

/// R3Reference — a reference to a class or function.
/// Direct port of `R3Reference` interface in the TS source.
pub const R3Reference = struct {
    name: []const u8,
    module_name: ?[]const u8 = null,
};

/// R3DirectiveMetadata — metadata for compiling a directive.
/// Direct port of `R3DirectiveMetadata` interface in the TS source.
pub const R3DirectiveMetadata = struct {
    name: []const u8,
    selector: []const u8 = "",
    inputs: []const []const u8 = &.{},
    outputs: []const []const u8 = &.{},
    export_as: []const []const u8 = &.{},
    is_standalone: bool = false,
    queries: []const []const u8 = &.{},
    host_bindings: []const []const u8 = &.{},
    host_listeners: []const []const u8 = &.{},
    is_component: bool = false,
    type_source_span: ?[]const u8 = null,
};

/// R3ComponentMetadata — metadata for compiling a component.
/// Direct port of `R3ComponentMetadata` interface in the TS source.
pub const R3ComponentMetadata = struct {
    base: R3DirectiveMetadata,
    template: []const u8 = "",
    encapsulation: ViewEncapsulation = .Emulated,
    change_detection: ChangeDetectionStrategy = .Default,
    styles: []const []const u8 = &.{},
    style_urls: []const []const u8 = &.{},
    animations: []const []const u8 = &.{},
    is_standalone: bool = false,
    imports: []const []const u8 = &.{},
    schemas: []const []const u8 = &.{},
    deferred_imports: []const []const u8 = &.{},
    preserve_whitespaces: bool = false,
};

/// R3HostMetadata — metadata for host binding compilation.
/// Direct port of `R3HostMetadata` interface in the TS source.
pub const R3HostMetadata = struct {
    type_name: []const u8,
    bindings: []const []const u8 = &.{},
    listeners: []const []const u8 = &.{},
};

/// R3QueryMetadata — metadata for content/view queries.
/// Direct port of `R3QueryMetadata` interface in the TS source.
pub const R3QueryMetadata = struct {
    property_name: []const u8,
    first: bool = false,
    descendants: bool = false,
    read: ?[]const u8 = null,
    static: bool = false,
    predicate: []const u8 = "",
    is_signal: bool = false,
};

/// R3TemplateDependencyMetadata — template dependency.
/// Direct port of `R3TemplateDependencyMetadata` interface in the TS source.
pub const R3TemplateDependencyMetadata = struct {
    kind: []const u8,
    type_name: []const u8,
};

/// R3PipeMetadata — metadata for compiling a pipe.
/// Direct port of `R3PipeMetadata` interface in the TS source.
pub const R3PipeMetadata = struct {
    name: []const u8,
    pipe_name: []const u8,
    pure: bool = true,
    is_standalone: bool = false,
};

/// R3InjectableMetadata — metadata for compiling an injectable.
/// Direct port of `R3InjectableMetadata` interface in the TS source.
pub const R3InjectableMetadata = struct {
    name: []const u8,
    token: ?[]const u8 = null,
    provided_in: ?[]const u8 = null,
    use_factory: ?[]const u8 = null,
    use_value: ?[]const u8 = null,
    use_class: ?[]const u8 = null,
    use_existing: ?[]const u8 = null,
    deps: []const []const u8 = &.{},
};

/// DeferBlockDepsEmitMode — how defer block dependencies are emitted.
/// Direct port of `DeferBlockDepsEmitMode` enum in the TS source.
pub const DeferBlockDepsEmitMode = enum(u8) {
    /// All deps are bundled into a single function.
    PerBundle,
    /// Each defer block gets its own deps function.
    PerBlock,
};

/// R3ComponentDeferMetadata — defer metadata for a component.
/// Direct port of `R3ComponentDeferMetadata` interface in the TS source.
pub const R3ComponentDeferMetadata = struct {
    mode: DeferBlockDepsEmitMode = .PerBundle,
    blocks: []const R3DeferBlockEntry = &.{},
};

/// R3DeferBlockEntry — a single defer block's dependency info.
pub const R3DeferBlockEntry = struct {
    block_id: u32,
    deps: []const []const u8 = &.{},
};

/// R3DeferResolverFunctionMetadata — metadata for a defer resolver function.
pub const R3DeferResolverFunctionMetadata = struct {
    function_name: []const u8,
    deps: []const []const u8 = &.{},
};

/// R3ForeignComponentMetadata — metadata for foreign (signal-based) components.
/// Direct port of `R3ForeignComponentMetadata` interface in the TS source.
pub const R3ForeignComponentMetadata = struct {
    component: []const u8,
    selector: []const u8 = "",
    inputs: []const []const u8 = &.{},
    outputs: []const []const u8 = &.{},
};

/// DeclarationListEmitMode — how declaration lists are emitted.
/// Direct port of `DeclarationListEmitMode` enum in the TS source.
pub const DeclarationListEmitMode = enum(u8) {
    /// Emit as a single array.
    Array,
    /// Emit as individual declarations.
    Individual,
};

// ─── Tests ──────────────────────────────────────────────────

test "R3DirectiveMetadata defaults" {
    const meta = R3DirectiveMetadata{ .name = "MyDir" };
    try std.testing.expectEqualStrings("MyDir", meta.name);
    try std.testing.expectEqualStrings("", meta.selector);
    try std.testing.expect(!meta.is_standalone);
}

test "R3ComponentMetadata defaults" {
    const meta = R3ComponentMetadata{ .base = .{ .name = "MyComp" } };
    try std.testing.expectEqualStrings("MyComp", meta.base.name);
    try std.testing.expectEqual(ViewEncapsulation.Emulated, meta.encapsulation);
    try std.testing.expectEqual(ChangeDetectionStrategy.Default, meta.change_detection);
}

test "R3PipeMetadata defaults" {
    const meta = R3PipeMetadata{ .name = "MyPipe", .pipe_name = "myPipe" };
    try std.testing.expect(meta.pure);
    try std.testing.expect(!meta.is_standalone);
}

test "ViewEncapsulation values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(ViewEncapsulation.Emulated));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(ViewEncapsulation.None));
}

test "ChangeDetectionStrategy values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(ChangeDetectionStrategy.Default));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(ChangeDetectionStrategy.OnPush));
}
