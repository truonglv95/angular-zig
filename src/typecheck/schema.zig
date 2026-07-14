/// TCB Schema — DOM schema checker for type checking
///
/// Port of: compiler/src/typecheck/schema.ts (84 LoC)
///
/// The DomSchemaChecker checks every non-Angular element/property processed
/// in a template and produces diagnostics related to improper usage. It
/// validates that DOM nodes and their attributes conform to the DOM spec.
const std = @import("std");

/// SchemaMetadata — metadata about allowed schemas in the template.
pub const SchemaMetadata = struct {
    name: []const u8,
};

/// TypeCheckId — a unique identifier for a type check block.
pub const TypeCheckId = u32;

/// DomSchemaDiagnostic — a diagnostic produced by the DOM schema checker.
pub const DomSchemaDiagnostic = struct {
    /// The template ID where the error was found.
    id: TypeCheckId,
    /// The error message.
    msg: []const u8,
    /// The tag name of the element that caused the error.
    tag_name: ?[]const u8 = null,
    /// The property name that caused the error (if applicable).
    property_name: ?[]const u8 = null,
    /// Source span for error reporting.
    source_span: ?[]const u8 = null,
};

/// DomSchemaChecker — checks DOM elements and properties for validity.
/// Direct port of `DomSchemaChecker<T>` interface in the TS source.
pub const DomSchemaChecker = struct {
    allocator: std.mem.Allocator,
    /// Diagnostics collected by the checker.
    diagnostics: std.array_list.Managed(DomSchemaDiagnostic),

    pub fn init(allocator: std.mem.Allocator) DomSchemaChecker {
        return .{
            .allocator = allocator,
            .diagnostics = std.array_list.Managed(DomSchemaDiagnostic).init(allocator),
        };
    }

    pub fn deinit(self: *DomSchemaChecker) void {
        self.diagnostics.deinit();
    }

    /// Check a non-Angular element and record any diagnostics about it.
    /// Direct port of `checkElement(id, tagName, sourceSpan, schemas, hostIsStandalone)` in the TS source.
    pub fn checkElement(
        self: *DomSchemaChecker,
        id: TypeCheckId,
        tag_name: []const u8,
        schemas: []const SchemaMetadata,
        host_is_standalone: bool,
    ) !void {
        _ = host_is_standalone;

        // Check if the element is allowed by the schemas.
        if (!isElementAllowed(tag_name, schemas)) {
            try self.diagnostics.append(.{
                .id = id,
                .msg = "'{s}' is not a known element",
                .tag_name = tag_name,
            });
        }
    }

    /// Check a property binding on a template element.
    /// Direct port of `checkTemplateElementProperty(...)` in the TS source.
    pub fn checkTemplateElementProperty(
        self: *DomSchemaChecker,
        id: TypeCheckId,
        tag_name: []const u8,
        name: []const u8,
        schemas: []const SchemaMetadata,
        host_is_standalone: bool,
    ) !void {
        _ = host_is_standalone;

        if (!isPropertyAllowed(tag_name, name, schemas)) {
            try self.diagnostics.append(.{
                .id = id,
                .msg = "'{s}' is not a known property of '{s}'",
                .tag_name = tag_name,
                .property_name = name,
            });
        }
    }

    /// Check a property binding on a host element.
    /// Direct port of `checkHostElementProperty(...)` in the TS source.
    pub fn checkHostElementProperty(
        self: *DomSchemaChecker,
        id: TypeCheckId,
        tag_name: []const u8,
        name: []const u8,
        schemas: []const SchemaMetadata,
    ) !void {
        if (!isPropertyAllowed(tag_name, name, schemas)) {
            try self.diagnostics.append(.{
                .id = id,
                .msg = "'{s}' is not a known host property of '{s}'",
                .tag_name = tag_name,
                .property_name = name,
            });
        }
    }

    /// Check if any diagnostics have been recorded.
    pub fn hasDiagnostics(self: *const DomSchemaChecker) bool {
        return self.diagnostics.items.len > 0;
    }
};

/// Check if an element is allowed by the schemas.
/// The full implementation would consult DomElementSchemaRegistry.
fn isElementAllowed(tag_name: []const u8, schemas: []const SchemaMetadata) bool {
    // Check for custom element schemas (CUSTOM_ELEMENTS_SCHEMA, NO_ERRORS_SCHEMA).
    for (schemas) |schema| {
        if (std.mem.eql(u8, schema.name, "CUSTOM_ELEMENTS_SCHEMA") or
            std.mem.eql(u8, schema.name, "NO_ERRORS_SCHEMA"))
        {
            return true;
        }
    }
    // Check common HTML elements.
    return isKnownHtmlElement(tag_name);
}

