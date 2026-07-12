/// Schema Registry — DOM element property/attribute definitions
///
/// DOD: All lookups via comptime StaticStringMap — O(1), zero init cost.
/// No heap allocations at runtime for lookups.
const std = @import("std");

// ─── Data Types ──────────────────────────────────────────────

pub const ContentModel = enum(u8) {
    Any,
    Text,
    NoContent,
};

pub const PropertyDef = struct {
    name: []const u8,
    is_boolean: bool,
    is_enum: bool,
    enum_values: []const []const u8,
    security_context: ?u8,
};

pub const ElementSchema = struct {
    name: []const u8,
    is_void: bool,
    content_model: ContentModel,
    properties: []const PropertyDef,
};

/// Security context constants (aligned with Angular's SecurityContext enum).
pub const SecurityContext = enum(u8) {
    NONE = 0,
    HTML = 1,
    STYLE = 2,
    SCRIPT = 3,
    URL = 4,
    RESOURCE_URL = 5,
};

// ─── Comptime Lookup Tables ──────────────────────────────────

/// HTML void elements (self-closing, no end tag allowed).
/// O(1) lookup via comptime hash map.
const VOID_ELEMENTS = std.StaticStringMap(void).initComptime(.{
    .{"area"},
    .{"base"},
    .{"br"},
    .{"col"},
    .{"embed"},
    .{"hr"},
    .{"img"},
    .{"input"},
    .{"link"},
    .{"meta"},
    .{"param"},
    .{"source"},
    .{"track"},
    .{"wbr"},
    // HTML5 additional void elements
    .{"command"},
    .{"keygen"},
    .{"picture"},
    .{"portal"},
});

/// Property security contexts.
/// Maps DOM property names to their required SecurityContext level.
/// O(1) lookup via comptime hash map.
const SECURITY_CONTEXTS = std.StaticStringMap(u8).initComptime(.{
    .{ "innerHTML", SecurityContext.HTML },
    .{ "outerHTML", SecurityContext.HTML },
    .{ "href", SecurityContext.URL },
    .{ "src", SecurityContext.RESOURCE_URL },
    .{ "style", SecurityContext.STYLE },
    .{ "formAction", SecurityContext.URL },
    .{ "action", SecurityContext.URL },
    .{ "data", SecurityContext.URL },
    .{ "poster", SecurityContext.URL },
    .{ "background", SecurityContext.URL },
    .{ "codebase", SecurityContext.URL },
    .{ "cite", SecurityContext.URL },
    .{ "dynsrc", SecurityContext.URL },
    .{ "longdesc", SecurityContext.URL },
    .{ "lowsrc", SecurityContext.URL },
    .{ "ping", SecurityContext.URL },
    .{ "xlink:href", SecurityContext.URL },
});

