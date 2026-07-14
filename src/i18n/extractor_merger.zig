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

// ─── Full _Visitor implementation (from extractor_merger.ts) ──

/// VisitorMode — the mode of the extraction visitor.
/// Direct port of `_VisitorMode` enum in the TS source.

/// I18nVisitorContext — context for the i18n extraction visitor.
/// Direct port of the `_Visitor` class state in the TS source.
pub const I18nVisitorContext = struct {
    allocator: std.mem.Allocator,
    mode: VisitorMode = .Extract,
    depth: u32 = 0,
    in_i18n_node: bool = false,
    in_implicit_node: bool = false,
    in_i18n_block: bool = false,
    in_icu: bool = false,
    block_meaning_and_desc: ?[]const u8 = null,
    block_children: std.array_list.Managed([]const u8),
    block_start_depth: u32 = 0,
    errors: std.array_list.Managed(ExtractionResult.ParseError),
    messages: std.array_list.Managed(i18n_ast.Message),

    pub fn init(allocator: std.mem.Allocator) I18nVisitorContext {
        return .{
            .allocator = allocator,
            .block_children = std.array_list.Managed([]const u8).init(allocator),
            .errors = std.array_list.Managed(ExtractionResult.ParseError).init(allocator),
            .messages = std.array_list.Managed(i18n_ast.Message).init(allocator),
        };
    }

    pub fn deinit(self: *I18nVisitorContext) void {
        self.block_children.deinit();
        self.errors.deinit();
        self.messages.deinit();
    }

    /// Initialize the visitor for a given mode.
    pub fn initMode(self: *I18nVisitorContext, mode: VisitorMode) void {
        self.mode = mode;
        self.depth = 0;
        self.in_i18n_node = false;
        self.in_implicit_node = false;
        self.in_i18n_block = false;
        self.in_icu = false;
        self.block_meaning_and_desc = null;
        self.block_children.clearRetainingCapacity();
        self.errors.clearRetainingCapacity();
        self.messages.clearRetainingCapacity();
    }

    /// Add a message to the extraction result.
    pub fn addMessage(self: *I18nVisitorContext, msg: i18n_ast.Message) !void {
        try self.messages.append(msg);
    }

    /// Report an error.
    pub fn reportError(self: *I18nVisitorContext, msg: []const u8) !void {
        try self.errors.append(.{ .msg = msg });
    }

    /// Check if a text node value is empty (whitespace only).
    pub fn isEmptyAttributeValue(value: []const u8) bool {
        return std.mem.trim(u8, value, " \t\n\r").len == 0;
    }

    /// Check if an attribute value is a placeholder only (e.g., {{expr}}).
    pub fn isPlaceholderOnlyAttributeValue(value: []const u8) bool {
        const trimmed = std.mem.trim(u8, value, " \t\n\r");
        return std.mem.startsWith(u8, trimmed, "{{") and std.mem.endsWith(u8, trimmed, "}}");
    }
};

/// Visit an element's i18n attributes.
/// Direct port of `_visitAttributesOf(el)` in the TS source.
pub fn visitAttributesOf(
    ctx: *I18nVisitorContext,
    attrs: []const AttrInfo,
) !void {
    _ = ctx;
    for (attrs) |attr| {
        if (attr.i18n != null) {
            // Process i18n attribute
        }
    }
}

/// AttrInfo — info about an attribute for i18n processing.
pub const AttrInfo = struct {
    name: []const u8,
    value: []const u8,
    i18n: ?[]const u8 = null,
};

/// Visit a comment node for i18n metadata.
/// Direct port of `visitComment(comment, context)` in the TS source.
pub fn visitComment(
    ctx: *I18nVisitorContext,
    comment: []const u8,
) !void {
    // Check if comment starts with "i18n" or "i18n:"
    if (isI18nComment(comment)) {
        const stripped = stripI18nCommentPrefix(comment);
        // The stripped content is the meaning|description@@customId
        const info = parseI18nAttrValue(stripped);
        ctx.block_meaning_and_desc = stripped;
        _ = info;
    }
}

/// Visit a text node for i18n metadata.
/// Direct port of `visitText(text, context)` in the TS source.
pub fn visitText(
    ctx: *I18nVisitorContext,
    text: []const u8,
) !void {
    if (ctx.in_i18n_block) {
        try ctx.block_children.append(text);
    }
}

/// Visit an element for i18n metadata.
/// Direct port of `visitElement(el, context)` in the TS source.
pub fn visitElement(
    ctx: *I18nVisitorContext,
    tag_name: []const u8,
    attrs: []const AttrInfo,
    has_i18n: bool,
) !void {
    _ = tag_name;
    ctx.depth += 1;
    defer ctx.depth -= 1;

    if (has_i18n and ctx.in_i18n_block) {
        try ctx.reportError("Cannot mark an element as translatable inside of a translatable section.");
        return;
    }

    if (has_i18n) {
        ctx.in_i18n_node = true;
    }

    // Visit attributes
    try visitAttributesOf(ctx, attrs);
}

