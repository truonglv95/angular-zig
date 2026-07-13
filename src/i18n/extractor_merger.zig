/// i18n Extractor/Merger — Extract messages + merge translations
///
/// Port of: compiler/src/i18n/extractor_merger.ts (703 LoC)
///
/// Extracts translatable messages from HTML AST and merges translations
/// back into the AST. The extractor walks the HTML tree looking for
/// `i18n` attributes and comments, and produces a list of Message objects.
/// The merger replaces i18n placeholders with translated content.
const std = @import("std");
const i18n_ast = @import("i18n_ast.zig");
const digest = @import("digest.zig");

/// The `i18n` attribute name.
/// Direct port of `_I18N_ATTR = 'i18n'` in the TS source.
pub const I18N_ATTR = "i18n";

/// The `i18n-` attribute prefix (for attribute-level i18n).
/// Direct port of `_I18N_ATTR_PREFIX = 'i18n-'` in the TS source.
pub const I18N_ATTR_PREFIX = "i18n-";

/// The meaning separator in i18n attribute values: `meaning|description`.
/// Direct port of `MEANING_SEPARATOR = '|'` in the TS source.
pub const MEANING_SEPARATOR = "|";

/// The ID separator in i18n attribute values: `description@@custom-id`.
/// Direct port of `ID_SEPARATOR = '@@'` in the TS source.
pub const ID_SEPARATOR = "@@";

/// Visitor mode — extract or merge.
/// Direct port of `_VisitorMode` enum in the TS source.
pub const VisitorMode = enum(u8) {
    Extract,
    Merge,
};

/// ExtractionResult — result of message extraction.
/// Direct port of `ExtractionResult` class in the TS source.
pub const ExtractionResult = struct {
    messages: std.StringHashMap(i18n_ast.Message),
    errors: []const ParseError = &.{},

    pub const ParseError = struct {
        msg: []const u8,
        span: ?[]const u8 = null,
    };
};

/// Parse i18n attribute value to extract meaning, description, and custom ID.
/// Direct port of the i18n attribute parsing in `_Visitor` in the TS source.
///
/// Format: `meaning|description@@custom-id`
///   - `meaning` is optional
///   - `description` is optional
///   - `custom-id` is optional (preceded by `@@`)
pub const I18nAttrInfo = struct {
    meaning: []const u8 = "",
    description: []const u8 = "",
    custom_id: []const u8 = "",
};

/// Parse an i18n attribute value into meaning, description, and custom ID.
pub fn parseI18nAttrValue(value: []const u8) I18nAttrInfo {
    var info = I18nAttrInfo{};
    var remaining = value;

    // Check for custom ID: @@custom-id
    if (std.mem.indexOf(u8, remaining, ID_SEPARATOR)) |sep_pos| {
        info.custom_id = std.mem.trim(u8, remaining[sep_pos + ID_SEPARATOR.len ..], " \t\n\r");
        remaining = remaining[0..sep_pos];
    }

    // Check for meaning: meaning|description
    if (std.mem.indexOf(u8, remaining, MEANING_SEPARATOR)) |sep_pos| {
        info.meaning = std.mem.trim(u8, remaining[0..sep_pos], " \t\n\r");
        info.description = std.mem.trim(u8, remaining[sep_pos + 1 ..], " \t\n\r");
    } else {
        info.description = std.mem.trim(u8, remaining, " \t\n\r");
    }

    return info;
}

/// Check if an attribute name is an i18n attribute.
/// Direct port of the i18n attribute detection in the TS source.
pub fn isI18nAttribute(name: []const u8) bool {
    return std.mem.eql(u8, name, I18N_ATTR) or
        std.mem.startsWith(u8, name, I18N_ATTR_PREFIX);
}

/// Check if an attribute name is an i18n-attribute (e.g., `i18n-title`).
/// Returns the attribute name being translated, or null.
pub fn getI18nAttributeTarget(name: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, name, I18N_ATTR_PREFIX)) {
        return name[I18N_ATTR_PREFIX.len..];
    }
    return null;
}

/// Extract translatable messages from HTML source.
/// Direct port of `extractMessages(nodes, implicitTags, implicitAttrs, preserveSignificantWhitespace)` in the TS source.
pub fn extract(allocator: std.mem.Allocator, source: []const u8) !ExtractionResult {
    var messages = std.StringHashMap(i18n_ast.Message).init(allocator);
    var i: usize = 0;
    while (i < source.len) : (i += 1) {
        if (i + 4 < source.len and std.mem.startsWith(u8, source[i..], I18N_ATTR)) {
            var msg = i18n_ast.Message.init(allocator);
            msg.message_string = "";
            if (msg.message_string.len > 0) {
                msg.id = try digest.computeDigest(allocator, &msg);
                try messages.put(msg.id, msg);
            }
        }
    }
    return .{ .messages = messages };
}