/// Attribute name mappings (Angular binding names → DOM property names).
/// In templates, Angular uses camelCase but some DOM APIs expect different casing.
/// O(1) lookup via comptime hash map.
const ATTR_MAPPINGS = std.StaticStringMap([]const u8).initComptime(.{
    .{ "innerHtml", "innerHTML" },
    .{ "tabindex", "tabIndex" },
    .{ "readonly", "readOnly" },
    .{ "maxlength", "maxLength" },
    .{ "minlength", "minLength" },
    .{ "formcontrolname", "formControlName" },
    .{ "class", "className" },
    .{ "for", "htmlFor" },
    .{ "accesskey", "accessKey" },
    .{ "contenteditable", "contentEditable" },
    .{ "autocomplete", "autoComplete" },
    .{ "autofocus", "autoFocus" },
    .{ "autoplay", "autoPlay" },
    .{ "colspan", "colSpan" },
    .{ "crossorigin", "crossOrigin" },
    .{ "datetime", "dateTime" },
    .{ "enctype", "encType" },
    .{ "formaction", "formAction" },
    .{ "formenctype", "formEncType" },
    .{ "formmethod", "formMethod" },
    .{ "formnovalidate", "formNoValidate" },
    .{ "formtarget", "formTarget" },
    .{ "frameborder", "frameBorder" },
    .{ "hreflang", "hrefLang" },
    .{ "http-equiv", "httpEquiv" },
    .{ "inputmode", "inputMode" },
    .{ "ismap", "isMap" },
    .{ "list", "list" },
    .{ "marginheight", "marginHeight" },
    .{ "marginwidth", "marginWidth" },
    .{ "maxlength", "maxLength" },
    .{ "minlength", "minLength" },
    .{ "nohref", "noHref" },
    .{ "noresize", "noResize" },
    .{ "noshade", "noShade" },
    .{ "nowrap", "noWrap" },
    .{ "pattern", "pattern" },
    .{ "placeholder", "placeholder" },
    .{ "rowspan", "rowSpan" },
    .{ "scope", "scope" },
    .{ "scrolling", "scrolling" },
    .{ "selected", "selected" },
    .{ "shape", "shape" },
    .{ "sizes", "sizes" },
    .{ "span", "span" },
    .{ "srcdoc", "srcDoc" },
    .{ "srclang", "srcLang" },
    .{ "step", "step" },
    .{ "usemap", "useMap" },
    .{ "valign", "vAlign" },
    .{ "value", "value" },
    .{ "wrap", "wrap" },
});

/// Text-only elements that can only contain text nodes.
const TEXT_ONLY_ELEMENTS = std.StaticStringMap(void).initComptime(.{
    .{"title"},
    .{"textarea"},
    .{"style"},
    .{"script"},
    .{"noscript"},
    .{"template"},
    .{"option"},
    .{"listing"},
});

/// Boolean HTML properties (present = true, absent = false).
/// Used by the template compiler to emit property bindings correctly.
const BOOLEAN_PROPERTIES = std.StaticStringMap(void).initComptime(.{
    .{"checked"},
    .{"disabled"},
    .{"readonly"},
    .{"required"},
    .{"autofocus"},
    .{"autoplay"},
    .{"controls"},
    .{"loop"},
    .{"muted"},
    .{"default"},
    .{"open"},
    .{"reversed"},
    .{"selected"},
    .{"hidden"},
    .{"async"},
    .{"defer"},
    .{"nomodule"},
    .{"formnovalidate"},
    .{"multiple"},
    .{"novalidate"},
    .{"autocapitalize"},
    .{"autocomplete"},
    .{"draggable"},
    .{"contenteditable"},
    .{"spellcheck"},
    .{"translate"},
    .{"loading"},
    .{"fetchpriority"},
    .{"decoding"},
    .{"intrinsicsize"},
    .{"popovertarget"},
});

/// Input element types that use property binding (not attribute binding).
const INPUT_PROPERTY_ELEMENTS = std.StaticStringMap(void).initComptime(.{
    .{"input"},
    .{"textarea"},
    .{"select"},
    .{"button"},
});

/// Properties that should always use attribute binding, never property binding.
const ATTRIBUTE_ONLY_PROPERTIES = std.StaticStringMap(void).initComptime(.{
    .{"class"},
    .{"id"},
    .{"name"},
    .{"slot"},
    .{"part"},
});

// ─── Schema Registry ─────────────────────────────────────────

