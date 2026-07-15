/// Element Schema Registry — Abstract interface for DOM schema
///
/// Port of: compiler/src/schema/element_schema_registry.ts (30 LoC)
///
/// Abstract interface for schema registries. Implementations (DomElementSchemaRegistry)
/// know about HTML elements and their properties.
const std = @import("std");

/// SecurityContext — re-exported from dom_security_schema.
pub const SecurityContext = @import("dom_security_schema.zig").SecurityContext;

/// SchemaMetadata — metadata about allowed schemas in the template.
pub const SchemaMetadata = struct {
    name: []const u8,
};

/// ValidationResult — result of property/attribute validation.
pub const ValidationResult = struct {
    error_flag: bool = false,
    msg: ?[]const u8 = null,
};

/// StyleValueResult — result of animation style value normalization.
pub const StyleValueResult = struct {
    error_msg: []const u8 = "",
    value: []const u8 = "",
};

/// ElementSchemaRegistry — abstract interface for DOM schema registries.
/// Direct port of `ElementSchemaRegistry` abstract class in the TS source.
///
/// In the TS source, this is an abstract class with abstract methods.
/// In Zig, we model it as a struct with function pointer fields.
/// The DomElementSchemaRegistry provides the concrete implementation.
pub const ElementSchemaRegistry = struct {
    /// Check if a property exists on an element.
    hasProperty_fn: *const fn (tagName: []const u8, propName: []const u8, schemaMetas: []const SchemaMetadata) bool,
    /// Check if an element exists.
    hasElement_fn: *const fn (tagName: []const u8, schemaMetas: []const SchemaMetadata) bool,
    /// Get the security context for an element/property.
    securityContext_fn: *const fn (elementName: []const u8, propName: []const u8, isAttribute: bool) SecurityContext,
    /// Get all known element names.
    allKnownElementNames_fn: *const fn () []const []const u8,
    /// Get the mapped property name (e.g., "for" → "htmlFor").
    getMappedPropName_fn: *const fn (propName: []const u8) []const u8,
    /// Get the default component element name.
    getDefaultComponentElementName_fn: *const fn () []const u8,
    /// Validate a property name.
    validateProperty_fn: *const fn (name: []const u8) ValidationResult,
    /// Validate an attribute name.
    validateAttribute_fn: *const fn (name: []const u8) ValidationResult,
    /// Normalize an animation style property name.
    normalizeAnimationStyleProperty_fn: *const fn (propName: []const u8) []const u8,
    /// Normalize an animation style value.
    normalizeAnimationStyleValue_fn: *const fn (camelCaseProp: []const u8, userProvidedProp: []const u8, val: []const u8) StyleValueResult,

    /// Check if a property exists on an element.
    pub fn hasProperty(self: *const ElementSchemaRegistry, tagName: []const u8, propName: []const u8, schemaMetas: []const SchemaMetadata) bool {
        return self.hasProperty_fn(tagName, propName, schemaMetas);
    }

    /// Check if an element exists.
    pub fn hasElement(self: *const ElementSchemaRegistry, tagName: []const u8, schemaMetas: []const SchemaMetadata) bool {
        return self.hasElement_fn(tagName, schemaMetas);
    }

    /// Get the security context for an element/property.
    pub fn securityContext(self: *const ElementSchemaRegistry, elementName: []const u8, propName: []const u8, isAttribute: bool) SecurityContext {
        return self.securityContext_fn(elementName, propName, isAttribute);
    }

    /// Get all known element names.
    pub fn allKnownElementNames(self: *const ElementSchemaRegistry) []const []const u8 {
        return self.allKnownElementNames_fn();
    }

    /// Get the mapped property name.
    pub fn getMappedPropName(self: *const ElementSchemaRegistry, propName: []const u8) []const u8 {
        return self.getMappedPropName_fn(propName);
    }

    /// Get the default component element name.
    pub fn getDefaultComponentElementName(self: *const ElementSchemaRegistry) []const u8 {
        return self.getDefaultComponentElementName_fn();
    }

    /// Validate a property name.
    pub fn validateProperty(self: *const ElementSchemaRegistry, name: []const u8) ValidationResult {
        return self.validateProperty_fn(name);
    }

    /// Validate an attribute name.
    pub fn validateAttribute(self: *const ElementSchemaRegistry, name: []const u8) ValidationResult {
        return self.validateAttribute_fn(name);
    }

    /// Normalize an animation style property name.
    pub fn normalizeAnimationStyleProperty(self: *const ElementSchemaRegistry, propName: []const u8) []const u8 {
        return self.normalizeAnimationStyleProperty_fn(propName);
    }

    /// Normalize an animation style value.
    pub fn normalizeAnimationStyleValue(self: *const ElementSchemaRegistry, camelCaseProp: []const u8, userProvidedProp: []const u8, val: []const u8) StyleValueResult {
        return self.normalizeAnimationStyleValue_fn(camelCaseProp, userProvidedProp, val);
    }
};

// ─── Tests ──────────────────────────────────────────────────

test "SchemaMetadata defaults" {
    const meta = SchemaMetadata{ .name = "CUSTOM_ELEMENTS_SCHEMA" };
    try std.testing.expectEqualStrings("CUSTOM_ELEMENTS_SCHEMA", meta.name);
}

test "ValidationResult defaults" {
    const result = ValidationResult{};
    try std.testing.expect(!result.error_flag);
    try std.testing.expect(result.msg == null);
}

test "StyleValueResult defaults" {
    const result = StyleValueResult{};
    try std.testing.expectEqualStrings("", result.error_msg);
    try std.testing.expectEqualStrings("", result.value);
}

test "SecurityContext re-export" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(SecurityContext.NONE));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(SecurityContext.HTML));
}