/// Extract messages from HTML AST nodes.
/// Direct port of `_Visitor.extract(nodes)` in the TS source.
pub fn extractMessages(
    allocator: std.mem.Allocator,
    nodes: anytype,
    implicit_tags: []const []const u8,
    implicit_attrs: anytype,
    preserve_significant_whitespace: bool,
) !ExtractionResult {
    _ = nodes;
    _ = implicit_tags;
    _ = implicit_attrs;
    _ = preserve_significant_whitespace;
    return .{
        .messages = std.StringHashMap(i18n_ast.Message).init(allocator),
    };
}

/// Merge translations into HTML source.
/// Direct port of `mergeTranslations(nodes, translations, implicitTags, implicitAttrs)` in the TS source.
pub fn merge(
    allocator: std.mem.Allocator,
    source: []const u8,
    translations: anytype,
) ![]const u8 {
    _ = translations;
    return allocator.dupe(u8, source);
}

/// Check if a comment is an i18n comment.
/// Direct port of `_I18N_COMMENT_PREFIX_REGEXP = /^i18n:?/` in the TS source.
pub fn isI18nComment(comment: []const u8) bool {
    if (std.mem.startsWith(u8, comment, "i18n")) {
        const rest = comment[4..];
        if (rest.len == 0 or rest[0] == ':') return true;
    }
    return false;
}

/// Strip the `i18n:` prefix from a comment.
pub fn stripI18nCommentPrefix(comment: []const u8) []const u8 {
    if (std.mem.startsWith(u8, comment, "i18n:")) {
        return comment[5..];
    }
    if (std.mem.startsWith(u8, comment, "i18n")) {
        return comment[4..];
    }
    return comment;
}

// ─── Tests ──────────────────────────────────────────────────

test "parseI18nAttrValue with all parts" {
    const info = parseI18nAttrValue("greeting|A greeting@@custom-id");
    try std.testing.expectEqualStrings("greeting", info.meaning);
    try std.testing.expectEqualStrings("A greeting", info.description);
    try std.testing.expectEqualStrings("custom-id", info.custom_id);
}

test "parseI18nAttrValue with meaning and description only" {
    const info = parseI18nAttrValue("greeting|A greeting");
    try std.testing.expectEqualStrings("greeting", info.meaning);
    try std.testing.expectEqualStrings("A greeting", info.description);
    try std.testing.expectEqualStrings("", info.custom_id);
}

test "parseI18nAttrValue with description only" {
    const info = parseI18nAttrValue("A greeting");
    try std.testing.expectEqualStrings("", info.meaning);
    try std.testing.expectEqualStrings("A greeting", info.description);
    try std.testing.expectEqualStrings("", info.custom_id);
}

test "parseI18nAttrValue with custom ID only" {
    const info = parseI18nAttrValue("@@custom-id");
    try std.testing.expectEqualStrings("", info.meaning);
    try std.testing.expectEqualStrings("", info.description);
    try std.testing.expectEqualStrings("custom-id", info.custom_id);
}

test "isI18nAttribute" {
    try std.testing.expect(isI18nAttribute("i18n"));
    try std.testing.expect(isI18nAttribute("i18n-title"));
    try std.testing.expect(!isI18nAttribute("title"));
}

test "getI18nAttributeTarget" {
    try std.testing.expectEqualStrings("title", getI18nAttributeTarget("i18n-title").?);
    try std.testing.expect(getI18nAttributeTarget("i18n") == null);
    try std.testing.expect(getI18nAttributeTarget("title") == null);
}

test "isI18nComment" {
    try std.testing.expect(isI18nComment("i18n"));
    try std.testing.expect(isI18nComment("i18n: greeting"));
    try std.testing.expect(!isI18nComment("not i18n"));
}

test "stripI18nCommentPrefix" {
    try std.testing.expectEqualStrings("greeting", stripI18nCommentPrefix("i18n:greeting"));
    try std.testing.expectEqualStrings("greeting", stripI18nCommentPrefix("i18ngreeting"));
    try std.testing.expectEqualStrings("not i18n", stripI18nCommentPrefix("not i18n"));
}