/// Check if a property is allowed on an element.
fn isPropertyAllowed(tag_name: []const u8, prop_name: []const u8, schemas: []const SchemaMetadata) bool {
    for (schemas) |schema| {
        if (std.mem.eql(u8, schema.name, "NO_ERRORS_SCHEMA")) {
            return true;
        }
    }
    // Check common HTML properties.
    _ = tag_name;
    return isKnownHtmlProperty(prop_name);
}

/// Check if a tag name is a known HTML element.
fn isKnownHtmlElement(tag_name: []const u8) bool {
    const known_elements = [_][]const u8{
        "div", "span", "p", "a", "img", "input", "button", "form",
        "label", "select", "option", "textarea", "table", "tr", "td", "th",
        "thead", "tbody", "ul", "ol", "li", "h1", "h2", "h3", "h4", "h5", "h6",
        "br", "hr", "link", "script", "style", "meta", "head", "body", "html",
        "nav", "header", "footer", "main", "section", "article", "aside",
    };
    for (known_elements) |elem| {
        if (std.mem.eql(u8, tag_name, elem)) return true;
    }
    return false;
}

/// Check if a property name is a known HTML property.
fn isKnownHtmlProperty(prop_name: []const u8) bool {
    const known_props = [_][]const u8{
        "class", "id", "style", "title", "href", "src", "alt", "value",
        "type", "name", "placeholder", "disabled", "readonly", "checked",
        "selected", "required", "hidden", "tabindex", "role", "aria-label",
        "innerHTML", "outerHTML", "textContent",
    };
    for (known_props) |prop| {
        if (std.mem.eql(u8, prop_name, prop)) return true;
    }
    return false;
}

// ─── Tests ──────────────────────────────────────────────────

test "DomSchemaChecker init/deinit" {
    const allocator = std.testing.allocator;
    var checker = DomSchemaChecker.init(allocator);
    defer checker.deinit();
    try std.testing.expect(!checker.hasDiagnostics());
}

test "checkElement allows known elements" {
    const allocator = std.testing.allocator;
    var checker = DomSchemaChecker.init(allocator);
    defer checker.deinit();

    try checker.checkElement(0, "div", &.{}, false);
    try std.testing.expect(!checker.hasDiagnostics());
}

test "checkElement rejects unknown elements" {
    const allocator = std.testing.allocator;
    var checker = DomSchemaChecker.init(allocator);
    defer checker.deinit();

    try checker.checkElement(0, "my-unknown-element", &.{}, false);
    try std.testing.expect(checker.hasDiagnostics());
}

test "checkElement allows custom elements with schema" {
    const allocator = std.testing.allocator;
    var checker = DomSchemaChecker.init(allocator);
    defer checker.deinit();

    const schemas = [_]SchemaMetadata{.{ .name = "CUSTOM_ELEMENTS_SCHEMA" }};
    try checker.checkElement(0, "my-custom-element", &schemas, false);
    try std.testing.expect(!checker.hasDiagnostics());
}

test "checkTemplateElementProperty allows known props" {
    const allocator = std.testing.allocator;
    var checker = DomSchemaChecker.init(allocator);
    defer checker.deinit();

    try checker.checkTemplateElementProperty(0, "input", "value", &.{}, false);
    try std.testing.expect(!checker.hasDiagnostics());
}

test "checkTemplateElementProperty rejects unknown props" {
    const allocator = std.testing.allocator;
    var checker = DomSchemaChecker.init(allocator);
    defer checker.deinit();

    try checker.checkTemplateElementProperty(0, "div", "unknownProp", &.{}, false);
    try std.testing.expect(checker.hasDiagnostics());
}

test "isKnownHtmlElement" {
    try std.testing.expect(isKnownHtmlElement("div"));
    try std.testing.expect(isKnownHtmlElement("span"));
    try std.testing.expect(isKnownHtmlElement("input"));
    try std.testing.expect(!isKnownHtmlElement("my-custom-element"));
}

test "isKnownHtmlProperty" {
    try std.testing.expect(isKnownHtmlProperty("class"));
    try std.testing.expect(isKnownHtmlProperty("href"));
    try std.testing.expect(isKnownHtmlProperty("innerHTML"));
    try std.testing.expect(!isKnownHtmlProperty("unknownProp"));
}
