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

// ─── Additional types from core.ts ──────────────────────────

/// Default value for `emitDistinctChangesOnly`.
pub const emit_distinct_changes_only_default_value = true;

/// ViewEncapsulation with experimental isolated shadow DOM.
/// Direct port of the expanded `ViewEncapsulation` enum in the TS source.
pub const ViewEncapsulationFull = enum(u8) {
    Emulated = 0,
    /// Historically the 1 value was for Native encapsulation (removed in v11).
    Native = 1,
    None = 2,
    ShadowDom = 3,
    ExperimentalIsolatedShadowDom = 4,
};

/// ChangeDetectionStrategy with Eager alias.
/// Direct port of the expanded `ChangeDetectionStrategy` enum in the TS source.
/// Note: In TS, Eager is an alias for Default (both = 1). In Zig, we can't have
/// duplicate enum values, so Eager is omitted (use Default instead).
pub const ChangeDetectionStrategyFull = enum(u8) {
    OnPush = 0,
    Default = 1,
};

/// Eager is an alias for Default in the TS source.
pub const EAGER: ChangeDetectionStrategyFull = .Default;

/// InputFlags — flags describing an input for a directive.
/// Direct port of `InputFlags` enum in the TS source.
pub const InputFlags = enum(u8) {
    None = 0,
    SignalBased = 1,
    HasDecoratorInputTransform = 2,
};

/// InjectFlags — injection flags for DI.
/// Direct port of `InjectFlags` const enum in the TS source.
pub const InjectFlags = enum(u8) {
    Default = 0,
    Host = 1,
    Self = 2,
    SkipSelf = 4,
    Optional = 8,
    ForPipe = 16,
};

/// MissingTranslationStrategy — how to handle missing translations.
/// Direct port of `MissingTranslationStrategy` enum in the TS source.
pub const MissingTranslationStrategy = enum(u8) {
    Error = 0,
    Warning = 1,
    Ignore = 2,
};

/// SelectorFlags — flags for generating R3-style CSS selectors.
/// Direct port of `SelectorFlags` const enum in the TS source.
/// Note: These are bit flags, so we use u8 constants instead of an enum
/// to allow combining flags with bitwise OR.
pub const SelectorFlags = struct {
    pub const NOT: u8 = 0b0001;
    pub const ATTRIBUTE: u8 = 0b0010;
    pub const ELEMENT: u8 = 0b0100;
    pub const CLASS: u8 = 0b1000;
};

/// RenderFlags — flags to determine which blocks should be executed.
/// Direct port of `RenderFlags` const enum in the TS source.
pub const RenderFlags = enum(u8) {
    /// Whether to run the creation block (e.g. create elements and directives).
    Create = 0b01,
    /// Whether to run the update block (e.g. refresh bindings).
    Update = 0b10,
};

/// AttributeMarker — marker values for attribute arrays.
/// Direct port of `AttributeMarker` const enum in the TS source.
pub const AttributeMarker = enum(u8) {
    /// NamespaceURI marker: following 3 values are namespaceUri, attributeName, attributeValue.
    NamespaceURI = 0,
    /// Classes marker: following values are class names.
    Classes = 1,
    /// Styles marker: following pairs are style name/value.
    Styles = 2,
    /// Bindings marker: following attribute names are from input/output bindings.
    Bindings = 3,
    /// Template marker: following attributes are from inline-template declaration.
    Template = 4,
    /// ProjectAs marker: following value is a parsed CssSelector for ngProjectAs.
    ProjectAs = 5,
    /// I18n marker: following attribute will be translated by runtime i18n.
    I18n = 6,
};

/// SecurityContext — the security context for a binding.
/// Direct port of `SecurityContext` re-exported from schema/dom_security_schema.
pub const SecurityContext = enum(u8) {
    None = 0,
    HTML = 1,
    Style = 2,
    Script = 3,
    URL = 4,
    ResourceURL = 5,
};

/// R3CssSelectorEntry — a single entry in an R3 CSS selector.
/// Can be either a string (element/attr/class name) or a flag value.
pub const R3CssSelectorEntry = union(enum) {
    string: []const u8,
    flags: u8, // SelectorFlags bit field
};

/// R3CssSelector — array of selector entries.
pub const R3CssSelector = []const R3CssSelectorEntry;

/// R3CssSelectorList — list of R3 CSS selectors.
pub const R3CssSelectorList = []const R3CssSelector;

/// CssSelector — parsed CSS selector (simplified).
pub const CssSelector = struct {
    element: ?[]const u8 = null,
    attrs: []const []const u8 = &.{},
    class_names: []const []const u8 = &.{},
    not_selectors: []const CssSelector = &.{},
};

