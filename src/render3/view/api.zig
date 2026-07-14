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
    /// The list of declarations is emitted into the generated code as is.
    Direct,
    /// The list is wrapped inside a closure (for forward references).
    Closure,
    /// Similar to Closure, with resolveForwardRef mapping.
    ClosureResolved,
    /// Runtime-resolved declarations.
    RuntimeResolved,
};

// ─── R3InputMetadata ────────────────────────────────────────

/// R3InputMetadata — metadata for an individual input on a directive.
/// Direct port of `R3InputMetadata` interface in the TS source.
pub const R3InputMetadata = struct {
    class_property_name: []const u8,
    binding_property_name: []const u8,
    required: bool = false,
    is_signal: bool = false,
    /// Transform function for the input (null if none, or if signal input).
    transform_function: ?[]const u8 = null,
};

// ─── R3TemplateDependencyKind ───────────────────────────────

/// R3TemplateDependencyKind — kind of template dependency.
/// Direct port of `R3TemplateDependencyKind` enum in the TS source.
pub const R3TemplateDependencyKind = enum(u8) {
    Directive = 0,
    Pipe = 1,
    NgModule = 2,
};

// ─── R3TemplateDependency ───────────────────────────────────

/// R3TemplateDependency — a dependency used within a component template.
/// Direct port of `R3TemplateDependency` interface in the TS source.
pub const R3TemplateDependency = struct {
    kind: R3TemplateDependencyKind,
    /// The type of the dependency as an expression string.
    type_name: []const u8,
};

// ─── R3DirectiveDependencyMetadata ──────────────────────────

/// R3DirectiveDependencyMetadata — info about a directive used in a template.
/// Direct port of `R3DirectiveDependencyMetadata` interface in the TS source.
pub const R3DirectiveDependencyMetadata = struct {
    kind: R3TemplateDependencyKind = .Directive,
    type_name: []const u8,
    selector: []const u8 = "",
    inputs: []const []const u8 = &.{},
    outputs: []const []const u8 = &.{},
    export_as: ?[]const []const u8 = null,
    is_component: bool = false,
    is_standalone: bool = false,
};

// ─── R3PipeDependencyMetadata ───────────────────────────────

/// R3PipeDependencyMetadata — info about a pipe used in a template.
/// Direct port of `R3PipeDependencyMetadata` interface in the TS source.
pub const R3PipeDependencyMetadata = struct {
    kind: R3TemplateDependencyKind = .Pipe,
    type_name: []const u8,
    name: []const u8,
    pure: bool = true,
};

// ─── R3NgModuleDependencyMetadata ───────────────────────────

/// R3NgModuleDependencyMetadata — info about an NgModule used in a template.
/// Direct port of `R3NgModuleDependencyMetadata` interface in the TS source.
pub const R3NgModuleDependencyMetadata = struct {
    kind: R3TemplateDependencyKind = .NgModule,
    type_name: []const u8,
};

// ─── R3HostDirectiveMetadata ────────────────────────────────

/// R3HostDirectiveMetadata — metadata for a host directive.
/// Direct port of `R3HostDirectiveMetadata` interface in the TS source.
pub const R3HostDirectiveMetadata = struct {
    directive_type: []const u8,
    inputs: ?[]const []const u8 = null,
    outputs: ?[]const []const u8 = null,
    is_standalone: bool = false,
};

// ─── R3DependencyMetadata ───────────────────────────────────

/// R3DependencyMetadata — metadata for a dependency.
/// Direct port of `R3DependencyMetadata` from r3_factory.ts.
pub const R3DependencyMetadata = struct {
    token: []const u8,
    is_attribute: bool = false,
    is_self: bool = false,
    is_skip_self: bool = false,
    is_optional: bool = false,
    is_host: bool = false,
};

// ─── R3QueryMetadata (expanded) ─────────────────────────────

