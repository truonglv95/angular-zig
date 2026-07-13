/// Element Schema Registry — Abstract interface for DOM schema
///
/// Port of: compiler/src/schema/element_schema_registry.ts
const std = @import("std");

/// Abstract interface for schema registries.
/// Implementations (DomElementSchemaRegistry) know about HTML elements/properties.
pub const ElementSchemaRegistry = struct {
    hasProperty: *const fn (self: *const ElementSchemaRegistry, name: []const u8) bool,
    hasElement: *const fn (self: *const ElementSchemaRegistry, name: []const u8) bool,
    getMappedPropName: *const fn (self: *const ElementSchemaRegistry, name: []const u8) []const u8,
    securityContext: *const fn (self: *const ElementSchemaRegistry, name: []const u8) ?u8,
    allKnownElementNames: *const fn (self: *const ElementSchemaRegistry) []const []const u8,
};