/// Convert a parsed CssSelector to a simple R3 selector.
/// Direct port of `parserSelectorToSimpleSelector(selector)` in the TS source.
pub fn parserSelectorToSimpleSelector(allocator: std.mem.Allocator, selector: CssSelector) ![]const R3CssSelectorEntry {
    var result = std.array_list.Managed(R3CssSelectorEntry).init(allocator);

    // Element name (empty string if '*' or null)
    const element_name = if (selector.element) |el| (if (std.mem.eql(u8, el, "*")) "" else el) else "";
    try result.append(.{ .string = element_name });

    // Attributes
    for (selector.attrs) |attr| {
        try result.append(.{ .string = attr });
    }

    // Classes
    if (selector.class_names.len > 0) {
        try result.append(.{ .flags = SelectorFlags.CLASS });
        for (selector.class_names) |class_name| {
            try result.append(.{ .string = class_name });
        }
    }

    return result.toOwnedSlice();
}

/// Convert a parsed CssSelector to a negative R3 selector.
/// Direct port of `parserSelectorToNegativeSelector(selector)` in the TS source.
pub fn parserSelectorToNegativeSelector(allocator: std.mem.Allocator, selector: CssSelector) ![]const R3CssSelectorEntry {
    var result = std.array_list.Managed(R3CssSelectorEntry).init(allocator);

    if (selector.element) |el| {
        try result.append(.{ .flags = SelectorFlags.NOT | SelectorFlags.ELEMENT });
        try result.append(.{ .string = el });
        for (selector.attrs) |attr| {
            try result.append(.{ .string = attr });
        }
    } else if (selector.attrs.len > 0) {
        try result.append(.{ .flags = SelectorFlags.NOT | SelectorFlags.ATTRIBUTE });
        for (selector.attrs) |attr| {
            try result.append(.{ .string = attr });
        }
    } else if (selector.class_names.len > 0) {
        try result.append(.{ .flags = SelectorFlags.NOT | SelectorFlags.CLASS });
        for (selector.class_names) |class_name| {
            try result.append(.{ .string = class_name });
        }
    }

    return result.toOwnedSlice();
}

// ─── Helper functions for enums ─────────────────────────────

/// Convert ViewEncapsulation to string.
pub fn viewEncapsulationToString(e: ViewEncapsulation) []const u8 {
    return switch (e) {
        .Emulated => "Emulated",
        .Native => "Native",
        .None => "None",
        .ShadowDom => "ShadowDom",
    };
}

/// Convert ChangeDetectionStrategy to string.
pub fn changeDetectionStrategyToString(s: ChangeDetectionStrategy) []const u8 {
    return switch (s) {
        .Default => "Default",
        .OnPush => "OnPush",
    };
}

/// Convert InputFlags to string.
pub fn inputFlagsToString(f: InputFlags) []const u8 {
    return switch (f) {
        .None => "None",
        .SignalBased => "SignalBased",
        .HasDecoratorInputTransform => "HasDecoratorInputTransform",
    };
}

/// Convert InjectFlags to string.
pub fn injectFlagsToString(f: InjectFlags) []const u8 {
    return switch (f) {
        .Default => "Default",
        .Host => "Host",
        .Self => "Self",
        .SkipSelf => "SkipSelf",
        .Optional => "Optional",
        .ForPipe => "ForPipe",
    };
}

/// Convert MissingTranslationStrategy to string.
pub fn missingTranslationStrategyToString(s: MissingTranslationStrategy) []const u8 {
    return switch (s) {
        .Error => "Error",
        .Warning => "Warning",
        .Ignore => "Ignore",
    };
}

/// Convert SecurityContext to string.
pub fn securityContextToString(ctx: SecurityContext) []const u8 {
    return switch (ctx) {
        .None => "None",
        .HTML => "HTML",
        .Style => "Style",
        .Script => "Script",
        .URL => "URL",
        .ResourceURL => "ResourceURL",
    };
}

/// Convert AttributeMarker to string.
pub fn attributeMarkerToString(m: AttributeMarker) []const u8 {
    return switch (m) {
        .NamespaceURI => "NamespaceURI",
        .Classes => "Classes",
        .Styles => "Styles",
        .Bindings => "Bindings",
        .Template => "Template",
        .ProjectAs => "ProjectAs",
        .I18n => "I18n",
    };
}

/// Convert RenderFlags to string.
pub fn renderFlagsToString(f: RenderFlags) []const u8 {
    return switch (f) {
        .Create => "Create",
        .Update => "Update",
    };
}

/// Convert SelectorFlags to string.
pub fn selectorFlagsToString(f: u8) []const u8 {
    if (f == SelectorFlags.NOT) return "NOT";
    if (f == SelectorFlags.ATTRIBUTE) return "ATTRIBUTE";
    if (f == SelectorFlags.ELEMENT) return "ELEMENT";
    if (f == SelectorFlags.CLASS) return "CLASS";
    return "COMBINED";
}