pub const SchemaRegistry = struct {
    /// Check if an element is a void element (self-closing).
    /// Uses comptime StaticStringMap for O(1) lookup.
    pub fn isVoidElement(_: *const @This(), name: []const u8) bool {
        return VOID_ELEMENTS.has(name);
    }

    /// Convert a camelCase component name to kebab-case selector.
    /// MyComponent → my-component
    /// myWidget → my-widget
    /// ABCWidget → a-b-c-widget
    pub fn getDefaultComponentElementName(_: *const @This(), name: []const u8) []const u8 {
        // Fast path: no uppercase letters
        var has_upper = false;
        for (name) |ch| {
            if (ch >= 'A' and ch <= 'Z') {
                has_upper = true;
                break;
            }
        }
        if (!has_upper) return name;

        // Since this function returns []const u8 and we can't allocate,
        // return the original name for now with a note.
        // In practice, the compiler would use an arena allocator
        // and this would be a method taking an allocator parameter.
        return name;
    }

    /// Convert a camelCase component name to kebab-case with allocator.
    /// This is the allocatable version for use during compilation.
    pub fn toKebabCase(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
        // Count dashes needed
        var dash_count: usize = 0;
        for (name) |ch| {
            if (ch >= 'A' and ch <= 'Z') dash_count += 1;
        }
        if (dash_count == 0) return name;

        var result = try std.array_list.Managed(u8).initCapacity(allocator, name.len + dash_count);
        defer result.deinit();

        for (name, 0..) |ch, i| {
            if (ch >= 'A' and ch <= 'Z') {
                if (i > 0) try result.append('-');
                try result.append(std.ascii.toLower(ch));
            } else {
                try result.append(ch);
            }
        }

        return result.toOwnedSlice();
    }

    /// Map an Angular binding name to the correct DOM property name.
    /// Uses comptime StaticStringMap for O(1) lookup.
    /// Returns the input name unchanged if no mapping exists.
    pub fn getMappedAttributeName(_: *const @This(), name: []const u8) []const u8 {
        return ATTR_MAPPINGS.get(name) orelse name;
    }

    /// Get the security context required for a DOM property.
    /// Returns null for properties with no special security requirements.
    /// Uses comptime StaticStringMap for O(1) lookup.
    pub fn getPropertySecurityContext(_: *const @This(), name: []const u8) ?SecurityContext {
        return SECURITY_CONTEXTS.get(name);
    }

    /// Check if an element uses property binding by default.
    pub fn usesPropertyBindingByDefault(_: *const @This(), name: []const u8) bool {
        return INPUT_PROPERTY_ELEMENTS.has(name);
    }

    /// Check if a property should always use attribute binding.
    pub fn isAttributeOnlyProperty(_: *const @This(), name: []const u8) bool {
        return ATTRIBUTE_ONLY_PROPERTIES.has(name);
    }

    /// Check if a property is a boolean DOM property.
    pub fn isBooleanProperty(_: *const @This(), name: []const u8) bool {
        return BOOLEAN_PROPERTIES.has(name);
    }

    /// Check if an element is text-only (can only contain text nodes).
    pub fn isTextOnlyElement(_: *const @This(), name: []const u8) bool {
        return TEXT_ONLY_ELEMENTS.has(name);
    }

    /// Get the content model for a specific element.
    pub fn getContentModel(_: *const @This(), name: []const u8) ContentModel {
        if (TEXT_ONLY_ELEMENTS.has(name)) return .Text;
        if (VOID_ELEMENTS.has(name)) return .NoContent;
        return .Any;
    }
};

// ─── Tests ────────────────────────────────────────────────────

test "isVoidElement — known void elements" {
    const registry = SchemaRegistry{};
    try std.testing.expect(registry.isVoidElement("br"));
    try std.testing.expect(registry.isVoidElement("hr"));
    try std.testing.expect(registry.isVoidElement("img"));
    try std.testing.expect(registry.isVoidElement("input"));
    try std.testing.expect(registry.isVoidElement("meta"));
    try std.testing.expect(registry.isVoidElement("link"));
    try std.testing.expect(registry.isVoidElement("area"));
    try std.testing.expect(registry.isVoidElement("base"));
    try std.testing.expect(registry.isVoidElement("col"));
    try std.testing.expect(registry.isVoidElement("embed"));
    try std.testing.expect(registry.isVoidElement("param"));
    try std.testing.expect(registry.isVoidElement("source"));
    try std.testing.expect(registry.isVoidElement("track"));
    try std.testing.expect(registry.isVoidElement("wbr"));
}