/// R3QueryMetadata — expanded metadata for content/view queries.
/// Direct port of `R3QueryMetadata` interface in the TS source.
pub const R3QueryMetadataFull = struct {
    property_name: []const u8,
    /// Whether the query should return only the first match.
    first: bool = false,
    /// Whether the query should include descendants.
    descendants: bool = false,
    /// Whether the query should read a specific type.
    read: ?[]const u8 = null,
    /// Whether the query is static (resolved before change detection).
    is_static: bool = false,
    /// The predicate for the query (selector or type reference).
    predicate: []const u8 = "",
    /// Whether the query is signal-based.
    is_signal: bool = false,
    /// Whether the query is a string predicate (vs type reference).
    is_string_predicate: bool = false,
    /// The source span of the query.
    source_span: ?[]const u8 = null,
};

// ─── R3HostMetadata (expanded) ──────────────────────────────

/// R3HostMetadataFull — expanded metadata for host binding compilation.
/// Direct port of `R3HostMetadata` interface in the TS source.
pub const R3HostMetadataFull = struct {
    /// Host bindings (property → expression).
    bindings: []const HostBinding = &.{},
    /// Host listeners (event → handler).
    listeners: []const HostListener = &.{},
    /// Host attributes (static).
    attributes: []const HostAttribute = &.{},
};

/// HostBinding — a host property binding.
pub const HostBinding = struct {
    property_name: []const u8,
    value: []const u8,
    source_span: ?[]const u8 = null,
};

/// HostListener — a host event listener.
pub const HostListener = struct {
    event_name: []const u8,
    handler: []const u8,
    target: ?[]const u8 = null,
    phase: ?[]const u8 = null,
    source_span: ?[]const u8 = null,
};

/// HostAttribute — a static host attribute.
pub const HostAttribute = struct {
    name: []const u8,
    value: []const u8,
};

// ─── Lifecycle metadata ─────────────────────────────────────

/// R3DirectiveLifecycle — lifecycle hooks used by a directive.
/// Direct port of `lifecycle` field in `R3DirectiveMetadata`.
pub const R3DirectiveLifecycle = struct {
    uses_on_changes: bool = false,
    uses_on_init: bool = false,
    uses_do_check: bool = false,
    uses_after_content_init: bool = false,
    uses_after_content_checked: bool = false,
    uses_after_view_init: bool = false,
    uses_after_view_checked: bool = false,
    uses_on_destroy: bool = false,
};

// ─── ControlCreate metadata ─────────────────────────────────

/// R3ControlCreate — metadata for the ɵngControlCreate hook.
/// Direct port of `controlCreate` field in `R3DirectiveMetadata`.
pub const R3ControlCreate = struct {
    pass_through_input: ?[]const u8 = null,
};

// ─── R3ComponentMetadataTemplate ────────────────────────────

/// R3ComponentMetadataTemplate — template info within R3ComponentMetadata.
/// Direct port of `template` field in `R3ComponentMetadata`.
pub const R3ComponentMetadataTemplate = struct {
    /// Parsed nodes of the template.
    nodes: []const u8 = &.{}, // Placeholder for t.Node[]
    /// ng-content selectors extracted from the template.
    ng_content_selectors: []const []const u8 = &.{},
    /// Whether the template preserves whitespaces.
    preserve_whitespaces: bool = false,
};

// ─── Helper functions ───────────────────────────────────────

/// Check if a directive metadata is for a component.
pub fn isComponent(meta: *const R3DirectiveMetadata) bool {
    return meta.is_component;
}

/// Check if a directive is standalone.
pub fn isStandalone(meta: *const R3DirectiveMetadata) bool {
    return meta.is_standalone;
}

/// Get the selector of a directive, or empty string if none.
pub fn getSelector(meta: *const R3DirectiveMetadata) []const u8 {
    return meta.selector;
}

/// Check if a directive has a specific export-as name.
pub fn hasExportAs(meta: *const R3DirectiveMetadata, name: []const u8) bool {
    for (meta.export_as) |export_name| {
        if (std.mem.eql(u8, export_name, name)) return true;
    }
    return false;
}

/// Check if a directive has a specific input.
pub fn hasInput(meta: *const R3DirectiveMetadata, name: []const u8) bool {
    for (meta.inputs) |input| {
        if (std.mem.eql(u8, input, name)) return true;
    }
    return false;
}