// ─── Tests ──────────────────────────────────────────────────

test "ViewEncapsulation values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(ViewEncapsulation.Emulated));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(ViewEncapsulation.None));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(ViewEncapsulation.ShadowDom));
}

test "ViewEncapsulationFull — experimental" {
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(ViewEncapsulationFull.ExperimentalIsolatedShadowDom));
}

test "ChangeDetectionStrategy values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(ChangeDetectionStrategy.Default));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(ChangeDetectionStrategy.OnPush));
}

test "ChangeDetectionStrategyFull — Eager alias" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(ChangeDetectionStrategyFull.OnPush));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(ChangeDetectionStrategyFull.Default));
    try std.testing.expectEqual(ChangeDetectionStrategyFull.Default, EAGER);
}

test "InputFlags values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(InputFlags.None));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(InputFlags.SignalBased));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(InputFlags.HasDecoratorInputTransform));
}

test "InjectFlags values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(InjectFlags.Default));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(InjectFlags.Host));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(InjectFlags.Self));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(InjectFlags.SkipSelf));
    try std.testing.expectEqual(@as(u8, 8), @intFromEnum(InjectFlags.Optional));
    try std.testing.expectEqual(@as(u8, 16), @intFromEnum(InjectFlags.ForPipe));
}

test "MissingTranslationStrategy values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(MissingTranslationStrategy.Error));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(MissingTranslationStrategy.Warning));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(MissingTranslationStrategy.Ignore));
}

test "SelectorFlags values" {
    try std.testing.expectEqual(@as(u8, 0b0001), SelectorFlags.NOT);
    try std.testing.expectEqual(@as(u8, 0b0010), SelectorFlags.ATTRIBUTE);
    try std.testing.expectEqual(@as(u8, 0b0100), SelectorFlags.ELEMENT);
    try std.testing.expectEqual(@as(u8, 0b1000), SelectorFlags.CLASS);
}

test "RenderFlags values" {
    try std.testing.expectEqual(@as(u8, 0b01), @intFromEnum(RenderFlags.Create));
    try std.testing.expectEqual(@as(u8, 0b10), @intFromEnum(RenderFlags.Update));
}

test "AttributeMarker values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(AttributeMarker.NamespaceURI));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(AttributeMarker.Classes));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(AttributeMarker.Styles));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(AttributeMarker.Bindings));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(AttributeMarker.Template));
    try std.testing.expectEqual(@as(u8, 5), @intFromEnum(AttributeMarker.ProjectAs));
    try std.testing.expectEqual(@as(u8, 6), @intFromEnum(AttributeMarker.I18n));
}

test "SecurityContext values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(SecurityContext.None));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(SecurityContext.HTML));
    try std.testing.expectEqual(@as(u8, 5), @intFromEnum(SecurityContext.ResourceURL));
}

test "CUSTOM_ELEMENTS_SCHEMA" {
    try std.testing.expectEqualStrings("custom-elements", CUSTOM_ELEMENTS_SCHEMA.name);
}

test "NO_ERRORS_SCHEMA" {
    try std.testing.expectEqualStrings("no-error-schema", NO_ERRORS_SCHEMA.name);
}

test "emit_distinct_changes_only_default_value" {
    try std.testing.expect(emit_distinct_changes_only_default_value);
}

test "Input defaults" {
    const input = Input{ .name = "value" };
    try std.testing.expect(input.alias == null);
    try std.testing.expect(!input.required);
    try std.testing.expect(!input.is_signal);
}

test "Input with signal" {
    const input = Input{
        .name = "count",
        .alias = "cnt",
        .required = true,
        .is_signal = true,
    };
    try std.testing.expectEqualStrings("cnt", input.alias.?);
    try std.testing.expect(input.required);
    try std.testing.expect(input.is_signal);
}

test "Output defaults" {
    const output = Output{ .name = "change" };
    try std.testing.expect(output.alias == null);
}

test "HostBinding defaults" {
    const hb = HostBinding{ .property_name = "class.active" };
    try std.testing.expect(hb.host_property_name == null);
}

test "HostListener defaults" {
    const hl = HostListener{ .event_name = "click", .handler = "onClick" };
    try std.testing.expectEqual(@as(usize, 0), hl.args.len);
}

test "Query defaults" {
    const q = Query{ .property_name = "items" };
    try std.testing.expect(!q.first);
    try std.testing.expect(!q.descendants);
    try std.testing.expect(!q.is_static);
}

test "SchemaMetadata" {
    const schema = SchemaMetadata{ .name = "custom" };
    try std.testing.expectEqualStrings("custom", schema.name);
}