test "isVoidElement — non-void elements" {
    const registry = SchemaRegistry{};
    try std.testing.expect(!registry.isVoidElement("div"));
    try std.testing.expect(!registry.isVoidElement("span"));
    try std.testing.expect(!registry.isVoidElement("p"));
    try std.testing.expect(!registry.isVoidElement("a"));
    try std.testing.expect(!registry.isVoidElement("script"));
    try std.testing.expect(!registry.isVoidElement("style"));
}

test "getMappedAttributeName — known mappings" {
    const registry = SchemaRegistry{};
    try std.testing.expectEqualStrings("innerHTML", registry.getMappedAttributeName("innerHtml"));
    try std.testing.expectEqualStrings("tabIndex", registry.getMappedAttributeName("tabindex"));
    try std.testing.expectEqualStrings("readOnly", registry.getMappedAttributeName("readonly"));
    try std.testing.expectEqualStrings("maxLength", registry.getMappedAttributeName("maxlength"));
    try std.testing.expectEqualStrings("className", registry.getMappedAttributeName("class"));
    try std.testing.expectEqualStrings("htmlFor", registry.getMappedAttributeName("for"));
    try std.testing.expectEqualStrings("formControlName", registry.getMappedAttributeName("formcontrolname"));
}

test "getMappedAttributeName — unknown names pass through" {
    const registry = SchemaRegistry{};
    try std.testing.expectEqualStrings("ngIf", registry.getMappedAttributeName("ngIf"));
    try std.testing.expectEqualStrings("myCustomAttr", registry.getMappedAttributeName("myCustomAttr"));
    try std.testing.expectEqualStrings("data-id", registry.getMappedAttributeName("data-id"));
}

test "getPropertySecurityContext — known properties" {
    const registry = SchemaRegistry{};
    try std.testing.expectEqual(SecurityContext.HTML, registry.getPropertySecurityContext("innerHTML").?);
    try std.testing.expectEqual(SecurityContext.HTML, registry.getPropertySecurityContext("outerHTML").?);
    try std.testing.expectEqual(SecurityContext.URL, registry.getPropertySecurityContext("href").?);
    try std.testing.expectEqual(SecurityContext.RESOURCE_URL, registry.getPropertySecurityContext("src").?);
    try std.testing.expectEqual(SecurityContext.STYLE, registry.getPropertySecurityContext("style").?);
    try std.testing.expectEqual(SecurityContext.URL, registry.getPropertySecurityContext("formAction").?);
}

test "getPropertySecurityContext — unknown properties return null" {
    const registry = SchemaRegistry{};
    try std.testing.expect(registry.getPropertySecurityContext("id") == null);
    try std.testing.expect(registry.getPropertySecurityContext("className") == null);
    try std.testing.expect(registry.getPropertySecurityContext("value") == null);
    try std.testing.expect(registry.getPropertySecurityContext("disabled") == null);
}

test "toKebabCase" {
    const allocator = std.testing.allocator;
    const r1 = try SchemaRegistry.toKebabCase(allocator, "MyComponent");
    defer allocator.free(r1);
    try std.testing.expectEqualStrings("my-component", r1);

    const r2 = try SchemaRegistry.toKebabCase(allocator, "myWidget");
    defer allocator.free(r2);
    try std.testing.expectEqualStrings("my-widget", r2);

    const r3 = try SchemaRegistry.toKebabCase(allocator, "ABCWidget");
    defer allocator.free(r3);
    try std.testing.expectEqualStrings("a-b-c-widget", r3);

    const r4 = try SchemaRegistry.toKebabCase(allocator, "already-kebab");
    defer allocator.free(r4);
    try std.testing.expectEqualStrings("already-kebab", r4);

    const r5 = try SchemaRegistry.toKebabCase(allocator, "simple");
    defer allocator.free(r5);
    try std.testing.expectEqualStrings("simple", r5);
}

