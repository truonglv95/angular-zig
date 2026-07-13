/// HTML Tags — HTML tag definitions (content type, void-ness, etc.)
///
/// Port of: compiler/src/ml_parser/html_tags.ts (194 LoC)
const std = @import("std");

/// Content model for HTML elements.
pub const TagContentType = enum(u8) {
    Text, EscapableRawText, RawText, Void,
};

/// HTML tag definition.
pub const HtmlTagDefinition = struct {
    name: []const u8,
    content_type: TagContentType = .Text,
    is_void: bool = false,
    implicit_namespace: ?[]const u8 = null,
};

/// Get the tag definition for an HTML tag name.
pub fn getHtmlTagDefinition(name: []const u8) HtmlTagDefinition {
    const void_tags = std.StaticStringMap(void).initComptime(.{
        .{"area"}, .{"base"}, .{"br"}, .{"col"}, .{"embed"}, .{"hr"},
        .{"img"}, .{"input"}, .{"link"}, .{"meta"}, .{"param"}, .{"source"},
        .{"track"}, .{"wbr"},
    });
    if (void_tags.has(name)) {
        return .{ .name = name, .content_type = .Void, .is_void = true };
    }

    const raw_text_tags = std.StaticStringMap(void).initComptime(.{
        .{"script"}, .{"style"},
    });
    if (raw_text_tags.has(name)) {
        return .{ .name = name, .content_type = .RawText };
    }

    const escapable_raw_tags = std.StaticStringMap(void).initComptime(.{
        .{"textarea"}, .{"title"},
    });
    if (escapable_raw_tags.has(name)) {
        return .{ .name = name, .content_type = .EscapableRawText };
    }

    // SVG namespace
    if (std.mem.eql(u8, name, "svg")) {
        return .{ .name = name, .implicit_namespace = "http://www.w3.org/2000/svg" };
    }
    // MathML namespace
    if (std.mem.eql(u8, name, "math")) {
        return .{ .name = name, .implicit_namespace = "http://www.w3.org/1998/Math/MathML" };
    }

    return .{ .name = name, .content_type = .Text };
}