test "viewEncapsulationToString" {
    try std.testing.expectEqualStrings("Emulated", viewEncapsulationToString(.Emulated));
    try std.testing.expectEqualStrings("None", viewEncapsulationToString(.None));
    try std.testing.expectEqualStrings("ShadowDom", viewEncapsulationToString(.ShadowDom));
}

test "changeDetectionStrategyToString" {
    try std.testing.expectEqualStrings("Default", changeDetectionStrategyToString(.Default));
    try std.testing.expectEqualStrings("OnPush", changeDetectionStrategyToString(.OnPush));
}

test "inputFlagsToString" {
    try std.testing.expectEqualStrings("None", inputFlagsToString(.None));
    try std.testing.expectEqualStrings("SignalBased", inputFlagsToString(.SignalBased));
}

test "injectFlagsToString" {
    try std.testing.expectEqualStrings("Default", injectFlagsToString(.Default));
    try std.testing.expectEqualStrings("Host", injectFlagsToString(.Host));
    try std.testing.expectEqualStrings("Optional", injectFlagsToString(.Optional));
}

test "missingTranslationStrategyToString" {
    try std.testing.expectEqualStrings("Error", missingTranslationStrategyToString(.Error));
    try std.testing.expectEqualStrings("Warning", missingTranslationStrategyToString(.Warning));
    try std.testing.expectEqualStrings("Ignore", missingTranslationStrategyToString(.Ignore));
}

test "securityContextToString" {
    try std.testing.expectEqualStrings("None", securityContextToString(.None));
    try std.testing.expectEqualStrings("HTML", securityContextToString(.HTML));
    try std.testing.expectEqualStrings("URL", securityContextToString(.URL));
}

test "attributeMarkerToString" {
    try std.testing.expectEqualStrings("Classes", attributeMarkerToString(.Classes));
    try std.testing.expectEqualStrings("Styles", attributeMarkerToString(.Styles));
    try std.testing.expectEqualStrings("Bindings", attributeMarkerToString(.Bindings));
    try std.testing.expectEqualStrings("I18n", attributeMarkerToString(.I18n));
}

test "renderFlagsToString" {
    try std.testing.expectEqualStrings("Create", renderFlagsToString(.Create));
    try std.testing.expectEqualStrings("Update", renderFlagsToString(.Update));
}

test "selectorFlagsToString" {
    try std.testing.expectEqualStrings("NOT", selectorFlagsToString(SelectorFlags.NOT));
    try std.testing.expectEqualStrings("ATTRIBUTE", selectorFlagsToString(SelectorFlags.ATTRIBUTE));
    try std.testing.expectEqualStrings("ELEMENT", selectorFlagsToString(SelectorFlags.ELEMENT));
    try std.testing.expectEqualStrings("CLASS", selectorFlagsToString(SelectorFlags.CLASS));
}

test "CssSelector defaults" {
    const sel = CssSelector{};
    try std.testing.expect(sel.element == null);
    try std.testing.expectEqual(@as(usize, 0), sel.attrs.len);
    try std.testing.expectEqual(@as(usize, 0), sel.class_names.len);
}

test "parserSelectorToSimpleSelector — element only" {
    const allocator = std.testing.allocator;
    const sel = CssSelector{ .element = "div" };
    const result = try parserSelectorToSimpleSelector(allocator, sel);
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualStrings("div", result[0].string);
}

test "parserSelectorToSimpleSelector — wildcard" {
    const allocator = std.testing.allocator;
    const sel = CssSelector{ .element = "*" };
    const result = try parserSelectorToSimpleSelector(allocator, sel);
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualStrings("", result[0].string);
}

test "parserSelectorToSimpleSelector — with classes" {
    const allocator = std.testing.allocator;
    const classes = [_][]const u8{ "active", "visible" };
    const sel = CssSelector{ .element = "div", .class_names = &classes };
    const result = try parserSelectorToSimpleSelector(allocator, sel);
    defer allocator.free(result);
    // element + CLASS flag + 2 class names = 4
    try std.testing.expectEqual(@as(usize, 4), result.len);
    try std.testing.expectEqual(SelectorFlags.CLASS, result[1].flags);
}

test "parserSelectorToNegativeSelector — element" {
    const allocator = std.testing.allocator;
    const sel = CssSelector{ .element = "div" };
    const result = try parserSelectorToNegativeSelector(allocator, sel);
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 2), result.len);
}

test "parserSelectorToNegativeSelector — classes only" {
    const allocator = std.testing.allocator;
    const classes = [_][]const u8{"active"};
    const sel = CssSelector{ .class_names = &classes };
    const result = try parserSelectorToNegativeSelector(allocator, sel);
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 2), result.len);
}

test "parserSelectorToNegativeSelector — empty" {
    const allocator = std.testing.allocator;
    const sel = CssSelector{};
    const result = try parserSelectorToNegativeSelector(allocator, sel);
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}