/// Check if a directive has a specific output.
pub fn hasOutput(meta: *const R3DirectiveMetadata, name: []const u8) bool {
    for (meta.outputs) |output| {
        if (std.mem.eql(u8, output, name)) return true;
    }
    return false;
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

/// Convert R3TemplateDependencyKind to string.
pub fn templateDependencyKindToString(k: R3TemplateDependencyKind) []const u8 {
    return switch (k) {
        .Directive => "Directive",
        .Pipe => "Pipe",
        .NgModule => "NgModule",
    };
}

/// Convert DeclarationListEmitMode to string.
pub fn declarationListEmitModeToString(m: DeclarationListEmitMode) []const u8 {
    return switch (m) {
        .Direct => "Direct",
        .Closure => "Closure",
        .ClosureResolved => "ClosureResolved",
        .RuntimeResolved => "RuntimeResolved",
    };
}

/// Convert DeferBlockDepsEmitMode to string.
pub fn deferBlockDepsEmitModeToString(m: DeferBlockDepsEmitMode) []const u8 {
    return switch (m) {
        .PerBundle => "PerBundle",
        .PerBlock => "PerBlock",
    };
}

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

test "R3InputMetadata defaults" {
    const im = R3InputMetadata{
        .class_property_name = "value",
        .binding_property_name = "value",
    };
    try std.testing.expect(!im.required);
    try std.testing.expect(!im.is_signal);
    try std.testing.expect(im.transform_function == null);
}

test "R3InputMetadata with signal" {
    const im = R3InputMetadata{
        .class_property_name = "count",
        .binding_property_name = "count",
        .required = true,
        .is_signal = true,
    };
    try std.testing.expect(im.required);
    try std.testing.expect(im.is_signal);
}

test "R3TemplateDependencyKind values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(R3TemplateDependencyKind.Directive));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(R3TemplateDependencyKind.Pipe));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(R3TemplateDependencyKind.NgModule));
}

test "R3TemplateDependency defaults" {
    const dep = R3TemplateDependency{
        .kind = .Directive,
        .type_name = "NgIf",
    };
    try std.testing.expectEqual(R3TemplateDependencyKind.Directive, dep.kind);
    try std.testing.expectEqualStrings("NgIf", dep.type_name);
}

test "R3DirectiveDependencyMetadata defaults" {
    const dep = R3DirectiveDependencyMetadata{
        .type_name = "NgFor",
        .selector = "[ngFor][ngForOf]",
    };
    try std.testing.expectEqual(R3TemplateDependencyKind.Directive, dep.kind);
    try std.testing.expectEqualStrings("[ngFor][ngForOf]", dep.selector);
    try std.testing.expect(!dep.is_component);
    try std.testing.expect(!dep.is_standalone);
}

test "R3PipeDependencyMetadata defaults" {
    const dep = R3PipeDependencyMetadata{
        .type_name = "DatePipe",
        .name = "date",
    };
    try std.testing.expectEqual(R3TemplateDependencyKind.Pipe, dep.kind);
    try std.testing.expectEqualStrings("date", dep.name);
    try std.testing.expect(dep.pure);
}

test "R3NgModuleDependencyMetadata defaults" {
    const dep = R3NgModuleDependencyMetadata{
        .type_name = "CommonModule",
    };
    try std.testing.expectEqual(R3TemplateDependencyKind.NgModule, dep.kind);
}

test "R3HostDirectiveMetadata defaults" {
    const hd = R3HostDirectiveMetadata{
        .directive_type = "MyHostDir",
    };
    try std.testing.expectEqualStrings("MyHostDir", hd.directive_type);
    try std.testing.expect(hd.inputs == null);
    try std.testing.expect(hd.outputs == null);
    try std.testing.expect(!hd.is_standalone);
}

test "R3DependencyMetadata defaults" {
    const dep = R3DependencyMetadata{
        .token = "MyService",
    };
    try std.testing.expect(!dep.is_attribute);
    try std.testing.expect(!dep.is_self);
    try std.testing.expect(!dep.is_skip_self);
    try std.testing.expect(!dep.is_optional);
    try std.testing.expect(!dep.is_host);
}

test "R3QueryMetadataFull defaults" {
    const q = R3QueryMetadataFull{
        .property_name = "items",
    };
    try std.testing.expect(!q.first);
    try std.testing.expect(!q.descendants);
    try std.testing.expect(!q.is_static);
    try std.testing.expect(!q.is_signal);
}