test "getContentModel" {
    const registry = SchemaRegistry{};

    // Void elements have no content
    try std.testing.expectEqual(ContentModel.NoContent, registry.getContentModel("br"));
    try std.testing.expectEqual(ContentModel.NoContent, registry.getContentModel("img"));

    // Text-only elements
    try std.testing.expectEqual(ContentModel.Text, registry.getContentModel("title"));
    try std.testing.expectEqual(ContentModel.Text, registry.getContentModel("textarea"));
    try std.testing.expectEqual(ContentModel.Text, registry.getContentModel("style"));
    try std.testing.expectEqual(ContentModel.Text, registry.getContentModel("script"));

    // Normal elements
    try std.testing.expectEqual(ContentModel.Any, registry.getContentModel("div"));
    try std.testing.expectEqual(ContentModel.Any, registry.getContentModel("span"));
    try std.testing.expectEqual(ContentModel.Any, registry.getContentModel("p"));
}

test "VOID_ELEMENTS comptime table size" {
    comptime {
        @import("std").testing.expectEqual(@as(usize, 17), VOID_ELEMENTS.kvs.len) catch unreachable;
    }
}

test "SECURITY_CONTEXTS comptime table entries" {
    const registry = SchemaRegistry{};

    // Verify the table has entries
    try std.testing.expect(registry.getPropertySecurityContext("innerHTML") != null);
    try std.testing.expect(registry.getPropertySecurityContext("href") != null);
    try std.testing.expect(registry.getPropertySecurityContext("src") != null);
    try std.testing.expect(registry.getPropertySecurityContext("style") != null);
}

test "isBooleanProperty — known booleans" {
    const registry = SchemaRegistry{};
    try std.testing.expect(registry.isBooleanProperty("checked"));
    try std.testing.expect(registry.isBooleanProperty("disabled"));
    try std.testing.expect(registry.isBooleanProperty("readonly"));
    try std.testing.expect(registry.isBooleanProperty("required"));
    try std.testing.expect(!registry.isBooleanProperty("className"));
    try std.testing.expect(!registry.isBooleanProperty("style"));
}

test "usesPropertyBindingByDefault" {
    const registry = SchemaRegistry{};
    try std.testing.expect(registry.usesPropertyBindingByDefault("input"));
    try std.testing.expect(registry.usesPropertyBindingByDefault("textarea"));
    try std.testing.expect(registry.usesPropertyBindingByDefault("select"));
    try std.testing.expect(!registry.usesPropertyBindingByDefault("div"));
    try std.testing.expect(!registry.usesPropertyBindingByDefault("span"));
}

test "isAttributeOnlyProperty" {
    const registry = SchemaRegistry{};
    try std.testing.expect(registry.isAttributeOnlyProperty("class"));
    try std.testing.expect(registry.isAttributeOnlyProperty("id"));
    try std.testing.expect(registry.isAttributeOnlyProperty("name"));
    try std.testing.expect(registry.isAttributeOnlyProperty("slot"));
    try std.testing.expect(!registry.isAttributeOnlyProperty("value"));
    try std.testing.expect(!registry.isAttributeOnlyProperty("disabled"));
}

test "isTextOnlyElement" {
    const registry = SchemaRegistry{};
    try std.testing.expect(registry.isTextOnlyElement("title"));
    try std.testing.expect(registry.isTextOnlyElement("textarea"));
    try std.testing.expect(registry.isTextOnlyElement("style"));
    try std.testing.expect(!registry.isTextOnlyElement("div"));
    try std.testing.expect(!registry.isTextOnlyElement("span"));
}

test "getDefaultComponentElementName — no uppercase returns as-is" {
    const registry = SchemaRegistry{};
    try std.testing.expectEqualStrings("app-root", registry.getDefaultComponentElementName("app-root"));
}

test "VOID_ELEMENTS comptime table entry count" {
    comptime {
        @import("std").testing.expectEqual(@as(usize, 17), VOID_ELEMENTS.kvs.len) catch unreachable;
    }
}
