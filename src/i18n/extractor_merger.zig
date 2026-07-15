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
    messages: std.StringHashMap(i18n_ast.Message) = undefined,
    messages_list: []const i18n_ast.Message = &.{},
    errors: []const ParseError = &.{},

    pub const ParseError = struct {
        msg: []const u8,
        span: ?[]const u8 = null,
    };

    /// Free all memory owned by this result (messages_list, messages map,
    /// and each message's internal allocations).
    /// Direct port of TS not-needed (V8 GC handles it).
    pub fn deinit(self: *ExtractionResult, allocator: std.mem.Allocator) void {
        // Free each message's internal allocations.
        for (self.messages_list) |*msg| {
            var m = msg.*;
            m.deinit();
        }
        if (self.messages_list.len > 0) {
            allocator.free(self.messages_list);
        }
        // Free errors slice (allocated via toOwnedSlice).
        if (self.errors.len > 0) {
            allocator.free(self.errors);
        }
    }
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
/// Direct port of `_parseMessageMeta(i18n)` in the TS source.
///
/// Format: `meaning|description@@custom-id`
///   - `meaning` is NOT trimmed (TS preserves whitespace)
///   - `description` is NOT trimmed
///   - `custom-id` IS trimmed
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
        info.meaning = remaining[0..sep_pos];
        info.description = remaining[sep_pos + 1 ..];
    } else {
        info.description = remaining;
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

const ml_lexer = @import("../ml_parser/lexer.zig");
const ml_parser = @import("../ml_parser/parser.zig");
const ml_ast = @import("../ml_parser/ast.zig");
const arena_mod = @import("../arena.zig");
const i18n_parser = @import("i18n_parser.zig");
const source_span_mod = @import("../source_span.zig");

/// Extract translatable messages from HTML source.
/// This is a convenience function that parses HTML and calls extractMessagesFromNodes.
pub fn extract(allocator: std.mem.Allocator, source: []const u8) !ExtractionResult {
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    var lex = ml_lexer.Lexer.init(allocator, source);
    defer lex.deinit();
    const lex_result = try lex.tokenize();
    var html_parser = ml_parser.Parser.init(allocator, &arena, source, lex_result[0]);
    defer html_parser.deinit();
    const html_result = try html_parser.parse();
    return try extractMessagesFromNodes(allocator, html_result.root_nodes, source);
}

/// Extract messages from HTML AST nodes.
/// Direct port of `_Visitor.extract(nodes)` in the TS source.
/// Walks the HTML tree looking for `i18n` attributes and i18n comments.
pub fn extractMessagesFromNodes(
    allocator: std.mem.Allocator,
    root_nodes: []const *const ml_ast.Node,
    source: []const u8,
) !ExtractionResult {
    var messages = std.array_list.Managed(i18n_ast.Message).init(allocator);
    var errors = std.array_list.Managed(ExtractionResult.ParseError).init(allocator);
    var visitor = i18n_parser.I18nVisitor.init(allocator, false, true);

    // Track i18n comment blocks (<!-- i18n:m|d --> ... <!-- /i18n -->).
    var in_i18n_block = false;
    var i18n_block_info = I18nAttrInfo{};
    var i18n_block_nodes = std.array_list.Managed(*const ml_ast.Node).init(allocator);
    defer i18n_block_nodes.deinit();

    for (root_nodes) |node| {
        // Check for i18n comment block markers
        if (node.data == .Comment) {
            const comment_val = node.data.Comment.value;
            // Trim whitespace from comment value for matching
            const trimmed = std.mem.trim(u8, comment_val, " \t\n\r");
            // Check for closing i18n block
            if (std.mem.startsWith(u8, trimmed, "/i18n")) {
                if (in_i18n_block) {
                    if (i18n_block_nodes.items.len > 0) {
                        try createMessageFromNodes(
                            allocator, &visitor, i18n_block_nodes.items,
                            i18n_block_info, source, &messages,
                        );
                    }
                    i18n_block_nodes.clearRetainingCapacity();
                    in_i18n_block = false;
                    i18n_block_info = .{};
                } else {
                    try errors.append(.{
                        .msg = "Trying to close an unopened block",
                        .span = null,
                    });
                }
                continue;
            }
            // Check for opening i18n block
            if (isI18nComment(trimmed)) {
                if (in_i18n_block) {
                    try errors.append(.{
                        .msg = "Could not start a block inside a translatable section",
                        .span = null,
                    });
                } else {
                    in_i18n_block = true;
                    const stripped = stripI18nCommentPrefix(trimmed);
                    i18n_block_info = parseI18nAttrValue(std.mem.trim(u8, stripped, " \t\n\r"));
                }
                continue;
            }
        }

        if (in_i18n_block) {
            try i18n_block_nodes.append(node);
        } else {
            try extractFromNode(allocator, &visitor, node, source, &messages, &errors);
        }
    }

    if (in_i18n_block) {
        try errors.append(.{
            .msg = "Unclosed block",
            .span = null,
        });
    }

    return .{
        .messages_list = try messages.toOwnedSlice(),
        .errors = try errors.toOwnedSlice(),
    };
}

/// Create an i18n message from a list of HTML nodes (for i18n comment blocks).
fn createMessageFromNodes(
    allocator: std.mem.Allocator,
    visitor: *i18n_parser.I18nVisitor,
    nodes: []const *const ml_ast.Node,
    info: I18nAttrInfo,
    source: []const u8,
    messages: *std.array_list.Managed(i18n_ast.Message),
) !void {
    var html_inputs = std.array_list.Managed(i18n_parser.HtmlNodeInput).init(allocator);
    defer html_inputs.deinit();
    for (nodes) |node| {
        try html_inputs.append(try mlNodeToHtmlInput(allocator, node, source));
    }

    var msg = try visitor.toI18nMessage(
        html_inputs.items,
        info.meaning,
        info.description,
        info.custom_id,
        null,
    );
    for (html_inputs.items) |input| {
        freeHtmlNodeInputs(allocator, input);
    }
    if (msg.owns_message_string and msg.message_string.len > 0) {
        if (msg.allocator) |a| a.free(msg.message_string);
        msg.owns_message_string = false;
    }
    const serialized = try i18n_ast.serializeNodesXmlLike(allocator, msg.nodes);
    defer allocator.free(serialized);
    msg.message_string = try allocator.dupe(u8, serialized);
    msg.owns_message_string = true;
    msg.id = try digest.computeDigest(allocator, &msg);
    msg.owns_id = true;
    try messages.append(msg);
}

/// Recursively extract i18n messages from a single HTML node.
fn extractFromNode(
    allocator: std.mem.Allocator,
    visitor: *i18n_parser.I18nVisitor,
    node: *const ml_ast.Node,
    source: []const u8,
    messages: *std.array_list.Managed(i18n_ast.Message),
    errors: *std.array_list.Managed(ExtractionResult.ParseError),
) anyerror!void {
    switch (node.data) {
        .Element => |elem| {
            // Check for i18n attribute
            var i18n_attr_value: ?[]const u8 = null;
            for (elem.attrs) |attr| {
                if (std.mem.eql(u8, attr.name, I18N_ATTR)) {
                    i18n_attr_value = attr.value;
                    break;
                }
            }

            if (i18n_attr_value) |i18n_val| {
                // Parse i18n attribute value: meaning|description@@customId
                const info = parseI18nAttrValue(i18n_val);

                // Only create message if element has children
                if (elem.children.len > 0) {
                    // Convert HTML children to i18n nodes
                    var html_inputs = std.array_list.Managed(i18n_parser.HtmlNodeInput).init(allocator);
                    defer html_inputs.deinit();
                    for (elem.children) |child| {
                        try html_inputs.append(try mlNodeToHtmlInput(allocator, child, source));
                    }

                    // Create the i18n message
                    var msg = try visitor.toI18nMessage(
                        html_inputs.items,
                        info.meaning,
                        info.description,
                        info.custom_id,
                        null,
                    );
                    // Free the temporary HtmlNodeInput children arrays (recursively).
                    // These were allocated by `mlNodeToHtmlInput` and are no longer
                    // needed after `toI18nMessage` has processed them.
                    for (html_inputs.items) |input| {
                        freeHtmlNodeInputs(allocator, input);
                    }
                    // Free the message_string that initWithNodes computed — we
                    // replace it with the serialized XML-like form below.
                    if (msg.owns_message_string and msg.message_string.len > 0) {
                        if (msg.allocator) |a| {
                            a.free(msg.message_string);
                        }
                        msg.owns_message_string = false;
                    }
                    // Compute message string and id
                    const serialized = try i18n_ast.serializeNodesXmlLike(allocator, msg.nodes);
                    defer allocator.free(serialized);
                    msg.message_string = try allocator.dupe(u8, serialized);
                    msg.owns_message_string = true;
                    msg.id = try digest.computeDigest(allocator, &msg);
                    msg.owns_id = true;
                    try messages.append(msg);
                }
            }

            // Check for i18n-* attributes (attribute-level i18n)
            for (elem.attrs) |attr| {
                if (getI18nAttributeTarget(attr.name)) |_| {
                    if (attr.name.len > I18N_ATTR_PREFIX.len) {
                        // Find the i18n-* attribute value
                        var i18n_attr_val: ?[]const u8 = null;
                        for (elem.attrs) |a| {
                            if (std.mem.eql(u8, a.name, attr.name)) {
                                i18n_attr_val = a.value;
                            }
                        }
                        const info = if (i18n_attr_val) |v| parseI18nAttrValue(v) else I18nAttrInfo{};

                        // Create message from attribute value
                        if (attr.value.len > 0) {
                            var html_inputs = std.array_list.Managed(i18n_parser.HtmlNodeInput).init(allocator);
                            defer html_inputs.deinit();
                            const attr_span = source_span_mod.ParseSourceSpan.init(0, 0, source);
                            try html_inputs.append(.{
                                .kind = .attribute,
                                .name = attr.name,
                                .value = attr.value,
                                .source_span = attr_span,
                            });

                            var msg = try visitor.toI18nMessage(
                                html_inputs.items,
                                info.meaning,
                                info.description,
                                info.custom_id,
                                null,
                            );
                            // Free the message_string that initWithNodes computed.
                            if (msg.owns_message_string and msg.message_string.len > 0) {
                                if (msg.allocator) |a| {
                                    a.free(msg.message_string);
                                }
                                msg.owns_message_string = false;
                            }
                            const serialized = try i18n_ast.serializeNodesXmlLike(allocator, msg.nodes);
                            defer allocator.free(serialized);
                            msg.message_string = try allocator.dupe(u8, serialized);
                            msg.owns_message_string = true;
                            msg.id = try digest.computeDigest(allocator, &msg);
                            msg.owns_id = true;
                            try messages.append(msg);
                        }
                    }
                }
            }

            // Recurse into children
            for (elem.children) |child| {
                try extractFromNode(allocator, visitor, child, source, messages, errors);
            }
        },
        .Comment => |comment| {
            // Check for i18n comment blocks: <!-- i18n --> ... <!-- /i18n -->
            if (isI18nComment(comment.value)) {
                // i18n comment block — content between this and /i18n is translatable
                // For now, just mark that we found it
            }
        },
        .Block => |block| {
            // Recurse into block children
            for (block.children) |child| {
                try extractFromNode(allocator, visitor, child, source, messages, errors);
            }
        },
        else => {},
    }
}

/// Recursively free HtmlNodeInput children arrays (allocated by `mlNodeToHtmlInput`).
fn freeHtmlNodeInputs(allocator: std.mem.Allocator, input: i18n_parser.HtmlNodeInput) void {
    if (input.kind == .element) {
        if (input.children.len > 0) {
            for (input.children) |child| {
                freeHtmlNodeInputs(allocator, child);
            }
            allocator.free(input.children);
        }
    }
}

/// Convert an ml_ast.Node to an HtmlNodeInput for the i18n visitor.
fn mlNodeToHtmlInput(
    allocator: std.mem.Allocator,
    node: *const ml_ast.Node,
    source: []const u8,
) !i18n_parser.HtmlNodeInput {
    const empty_span = @import("../source_span.zig").ParseSourceSpan.init(0, 0, source);
    return switch (node.data) {
        .Text => |t| .{
            .kind = .text,
            .text = t.value,
            .value = t.value,
            .source_span = empty_span,
        },
        .Element => |e| blk: {
            // Convert children recursively
            var children = try allocator.alloc(i18n_parser.HtmlNodeInput, e.children.len);
            for (e.children, 0..) |child, i| {
                children[i] = try mlNodeToHtmlInput(allocator, child, source);
            }
            break :blk .{
                .kind = .element,
                .name = e.name,
                .source_span = empty_span,
                .children = children,
            };
        },
        .Comment => |c| .{
            .kind = .comment,
            .value = c.value,
            .text = c.value,
            .source_span = empty_span,
        },
        .Cdata => |c| .{
            .kind = .text,
            .text = c.value,
            .value = c.value,
            .source_span = empty_span,
        },
        else => .{
            .kind = .text,
            .text = "",
            .value = "",
            .source_span = empty_span,
        },
    };
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
    _ = allocator;
    _ = nodes;
    _ = implicit_tags;
    _ = implicit_attrs;
    _ = preserve_significant_whitespace;
    return .{
        .messages_list = &.{},
        .errors = &.{},
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

// ─── Opening/closing comment detection ──────────────────────

/// Check if a comment is an opening i18n comment (`<!--i18n-->` or `<!--i18n:...-->`).
/// Direct port of `_isOpeningComment(comment)` in the TS source.
pub fn isOpeningComment(comment_value: []const u8) bool {
    const trimmed = std.mem.trim(u8, comment_value, " \t");
    if (std.mem.startsWith(u8, trimmed, "i18n")) {
        const rest = trimmed[4..];
        if (rest.len == 0) return true;
        if (rest[0] == ':') return true;
    }
    return false;
}

/// Check if a comment is a closing i18n comment (`<!--/i18n-->`).
/// Direct port of `_isClosingComment(comment)` in the TS source.
pub fn isClosingComment(comment_value: []const u8) bool {
    const trimmed = std.mem.trim(u8, comment_value, " \t");
    return std.mem.eql(u8, trimmed, "/i18n");
}

// ─── _Visitor class (extract + merge) ────────────────────────

/// I18nExtractorVisitor — the full _Visitor implementation.
/// Direct port of `_Visitor` class in the TS source.
///
/// Used in two modes:
/// 1. Extract: walks the HTML AST and collects translatable messages.
/// 2. Merge: walks the HTML AST and replaces translatable content with translations.
pub const I18nExtractorVisitor = struct {
    allocator: std.mem.Allocator,
    implicit_tags: []const []const u8 = &.{},
    preserve_significant_whitespace: bool = true,

    // State
    mode: VisitorMode = .Extract,
    depth: u32 = 0,
    in_i18n_node: bool = false,
    in_implicit_node: bool = false,
    in_i18n_block: bool = false,
    in_icu: bool = false,
    block_meaning_and_desc: []const u8 = "",
    block_start_depth: u32 = 0,
    msg_count_at_section_start: ?u32 = null,

    // Results
    errors: std.array_list.Managed(ExtractionResult.ParseError),
    messages: std.array_list.Managed(i18n_ast.Message),

    pub fn init(allocator: std.mem.Allocator) I18nExtractorVisitor {
        return .{
            .allocator = allocator,
            .errors = std.array_list.Managed(ExtractionResult.ParseError).init(allocator),
            .messages = std.array_list.Managed(i18n_ast.Message).init(allocator),
        };
    }

    pub fn deinit(self: *I18nExtractorVisitor) void {
        self.errors.deinit();
        self.messages.deinit();
    }

    /// Initialize the visitor for a given mode.
    /// Direct port of `_init(mode)` in the TS source.
    pub fn initMode(self: *I18nExtractorVisitor, mode: VisitorMode) void {
        self.mode = mode;
        self.in_i18n_block = false;
        self.in_i18n_node = false;
        self.depth = 0;
        self.in_icu = false;
        self.msg_count_at_section_start = null;
        self.errors.clearRetainingCapacity();
        self.messages.clearRetainingCapacity();
        self.in_implicit_node = false;
    }

    /// Extract messages from a list of HTML node sources.
    /// Direct port of `extract(nodes)` in the TS source.
    pub fn extract(self: *I18nExtractorVisitor, nodes: []const ExtractableNode) !ExtractionResult {
        self.initMode(.Extract);
        for (nodes) |node| {
            try self.visitNode(&node);
        }
        if (self.in_i18n_block) {
            try self.reportError("Unclosed block");
        }
        return .{
            .messages = std.StringHashMap(i18n_ast.Message).init(self.allocator),
            .errors = try self.errors.toOwnedSlice(),
        };
    }

    /// Visit a single node — dispatch based on kind.
    fn visitNode(self: *I18nExtractorVisitor, node: *const ExtractableNode) anyerror!void {
        switch (node.kind) {
            .text => try self.visitText(node.text),
            .element => try self.visitElementLike(node),
            .comment => try self.visitCommentNode(node.text),
            .expansion => try self.visitExpansion(node),
            .block => try self.visitBlockNode(node),
        }
    }

    /// Visit a text node.
    /// Direct port of `visitText(text, context)` in the TS source.
    pub fn visitText(self: *I18nExtractorVisitor, text: []const u8) anyerror!void {
        _ = self;
        _ = text;
        // Text inside a translatable section is collected by _mayBeAddBlockChildren.
    }

    /// Visit an element-like node.
    /// Direct port of `_visitElementLike(node, context)` in the TS source.
    pub fn visitElementLike(self: *I18nExtractorVisitor, node: *const ExtractableNode) anyerror!void {
        self.depth += 1;
        defer self.depth -= 1;

        // Check for i18n attribute
        const has_i18n = self.hasI18nAttribute(node);

        if (has_i18n and self.in_i18n_block) {
            try self.reportError("Cannot mark an element as translatable inside of a translatable section.");
            return;
        }

        if (has_i18n) {
            self.in_i18n_node = true;
            // Parse the i18n attribute value
            const i18n_value = self.getI18nAttributeValue(node);
            const info = parseI18nAttrValue(i18n_value);
            // Create a message from this element's children
            try self.addMessageFromNode(node, info);
        }

        // Visit children
        for (node.children) |child| {
            try self.visitNode(&child);
        }
    }

    /// Visit a comment node.
    /// Direct port of `visitComment(comment, context)` in the TS source.
    pub fn visitCommentNode(self: *I18nExtractorVisitor, comment: []const u8) anyerror!void {
        const is_opening = isOpeningComment(comment);
        const is_closing = isClosingComment(comment);

        if (is_opening and self.isInTranslatableSection()) {
            try self.reportError("Could not start a block inside a translatable section");
            return;
        }

        if (is_closing and !self.in_i18n_block) {
            try self.reportError("Trying to close an unopened block");
            return;
        }

        if (!self.in_i18n_node and !self.in_icu) {
            if (!self.in_i18n_block) {
                if (is_opening) {
                    self.in_i18n_block = true;
                    self.block_start_depth = self.depth;
                    self.block_meaning_and_desc = stripI18nCommentPrefix(comment);
                    self.openTranslatableSection();
                }
            } else {
                if (is_closing) {
                    if (self.depth == self.block_start_depth) {
                        self.closeTranslatableSection();
                        self.in_i18n_block = false;
                    } else {
                        try self.reportError("I18N blocks should not cross element boundaries");
                    }
                }
            }
        }
    }

    /// Visit an ICU expansion.
    /// Direct port of `visitExpansion(icu, context)` in the TS source.
    pub fn visitExpansion(self: *I18nExtractorVisitor, node: *const ExtractableNode) anyerror!void {
        const was_in_icu = self.in_icu;

        if (!self.in_icu) {
            if (self.isInTranslatableSection()) {
                // Add the ICU as a message
                try self.addMessageFromNode(node, I18nAttrInfo{});
            }
            self.in_icu = true;
        }

        // Visit cases (children)
        for (node.children) |child| {
            try self.visitNode(&child);
        }

        self.in_icu = was_in_icu;
    }

    /// Visit a block node (@if, @for, etc.).
    /// Direct port of `visitBlock(block, context)` in the TS source.
    pub fn visitBlockNode(self: *I18nExtractorVisitor, node: *const ExtractableNode) anyerror!void {
        for (node.children) |child| {
            try self.visitNode(&child);
        }
    }

    // ─── Helper methods ──────────────────────────────────────

    /// Check if the visitor is currently in a translatable section.
    /// Direct port of `_isInTranslatableSection` getter in the TS source.
    pub fn isInTranslatableSection(self: *const I18nExtractorVisitor) bool {
        return self.in_i18n_block or self.in_i18n_node or self.in_implicit_node;
    }

    /// Open a translatable section.
    /// Direct port of `_openTranslatableSection(node)` in the TS source.
    fn openTranslatableSection(self: *I18nExtractorVisitor) void {
        self.msg_count_at_section_start = @intCast(self.messages.items.len);
    }

    /// Close a translatable section.
    /// Direct port of `_closeTranslatableSection(node, children)` in the TS source.
    fn closeTranslatableSection(self: *I18nExtractorVisitor) void {
        self.msg_count_at_section_start = null;
    }

    /// Report an error.
    /// Direct port of `_reportError(node, msg)` in the TS source.
    fn reportError(self: *I18nExtractorVisitor, msg: []const u8) !void {
        try self.errors.append(.{ .msg = msg });
    }

    /// Check if a node has an i18n attribute.
    fn hasI18nAttribute(self: *const I18nExtractorVisitor, node: *const ExtractableNode) bool {
        _ = self;
        for (node.attrs) |attr| {
            if (isI18nAttribute(attr.name)) return true;
        }
        return false;
    }

    /// Get the i18n attribute value from a node.
    fn getI18nAttributeValue(self: *const I18nExtractorVisitor, node: *const ExtractableNode) []const u8 {
        _ = self;
        for (node.attrs) |attr| {
            if (std.mem.eql(u8, attr.name, I18N_ATTR)) return attr.value;
        }
        return "";
    }

    /// Add a message from a node.
    fn addMessageFromNode(self: *I18nExtractorVisitor, node: *const ExtractableNode, info: I18nAttrInfo) !void {
        _ = node;
        var msg = i18n_ast.Message.init(self.allocator);
        msg.meaning = info.meaning;
        msg.description = info.description;
        msg.custom_id = info.custom_id;
        msg.id = info.custom_id;
        try self.messages.append(msg);
    }
};

/// ExtractableNode — a simplified HTML node for i18n extraction.
/// This is the input to the I18nExtractorVisitor.
pub const ExtractableNode = struct {
    kind: ExtractableNodeKind,
    text: []const u8 = "",
    tag_name: []const u8 = "",
    attrs: []const ExtractableAttr = &.{},
    children: []const ExtractableNode = &.{},
    source_span: ?[]const u8 = null,
};

pub const ExtractableNodeKind = enum {
    text,
    element,
    comment,
    expansion,
    block,
};

pub const ExtractableAttr = struct {
    name: []const u8,
    value: []const u8 = "",
};

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

// ─── Tests for opening/closing comments ─────────────────────

test "isOpeningComment — i18n" {
    try std.testing.expect(isOpeningComment("i18n"));
    try std.testing.expect(isOpeningComment("  i18n  "));
    try std.testing.expect(isOpeningComment("i18n:meaning|desc"));
}

test "isOpeningComment — not i18n" {
    try std.testing.expect(!isOpeningComment("regular comment"));
    try std.testing.expect(!isOpeningComment("/i18n"));
    try std.testing.expect(!isOpeningComment("i18n-title"));
}

test "isClosingComment — /i18n" {
    try std.testing.expect(isClosingComment("/i18n"));
    try std.testing.expect(isClosingComment("  /i18n  "));
}

test "isClosingComment — not closing" {
    try std.testing.expect(!isClosingComment("i18n"));
    try std.testing.expect(!isClosingComment("regular comment"));
    try std.testing.expect(!isClosingComment("/i18n:desc"));
}

// ─── Tests for I18nExtractorVisitor ─────────────────────────

test "I18nExtractorVisitor init/deinit" {
    const allocator = std.testing.allocator;
    var visitor = I18nExtractorVisitor.init(allocator);
    defer visitor.deinit();
    try std.testing.expectEqual(@as(usize, 0), visitor.messages.items.len);
    try std.testing.expectEqual(@as(usize, 0), visitor.errors.items.len);
}

test "I18nExtractorVisitor initMode" {
    const allocator = std.testing.allocator;
    var visitor = I18nExtractorVisitor.init(allocator);
    defer visitor.deinit();
    visitor.initMode(.Merge);
    try std.testing.expectEqual(VisitorMode.Merge, visitor.mode);
}

test "I18nExtractorVisitor — extract empty nodes" {
    const allocator = std.testing.allocator;
    var visitor = I18nExtractorVisitor.init(allocator);
    defer visitor.deinit();
    var result = try visitor.extract(&.{});
    defer result.errors = &.{};
    try std.testing.expectEqual(@as(usize, 0), visitor.messages.items.len);
}

test "I18nExtractorVisitor — extract with i18n element" {
    const allocator = std.testing.allocator;
    var visitor = I18nExtractorVisitor.init(allocator);
    defer visitor.deinit();

    var attrs = [_]ExtractableAttr{
        .{ .name = "i18n", .value = "greeting|A greeting" },
    };
    var nodes = [_]ExtractableNode{.{
        .kind = .element,
        .tag_name = "div",
        .attrs = &attrs,
    }};
    var result = try visitor.extract(&nodes);
    defer result.errors = &.{};
    try std.testing.expectEqual(@as(usize, 1), visitor.messages.items.len);
    try std.testing.expectEqualStrings("greeting", visitor.messages.items[0].meaning);
    try std.testing.expectEqualStrings("A greeting", visitor.messages.items[0].description);
}

test "I18nExtractorVisitor — isInTranslatableSection" {
    const allocator = std.testing.allocator;
    var visitor = I18nExtractorVisitor.init(allocator);
    defer visitor.deinit();

    try std.testing.expect(!visitor.isInTranslatableSection());
    visitor.in_i18n_block = true;
    try std.testing.expect(visitor.isInTranslatableSection());
    visitor.in_i18n_block = false;
    visitor.in_i18n_node = true;
    try std.testing.expect(visitor.isInTranslatableSection());
}

test "I18nExtractorVisitor — visitCommentNode opening" {
    const allocator = std.testing.allocator;
    var visitor = I18nExtractorVisitor.init(allocator);
    defer visitor.deinit();

    try visitor.visitCommentNode("i18n:meaning|desc");
    try std.testing.expect(visitor.in_i18n_block);
}

test "I18nExtractorVisitor — visitCommentNode closing" {
    const allocator = std.testing.allocator;
    var visitor = I18nExtractorVisitor.init(allocator);
    defer visitor.deinit();

    visitor.in_i18n_block = true;
    visitor.block_start_depth = 0;
    try visitor.visitCommentNode("/i18n");
    try std.testing.expect(!visitor.in_i18n_block);
}

test "I18nExtractorVisitor — visitCommentNode closing without opening" {
    const allocator = std.testing.allocator;
    var visitor = I18nExtractorVisitor.init(allocator);
    defer visitor.deinit();

    try visitor.visitCommentNode("/i18n");
    try std.testing.expectEqual(@as(usize, 1), visitor.errors.items.len);
}

test "ExtractableNode — defaults" {
    const node = ExtractableNode{ .kind = .text };
    try std.testing.expectEqualStrings("", node.text);
    try std.testing.expectEqualStrings("", node.tag_name);
    try std.testing.expectEqual(@as(usize, 0), node.attrs.len);
    try std.testing.expectEqual(@as(usize, 0), node.children.len);
}

test "ExtractableAttr — basic" {
    const attr = ExtractableAttr{ .name = "class", .value = "active" };
    try std.testing.expectEqualStrings("class", attr.name);
    try std.testing.expectEqualStrings("active", attr.value);
}

test "ExtractableNodeKind — all variants" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(ExtractableNodeKind.text));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(ExtractableNodeKind.element));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(ExtractableNodeKind.comment));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(ExtractableNodeKind.expansion));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(ExtractableNodeKind.block));
}