test "R3DirectiveLifecycle defaults" {
    const lc = R3DirectiveLifecycle{};
    try std.testing.expect(!lc.uses_on_changes);
    try std.testing.expect(!lc.uses_on_init);
    try std.testing.expect(!lc.uses_do_check);
    try std.testing.expect(!lc.uses_on_destroy);
}

test "R3DirectiveLifecycle with hooks" {
    const lc = R3DirectiveLifecycle{
        .uses_on_changes = true,
        .uses_on_init = true,
        .uses_on_destroy = true,
    };
    try std.testing.expect(lc.uses_on_changes);
    try std.testing.expect(lc.uses_on_init);
    try std.testing.expect(lc.uses_on_destroy);
}

test "R3ControlCreate defaults" {
    const cc = R3ControlCreate{};
    try std.testing.expect(cc.pass_through_input == null);
}

test "R3ControlCreate with input" {
    const cc = R3ControlCreate{
        .pass_through_input = "ngModel",
    };
    try std.testing.expectEqualStrings("ngModel", cc.pass_through_input.?);
}

test "HostBinding struct" {
    const hb = HostBinding{
        .property_name = "class.active",
        .value = "isActive",
    };
    try std.testing.expectEqualStrings("class.active", hb.property_name);
}

test "HostListener struct" {
    const hl = HostListener{
        .event_name = "click",
        .handler = "onClick()",
    };
    try std.testing.expectEqualStrings("click", hl.event_name);
    try std.testing.expect(hl.target == null);
}

test "HostAttribute struct" {
    const ha = HostAttribute{
        .name = "role",
        .value = "button",
    };
    try std.testing.expectEqualStrings("role", ha.name);
    try std.testing.expectEqualStrings("button", ha.value);
}

test "DeclarationListEmitMode values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(DeclarationListEmitMode.Direct));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(DeclarationListEmitMode.Closure));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(DeclarationListEmitMode.ClosureResolved));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(DeclarationListEmitMode.RuntimeResolved));
}

test "DeferBlockDepsEmitMode values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(DeferBlockDepsEmitMode.PerBundle));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(DeferBlockDepsEmitMode.PerBlock));
}

test "R3ComponentMetadataTemplate defaults" {
    const t = R3ComponentMetadataTemplate{};
    try std.testing.expectEqual(@as(usize, 0), t.nodes.len);
    try std.testing.expect(!t.preserve_whitespaces);
}

test "isComponent — false for directive" {
    const meta = R3DirectiveMetadata{ .name = "MyDir" };
    try std.testing.expect(!isComponent(&meta));
}

test "isComponent — true for component" {
    const meta = R3DirectiveMetadata{ .name = "MyComp", .is_component = true };
    try std.testing.expect(isComponent(&meta));
}

test "isStandalone — false by default" {
    const meta = R3DirectiveMetadata{ .name = "MyDir" };
    try std.testing.expect(!isStandalone(&meta));
}

test "isStandalone — true when set" {
    const meta = R3DirectiveMetadata{ .name = "MyDir", .is_standalone = true };
    try std.testing.expect(isStandalone(&meta));
}

test "getSelector — returns selector" {
    const meta = R3DirectiveMetadata{ .name = "MyDir", .selector = "[appDir]" };
    try std.testing.expectEqualStrings("[appDir]", getSelector(&meta));
}

test "hasExportAs — finds name" {
    const export_as = [_][]const u8{ "dir", "myDir" };
    const meta = R3DirectiveMetadata{ .name = "MyDir", .export_as = &export_as };
    try std.testing.expect(hasExportAs(&meta, "dir"));
    try std.testing.expect(hasExportAs(&meta, "myDir"));
    try std.testing.expect(!hasExportAs(&meta, "other"));
}

test "hasInput — finds input" {
    const inputs = [_][]const u8{ "value", "label" };
    const meta = R3DirectiveMetadata{ .name = "MyDir", .inputs = &inputs };
    try std.testing.expect(hasInput(&meta, "value"));
    try std.testing.expect(hasInput(&meta, "label"));
    try std.testing.expect(!hasInput(&meta, "other"));
}

