/// i18n Placeholder — Maps HTML tag names to XLIFF placeholder names
///
/// Port of: compiler/src/i18n/serializers/placeholder.ts
const std = @import("std");

/// Map of HTML tag names to XLIFF placeholder names.
/// E.g. <b> → BOLD_TEXT, <br> → LINE_BREAK
pub const TAG_PLACEHOLDER_MAP = std.StaticStringMap([]const u8).initComptime(.{
    .{ "b", "BOLD_TEXT" },
    .{ "br", "LINE_BREAK" },
    .{ "i", "ITALIC_TEXT" },
    .{ "h1", "HEADING_1" },
    .{ "h2", "HEADING_2" },
    .{ "h3", "HEADING_3" },
    .{ "h4", "HEADING_4" },
    .{ "h5", "HEADING_5" },
    .{ "h6", "HEADING_6" },
    .{ "a", "LINK" },
    .{ "p", "PARAGRAPH" },
    .{ "strong", "STRONG_TEXT" },
    .{ "em", "EMPHASIZED_TEXT" },
    .{ "code", "CODE" },
    .{ "pre", "PRE_FORMATTED" },
    .{ "img", "IMAGE" },
    .{ "ul", "UNORDERED_LIST" },
    .{ "ol", "ORDERED_LIST" },
    .{ "li", "LIST_ITEM" },
    .{ "table", "TABLE" },
    .{ "tr", "TABLE_ROW" },
    .{ "td", "TABLE_CELL" },
    .{ "th", "TABLE_HEADER" },
    .{ "thead", "TABLE_HEAD" },
    .{ "tbody", "TABLE_BODY" },
    .{ "tfoot", "TABLE_FOOT" },
    .{ "span", "SPAN" },
    .{ "div", "DIV" },
    .{ "blockquote", "BLOCKQUOTE" },
    .{ "hr", "HORIZONTAL_RULE" },
    .{ "label", "LABEL" },
    .{ "input", "INPUT" },
    .{ "button", "BUTTON" },
    .{ "select", "SELECT" },
    .{ "option", "OPTION" },
    .{ "textarea", "TEXTAREA" },
    .{ "form", "FORM" },
    .{ "fieldset", "FIELDSET" },
    .{ "legend", "LEGEND" },
    .{ "datalist", "DATALIST" },
    .{ "output", "OUTPUT" },
    .{ "progress", "PROGRESS" },
    .{ "meter", "METER" },
    .{ "details", "DETAILS" },
    .{ "summary", "SUMMARY" },
    .{ "dialog", "DIALOG" },
    .{ "canvas", "CANVAS" },
    .{ "svg", "SVG" },
    .{ "math", "MATH" },
});

/// Get the XLIFF placeholder name for an HTML tag.
/// Returns null if the tag doesn't have a specific placeholder.
pub fn getPlaceholderName(tag: []const u8) ?[]const u8 {
    return TAG_PLACEHOLDER_MAP.get(tag);
}

/// Get the tag name for a placeholder name (reverse lookup).
pub fn getTagName(placeholder: []const u8) ?[]const u8 {
    var it = TAG_PLACEHOLDER_MAP.iterator();
    while (it.next()) |entry| {
        if (std.mem.eql(u8, entry.value_ptr.*, placeholder)) {
            return entry.key_ptr.*;
        }
    }
    return null;
}
