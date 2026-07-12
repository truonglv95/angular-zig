/// HTML Tag Definitions — comptime static tables
///
/// DOD: StaticStringMap with comptime init → no runtime init cost.
/// Lookup is O(1) hash + direct comparison.
const std = @import("std");

pub const Namespace = enum(u8) { HTML, SVG, MathML };

/// Void elements — no closing tag allowed
pub const VOID_ELEMENTS = std.StaticStringMap(void).initComptime(.{
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
});

/// SVG elements
pub const SVG_ELEMENTS = std.StaticStringMap(void).initComptime(.{
    .{"svg"},
    .{"animate"},
    .{"circle"},
    .{"clipPath"},
    .{"defs"},
    .{"desc"},
    .{"ellipse"},
    .{"feBlend"},
    .{"feColorMatrix"},
    .{"feComponentTransfer"},
    .{"feComposite"},
    .{"feConvolveMatrix"},
    .{"feDiffuseLighting"},
    .{"feDisplacementMap"},
    .{"feDistantLight"},
    .{"feFlood"},
    .{"feGaussianBlur"},
    .{"feImage"},
    .{"feMerge"},
    .{"feMergeNode"},
    .{"feMorphology"},
    .{"feOffset"},
    .{"fePointLight"},
    .{"feSpecularLighting"},
    .{"feSpotLight"},
    .{"feTile"},
    .{"feTurbulence"},
    .{"filter"},
    .{"foreignObject"},
    .{"g"},
    .{"image"},
    .{"line"},
    .{"linearGradient"},
    .{"marker"},
    .{"mask"},
    .{"metadata"},
    .{"path"},
    .{"pattern"},
    .{"polygon"},
    .{"polyline"},
    .{"radialGradient"},
    .{"rect"},
    .{"stop"},
    .{"switch"},
    .{"symbol"},
    .{"text"},
    .{"textPath"},
    .{"tspan"},
    .{"use"},
    .{"view"},
});

/// MathML elements
pub const MATHML_ELEMENTS = std.StaticStringMap(void).initComptime(.{
    .{"math"},
    .{"mi"},
    .{"mn"},
    .{"mo"},
    .{"ms"},
    .{"mtext"},
    .{"annotation"},
    .{"annotation-xml"},
});

/// Elements that preserve whitespace inside
pub const PRESERVE_WHITESPACE_ELEMENTS = std.StaticStringMap(void).initComptime(.{
    .{"pre"},
    .{"textarea"},
    .{"code"},
});

/// Raw text elements (content is not parsed as HTML)
pub const RAW_TEXT_ELEMENTS = std.StaticStringMap(void).initComptime(.{
    .{"script"},
    .{"style"},
    .{"noscript"},
    .{"iframe"},
    .{"noembed"},
    .{"noframes"},
    .{"plaintext"},
    .{"xmp"},
});

/// Elements that can contain phrasing content only
pub const PHRASING_CONTENT_ELEMENTS = std.StaticStringMap(void).initComptime(.{
    .{"a"},
    .{"abbr"},
    .{"area"},
    .{"audio"},
    .{"b"},
    .{"bdi"},
    .{"bdo"},
    .{"br"},
    .{"button"},
    .{"canvas"},
    .{"cite"},
    .{"code"},
    .{"data"},
    .{"datalist"},
    .{"del"},
    .{"dfn"},
    .{"em"},
    .{"embed"},
    .{"i"},
    .{"iframe"},
    .{"img"},
    .{"input"},
    .{"ins"},
    .{"kbd"},
    .{"keygen"},
    .{"label"},
    .{"link"},
    .{"map"},
    .{"mark"},
    .{"meter"},
    .{"nav"},
    .{"noscript"},
    .{"object"},
    .{"output"},
    .{"picture"},
    .{"progress"},
    .{"q"},
    .{"ruby"},
    .{"s"},
    .{"samp"},
    .{"script"},
    .{"select"},
    .{"small"},
    .{"span"},
    .{"strong"},
    .{"sub"},
    .{"sup"},
    .{"template"},
    .{"textarea"},
    .{"time"},
    .{"u"},
    .{"var"},
    .{"video"},
    .{"wbr"},
});

/// Check if element is void (self-closing)
pub fn isVoidElement(name: []const u8) bool {
    return VOID_ELEMENTS.has(name);
}

/// Get namespace for element name
pub fn getNamespace(name: []const u8) Namespace {
    if (SVG_ELEMENTS.has(name)) return .SVG;
    if (MATHML_ELEMENTS.has(name)) return .MathML;
    return .HTML;
}

/// Check if element preserves whitespace
pub fn preservesWhitespace(name: []const u8) bool {
    return PRESERVE_WHITESPACE_ELEMENTS.has(name);
}

/// Check if element has raw text content
pub fn isRawTextElement(name: []const u8) bool {
    return RAW_TEXT_ELEMENTS.has(name);
}

// ─── Tests ────────────────────────────────────────────────────

test "void elements" {
    try std.testing.expect(isVoidElement("br"));
    try std.testing.expect(isVoidElement("input"));
    try std.testing.expect(!isVoidElement("div"));
}

test "namespace detection" {
    try std.testing.expectEqual(Namespace.HTML, getNamespace("div"));
    try std.testing.expectEqual(Namespace.SVG, getNamespace("svg"));
    try std.testing.expectEqual(Namespace.SVG, getNamespace("circle"));
    try std.testing.expectEqual(Namespace.MathML, getNamespace("math"));
}

test "raw text elements" {
    try std.testing.expect(isRawTextElement("script"));
    try std.testing.expect(isRawTextElement("style"));
    try std.testing.expect(!isRawTextElement("div"));
}