test "hasOutput — finds output" {
    const outputs = [_][]const u8{ "change", "blur" };
    const meta = R3DirectiveMetadata{ .name = "MyDir", .outputs = &outputs };
    try std.testing.expect(hasOutput(&meta, "change"));
    try std.testing.expect(hasOutput(&meta, "blur"));
    try std.testing.expect(!hasOutput(&meta, "other"));
}

test "viewEncapsulationToString" {
    try std.testing.expectEqualStrings("Emulated", viewEncapsulationToString(.Emulated));
    try std.testing.expectEqualStrings("Native", viewEncapsulationToString(.Native));
    try std.testing.expectEqualStrings("ShadowDom", viewEncapsulationToString(.ShadowDom));
    try std.testing.expectEqualStrings("None", viewEncapsulationToString(.None));
}

test "changeDetectionStrategyToString" {
    try std.testing.expectEqualStrings("Default", changeDetectionStrategyToString(.Default));
    try std.testing.expectEqualStrings("OnPush", changeDetectionStrategyToString(.OnPush));
}

test "templateDependencyKindToString" {
    try std.testing.expectEqualStrings("Directive", templateDependencyKindToString(.Directive));
    try std.testing.expectEqualStrings("Pipe", templateDependencyKindToString(.Pipe));
    try std.testing.expectEqualStrings("NgModule", templateDependencyKindToString(.NgModule));
}

test "declarationListEmitModeToString" {
    try std.testing.expectEqualStrings("Direct", declarationListEmitModeToString(.Direct));
    try std.testing.expectEqualStrings("Closure", declarationListEmitModeToString(.Closure));
    try std.testing.expectEqualStrings("ClosureResolved", declarationListEmitModeToString(.ClosureResolved));
    try std.testing.expectEqualStrings("RuntimeResolved", declarationListEmitModeToString(.RuntimeResolved));
}

test "deferBlockDepsEmitModeToString" {
    try std.testing.expectEqualStrings("PerBundle", deferBlockDepsEmitModeToString(.PerBundle));
    try std.testing.expectEqualStrings("PerBlock", deferBlockDepsEmitModeToString(.PerBlock));
}

test "R3Reference defaults" {
    const ref = R3Reference{ .name = "MyClass" };
    try std.testing.expectEqualStrings("MyClass", ref.name);
    try std.testing.expect(ref.module_name == null);
}

test "R3HostMetadata defaults" {
    const hm = R3HostMetadata{ .type_name = "MyDir" };
    try std.testing.expectEqual(@as(usize, 0), hm.bindings.len);
    try std.testing.expectEqual(@as(usize, 0), hm.listeners.len);
}

test "R3HostMetadataFull defaults" {
    const hm = R3HostMetadataFull{};
    try std.testing.expectEqual(@as(usize, 0), hm.bindings.len);
    try std.testing.expectEqual(@as(usize, 0), hm.listeners.len);
    try std.testing.expectEqual(@as(usize, 0), hm.attributes.len);
}

test "R3InjectableMetadata defaults" {
    const im = R3InjectableMetadata{ .name = "MyService" };
    try std.testing.expect(im.token == null);
    try std.testing.expect(im.provided_in == null);
    try std.testing.expect(im.use_factory == null);
}

test "R3ComponentDeferMetadata defaults" {
    const dm = R3ComponentDeferMetadata{};
    try std.testing.expectEqual(DeferBlockDepsEmitMode.PerBundle, dm.mode);
    try std.testing.expectEqual(@as(usize, 0), dm.blocks.len);
}

test "R3DeferBlockEntry defaults" {
    const entry = R3DeferBlockEntry{ .block_id = 1 };
    try std.testing.expectEqual(@as(u32, 1), entry.block_id);
    try std.testing.expectEqual(@as(usize, 0), entry.deps.len);
}

test "R3ForeignComponentMetadata defaults" {
    const fcm = R3ForeignComponentMetadata{ .component = "MyComp" };
    try std.testing.expectEqualStrings("", fcm.selector);
    try std.testing.expectEqual(@as(usize, 0), fcm.inputs.len);
}
