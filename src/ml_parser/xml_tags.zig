/// XML Tags — XML tag definitions
///
/// Port of: compiler/src/ml_parser/xml_tags.ts (36 LoC)
const std = @import("std");

/// XML tag definition (simpler than HTML — no void elements, no namespaces).
pub const XmlTagDefinition = struct {
    name: []const u8,
};

/// Get the tag definition for an XML tag name.
pub fn getXmlTagDefinition(name: []const u8) XmlTagDefinition {
    return .{ .name = name };
}