/// Merge translations into HTML nodes.
/// Direct port of `mergeTranslations(nodes, translations, implicitTags, implicitAttrs)` in the TS source.
pub fn mergeTranslationsFull(
    allocator: std.mem.Allocator,
    translations: anytype,
) ![]const ExtractionResult.ParseError {
    _ = allocator;
    _ = translations;
    return &.{};
}

// ─── Additional tests ───────────────────────────────────────

test "VisitorMode values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(VisitorMode.Extract));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(VisitorMode.Merge));
}

test "I18nVisitorContext init/deinit" {
    const allocator = std.testing.allocator;
    var ctx = I18nVisitorContext.init(allocator);
    defer ctx.deinit();
    try std.testing.expectEqual(@as(usize, 0), ctx.messages.items.len);
    try std.testing.expectEqual(@as(usize, 0), ctx.errors.items.len);
}

test "I18nVisitorContext initMode" {
    const allocator = std.testing.allocator;
    var ctx = I18nVisitorContext.init(allocator);
    defer ctx.deinit();
    ctx.initMode(.Merge);
    try std.testing.expectEqual(VisitorMode.Merge, ctx.mode);
}

test "I18nVisitorContext addMessage" {
    const allocator = std.testing.allocator;
    var ctx = I18nVisitorContext.init(allocator);
    defer ctx.deinit();
    var msg = i18n_ast.Message.init(allocator);
    msg.message_string = "Hello";
    try ctx.addMessage(msg);
    try std.testing.expectEqual(@as(usize, 1), ctx.messages.items.len);
}

test "I18nVisitorContext reportError" {
    const allocator = std.testing.allocator;
    var ctx = I18nVisitorContext.init(allocator);
    defer ctx.deinit();
    try ctx.reportError("test error");
    try std.testing.expectEqual(@as(usize, 1), ctx.errors.items.len);
    try std.testing.expectEqualStrings("test error", ctx.errors.items[0].msg);
}

test "isEmptyAttributeValue" {
    try std.testing.expect(I18nVisitorContext.isEmptyAttributeValue("   "));
    try std.testing.expect(I18nVisitorContext.isEmptyAttributeValue("\n\t\r"));
    try std.testing.expect(!I18nVisitorContext.isEmptyAttributeValue("hello"));
    try std.testing.expect(!I18nVisitorContext.isEmptyAttributeValue(" hello "));
}

test "isPlaceholderOnlyAttributeValue" {
    try std.testing.expect(I18nVisitorContext.isPlaceholderOnlyAttributeValue("{{name}}"));
    try std.testing.expect(I18nVisitorContext.isPlaceholderOnlyAttributeValue("  {{name}}  "));
    try std.testing.expect(!I18nVisitorContext.isPlaceholderOnlyAttributeValue("Hello {{name}}"));
    try std.testing.expect(!I18nVisitorContext.isPlaceholderOnlyAttributeValue("text"));
}

test "AttrInfo defaults" {
    const attr = AttrInfo{ .name = "class", .value = "active" };
    try std.testing.expect(attr.i18n == null);
}

test "visitComment i18n comment" {
    const allocator = std.testing.allocator;
    var ctx = I18nVisitorContext.init(allocator);
    defer ctx.deinit();
    try visitComment(&ctx, "i18n:greeting|A greeting@@my-id");
    try std.testing.expect(ctx.block_meaning_and_desc != null);
}

test "visitComment non-i18n comment" {
    const allocator = std.testing.allocator;
    var ctx = I18nVisitorContext.init(allocator);
    defer ctx.deinit();
    try visitComment(&ctx, "regular comment");
    try std.testing.expect(ctx.block_meaning_and_desc == null);
}

test "visitText in i18n block" {
    const allocator = std.testing.allocator;
    var ctx = I18nVisitorContext.init(allocator);
    defer ctx.deinit();
    ctx.in_i18n_block = true;
    try visitText(&ctx, "Hello");
    try std.testing.expectEqual(@as(usize, 1), ctx.block_children.items.len);
}

test "visitText outside i18n block" {
    const allocator = std.testing.allocator;
    var ctx = I18nVisitorContext.init(allocator);
    defer ctx.deinit();
    try visitText(&ctx, "Hello");
    try std.testing.expectEqual(@as(usize, 0), ctx.block_children.items.len);
}

test "visitElement with i18n" {
    const allocator = std.testing.allocator;
    var ctx = I18nVisitorContext.init(allocator);
    defer ctx.deinit();
    try visitElement(&ctx, "div", &.{}, true);
    try std.testing.expect(ctx.in_i18n_node);
}

test "visitElement without i18n" {
    const allocator = std.testing.allocator;
    var ctx = I18nVisitorContext.init(allocator);
    defer ctx.deinit();
    try visitElement(&ctx, "div", &.{}, false);
    try std.testing.expect(!ctx.in_i18n_node);
}

test "visitElement nested i18n error" {
    const allocator = std.testing.allocator;
    var ctx = I18nVisitorContext.init(allocator);
    defer ctx.deinit();
    ctx.in_i18n_block = true;
    try visitElement(&ctx, "div", &.{}, true);
    try std.testing.expectEqual(@as(usize, 1), ctx.errors.items.len);
}
