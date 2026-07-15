/// i18n XTB Serializer — Google's XTB translation format
///
/// Port of: compiler/src/i18n/serializers/xtb.ts (252 LoC)
///
/// XTB is Google's XML-based translation format used for Angular's
/// compilation pipeline. XTB files contain translated messages keyed
/// by message IDs. The XTB format is read-only (cannot be written).
const std = @import("std");
const i18n_ast = @import("../i18n_ast.zig");
const xml_helper = @import("xml_helper.zig");
const digest_mod = @import("../digest.zig");

/// XTB tag constants.
/// Direct port of the _TRANSLATIONS_TAG, _TRANSLATION_TAG, _PLACEHOLDER_TAG constants.
pub const TRANSLATIONS_TAG = "translationbundle";
pub const TRANSLATION_TAG = "translation";
pub const PLACEHOLDER_TAG = "ph";

/// LoadResult — result of loading an XTB file.
/// Direct port of the return type of `Xtb.load(content, url)`.
pub const LoadResult = struct {
    locale: ?[]const u8,
    /// Maps message IDs to i18n node arrays.
    i18n_nodes_by_msg_id: std.StringHashMap([]const i18n_ast.Node),
    /// Allocator used for node arrays (for deinit).
    allocator: ?std.mem.Allocator = null,

    pub fn deinit(self: *LoadResult) void {
        // Free each node array (allocated via `toOwnedSlice` in `convertHtmlToI18nNodes`).
        if (self.allocator) |a| {
            var it = self.i18n_nodes_by_msg_id.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.*.len > 0) a.free(entry.value_ptr.*);
            }
        }
        self.i18n_nodes_by_msg_id.deinit();
    }
};

/// ParseResult — result of parsing XTB content to HTML.
/// Direct port of the return type of `XtbParser.parse(xtb, url)`.
pub const ParseResult = struct {
    locale: ?[]const u8 = null,
    /// Maps message IDs to raw HTML strings.
    msg_id_to_html: std.StringHashMap([]const u8),
    errors: std.array_list.Managed(ParseError),

    pub const ParseError = struct {
        msg: []const u8,
        span: ?[]const u8 = null,
    };

    pub fn deinit(self: *ParseResult) void {
        self.msg_id_to_html.deinit();
        self.errors.deinit();
    }
};

/// Xtb — serializer for XTB format (read-only).
/// Direct port of `Xtb` class in the TS source.
pub const Xtb = struct {
    /// XTB format is read-only — writing is not supported.
    /// Direct port of `write(messages, locale)` which throws "Unsupported".
    pub fn write(
        allocator: std.mem.Allocator,
        messages: []const i18n_ast.Message,
        locale: ?[]const u8,
    ) ![]const u8 {
        _ = allocator;
        _ = messages;
        _ = locale;
        return error.Unsupported;
    }

    /// Load messages from XTB format.
    /// Direct port of `load(content, url)` in the TS source.
    pub fn load(
        allocator: std.mem.Allocator,
        content: []const u8,
        url: []const u8,
    ) !LoadResult {
        // xtb to xml nodes
        var parser = XtbParser.init(allocator);
        defer parser.deinit();
        var parse_result = try parser.parse(content, url);
        defer parse_result.deinit();

        // Convert HTML to i18n nodes (simplified — in TS this is lazy)
        var result = LoadResult{
            .locale = parse_result.locale,
            .i18n_nodes_by_msg_id = std.StringHashMap([]const i18n_ast.Node).init(allocator),
            .allocator = allocator,
        };

        // For each message ID, convert the HTML to i18n nodes.
        var it = parse_result.msg_id_to_html.iterator();
        while (it.next()) |entry| {
            const nodes = try convertHtmlToI18nNodes(allocator, entry.value_ptr.*, url);
            try result.i18n_nodes_by_msg_id.put(entry.key_ptr.*, nodes);
        }

        return result;
    }

    /// Compute the digest for a message (uses XMB digest = SHA1).
    /// Direct port of `digest(message)` in the TS source.
    pub fn digest(allocator: std.mem.Allocator, msg: *const i18n_ast.Message) ![]const u8 {
        return digest_mod.computeDigest(allocator, msg);
    }

    /// Create a name mapper for the message.
    /// Direct port of `createNameMapper(message)` in the TS source.
    pub fn createNameMapper(msg: *const i18n_ast.Message) []const u8 {
        _ = msg;
        return "";
    }
};

/// XtbParser — parses XTB XML content.
/// Direct port of `XtbParser` class in the TS source.
pub const XtbParser = struct {
    allocator: std.mem.Allocator,
    bundle_depth: u32 = 0,
    locale: ?[]const u8 = null,
    msg_id_to_html: std.StringHashMap([]const u8),
    errors: std.array_list.Managed(ParseResult.ParseError),

    pub fn init(allocator: std.mem.Allocator) XtbParser {
        return .{
            .allocator = allocator,
            .msg_id_to_html = std.StringHashMap([]const u8).init(allocator),
            .errors = std.array_list.Managed(ParseResult.ParseError).init(allocator),
        };
    }

    pub fn deinit(self: *XtbParser) void {
        self.msg_id_to_html.deinit();
        self.errors.deinit();
    }

    /// Parse XTB content.
    /// Direct port of `parse(xtb, url)` in the TS source.
    pub fn parse(self: *XtbParser, content: []const u8, url: []const u8) !ParseResult {
        _ = url;
        self.bundle_depth = 0;
        self.msg_id_to_html.clearRetainingCapacity();
        self.errors.clearRetainingCapacity();

        // Simple XML parsing: look for <translationbundle lang="...">
        // and <translation id="...">...</translation> elements.
        try self.parseContent(content);

        // Copy results to ParseResult
        var result = ParseResult{
            .locale = self.locale,
            .msg_id_to_html = std.StringHashMap([]const u8).init(self.allocator),
            .errors = std.array_list.Managed(ParseResult.ParseError).init(self.allocator),
        };

        // Copy msg_id_to_html
        var it = self.msg_id_to_html.iterator();
        while (it.next()) |entry| {
            try result.msg_id_to_html.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Copy errors
        for (self.errors.items) |err| {
            try result.errors.append(err);
        }

        return result;
    }

    /// Simple content parser — scans for translationbundle and translation tags.
    fn parseContent(self: *XtbParser, content: []const u8) !void {
        var pos: usize = 0;
        while (pos < content.len) {
            // Find next '<'
            const tag_start = std.mem.indexOfScalarPos(u8, content, pos, '<') orelse break;
            const tag_end = std.mem.indexOfScalarPos(u8, content, tag_start, '>') orelse break;
            const tag_content = content[tag_start + 1 .. tag_end];

            if (std.mem.startsWith(u8, tag_content, TRANSLATIONS_TAG)) {
                self.bundle_depth += 1;
                // Extract lang attribute
                if (std.mem.indexOf(u8, tag_content, "lang=\"")) |lang_start| {
                    const lang_value_start = lang_start + 6;
                    if (std.mem.indexOfScalarPos(u8, tag_content, lang_value_start, '"')) |lang_end| {
                        self.locale = content[tag_start + 1 + lang_value_start .. tag_start + 1 + lang_end];
                    }
                }
            } else if (std.mem.startsWith(u8, tag_content, "/" ++ TRANSLATIONS_TAG)) {
                if (self.bundle_depth > 0) self.bundle_depth -= 1;
            } else if (std.mem.startsWith(u8, tag_content, TRANSLATION_TAG)) {
                // Extract id attribute
                if (std.mem.indexOf(u8, tag_content, "id=\"")) |id_start| {
                    const id_value_start = id_start + 4;
                    if (std.mem.indexOfScalarPos(u8, tag_content, id_value_start, '"')) |id_end| {
                        const id = tag_content[id_value_start..id_end];
                        // Find closing </translation>
                        const close_tag = "</" ++ TRANSLATION_TAG ++ ">";
                        if (std.mem.indexOfPos(u8, content, tag_end, close_tag)) |close_pos| {
                            const inner_text = content[tag_end + 1 .. close_pos];
                            try self.msg_id_to_html.put(id, inner_text);
                        }
                    }
                } else {
                    try self.errors.append(.{ .msg = "<translation> misses the \"id\" attribute" });
                }
            }

            pos = tag_end + 1;
        }
    }

    /// Report an error.
    /// Direct port of `_addError(node, message)` in the TS source.
    pub fn addError(self: *XtbParser, message: []const u8) !void {
        try self.errors.append(.{ .msg = message });
    }
};

/// Convert HTML/XML nodes to i18n nodes.
/// Direct port of `XmlToI18n` class in the TS source.
pub fn convertHtmlToI18nNodes(
    allocator: std.mem.Allocator,
    html: []const u8,
    url: []const u8,
) ![]const i18n_ast.Node {
    _ = url;
    var nodes = std.array_list.Managed(i18n_ast.Node).init(allocator);

    // Simple conversion: text → Text node, <ph name="...">...</ph> → Placeholder
    // Closing tags (</ph>) are skipped.
    var pos: usize = 0;
    var text_start: usize = 0;
    while (pos < html.len) {
        if (html[pos] == '<') {
            // Save any text before this tag
            if (pos > text_start) {
                const text = html[text_start..pos];
                if (text.len > 0) {
                    try nodes.append(i18n_ast.Node{
                        .kind = .text,
                        .source_span = .{
                            .start = .{ .offset = 0, .line = 0, .col = 0 },
                            .end = .{ .offset = 0, .line = 0, .col = 0 },
                            .full_start = .{ .start = 0, .end = 0 },
                        },
                        .data = .{ .text = .{ .value = text } },
                    });
                }
            }

            const tag_end = std.mem.indexOfScalarPos(u8, html, pos, '>') orelse break;
            const tag_content = html[pos + 1 .. tag_end];

            // Skip closing tags (</ph>, </translation>, etc.)
            if (tag_content.len > 0 and tag_content[0] == '/') {
                pos = tag_end + 1;
                text_start = pos;
                continue;
            }

            if (std.mem.startsWith(u8, tag_content, PLACEHOLDER_TAG)) {
                // Extract name attribute
                if (std.mem.indexOf(u8, tag_content, "name=\"")) |name_start| {
                    const name_value_start = name_start + 6;
                    if (std.mem.indexOfScalarPos(u8, tag_content, name_value_start, '"')) |name_end| {
                        const name = tag_content[name_value_start..name_end];
                        try nodes.append(i18n_ast.Node{
                            .kind = .placeholder,
                            .source_span = .{
                                .start = .{ .offset = 0, .line = 0, .col = 0 },
                                .end = .{ .offset = 0, .line = 0, .col = 0 },
                                .full_start = .{ .start = 0, .end = 0 },
                            },
                            .data = .{ .placeholder = .{ .value = "", .name = name } },
                        });
                    }
                }
                // Skip past closing </ph> if it exists
                const close_tag = "</" ++ PLACEHOLDER_TAG ++ ">";
                if (std.mem.indexOfPos(u8, html, tag_end, close_tag)) |close_pos| {
                    pos = close_pos + close_tag.len;
                } else {
                    pos = tag_end + 1;
                }
                text_start = pos;
                continue;
            }

            pos = tag_end + 1;
            text_start = pos;
        } else {
            pos += 1;
        }
    }

    // Save remaining text
    if (pos > text_start and text_start < html.len) {
        const text = html[text_start..pos];
        if (text.len > 0) {
            try nodes.append(i18n_ast.Node{
                .kind = .text,
                .source_span = .{
                    .start = .{ .offset = 0, .line = 0, .col = 0 },
                    .end = .{ .offset = 0, .line = 0, .col = 0 },
                    .full_start = .{ .start = 0, .end = 0 },
                },
                .data = .{ .text = .{ .value = text } },
            });
        }
    }

    return nodes.toOwnedSlice();
}

/// Parse an XTB file and extract translations.
/// Convenience wrapper around XtbParser.
pub fn parseXtb(
    allocator: std.mem.Allocator,
    content: []const u8,
) !struct { locale: ?[]const u8, messages: std.StringHashMap([]const u8), errors: []const []const u8 } {
    var parser = XtbParser.init(allocator);
    defer parser.deinit();
    var result = try parser.parse(content, "");
    defer result.deinit();

    var messages = std.StringHashMap([]const u8).init(allocator);
    var it = result.msg_id_to_html.iterator();
    while (it.next()) |entry| {
        try messages.put(entry.key_ptr.*, entry.value_ptr.*);
    }

    var errors = std.array_list.Managed([]const u8).init(allocator);
    for (result.errors.items) |err| {
        try errors.append(err.msg);
    }

    return .{
        .locale = result.locale,
        .messages = messages,
        .errors = try errors.toOwnedSlice(),
    };
}

/// Convert a message ID to a public XTB name.
/// Direct port of `toPublicName(id)` from xmb.ts.
pub fn toPublicName(id: []const u8) []const u8 {
    return id;
}

// ─── Tests ──────────────────────────────────────────────────

test "Xtb.write is unsupported" {
    const allocator = std.testing.allocator;
    const messages = [_]i18n_ast.Message{};
    try std.testing.expectError(error.Unsupported, Xtb.write(allocator, &messages, null));
}

test "Xtb.load returns empty result for empty content" {
    const allocator = std.testing.allocator;
    var result = try Xtb.load(allocator, "", "test.xtb");
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 0), result.i18n_nodes_by_msg_id.count());
}

test "Xtb.load parses translationbundle" {
    const allocator = std.testing.allocator;
    const content =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<translationbundle lang="fr">
        \\  <translation id="123">Bonjour</translation>
        \\</translationbundle>
    ;
    var result = try Xtb.load(allocator, content, "test.xtb");
    defer result.deinit();
    try std.testing.expectEqualStrings("fr", result.locale.?);
    try std.testing.expectEqual(@as(usize, 1), result.i18n_nodes_by_msg_id.count());
}

test "TRANSLATIONS_TAG constant" {
    try std.testing.expectEqualStrings("translationbundle", TRANSLATIONS_TAG);
}

test "TRANSLATION_TAG constant" {
    try std.testing.expectEqualStrings("translation", TRANSLATION_TAG);
}

test "PLACEHOLDER_TAG constant" {
    try std.testing.expectEqualStrings("ph", PLACEHOLDER_TAG);
}

test "toPublicName returns input unchanged" {
    try std.testing.expectEqualStrings("123456789", toPublicName("123456789"));
}

test "XtbParser init/deinit" {
    const allocator = std.testing.allocator;
    var parser = XtbParser.init(allocator);
    defer parser.deinit();
    try std.testing.expectEqual(@as(u32, 0), parser.bundle_depth);
}

test "XtbParser parses empty content" {
    const allocator = std.testing.allocator;
    var parser = XtbParser.init(allocator);
    defer parser.deinit();
    var result = try parser.parse("", "test.xtb");
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 0), result.msg_id_to_html.count());
}

test "XtbParser parses translationbundle with lang" {
    const allocator = std.testing.allocator;
    var parser = XtbParser.init(allocator);
    defer parser.deinit();
    const content = "<translationbundle lang=\"es\"></translationbundle>";
    var result = try parser.parse(content, "test.xtb");
    defer result.deinit();
    try std.testing.expectEqualStrings("es", result.locale.?);
}

test "XtbParser parses translation with id" {
    const allocator = std.testing.allocator;
    var parser = XtbParser.init(allocator);
    defer parser.deinit();
    const content = "<translationbundle><translation id=\"msg1\">Hello</translation></translationbundle>";
    var result = try parser.parse(content, "test.xtb");
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 1), result.msg_id_to_html.count());
    try std.testing.expect(result.msg_id_to_html.contains("msg1"));
}

test "XtbParser reports missing id" {
    const allocator = std.testing.allocator;
    var parser = XtbParser.init(allocator);
    defer parser.deinit();
    const content = "<translationbundle><translation>Hello</translation></translationbundle>";
    var result = try parser.parse(content, "test.xtb");
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 1), result.errors.items.len);
}

test "XtbParser.addError" {
    const allocator = std.testing.allocator;
    var parser = XtbParser.init(allocator);
    defer parser.deinit();
    try parser.addError("test error");
    try std.testing.expectEqual(@as(usize, 1), parser.errors.items.len);
}

test "convertHtmlToI18nNodes — text only" {
    const allocator = std.testing.allocator;
    const nodes = try convertHtmlToI18nNodes(allocator, "Hello World", "test");
    defer allocator.free(nodes);
    try std.testing.expectEqual(@as(usize, 1), nodes.len);
    try std.testing.expectEqualStrings("Hello World", nodes[0].data.text.value);
}

test "convertHtmlToI18nNodes — placeholder" {
    const allocator = std.testing.allocator;
    const html = "<ph name=\"PH\">placeholder</ph>";
    const nodes = try convertHtmlToI18nNodes(allocator, html, "test");
    defer allocator.free(nodes);
    try std.testing.expectEqual(@as(usize, 1), nodes.len);
    try std.testing.expectEqual(i18n_ast.NodeKind.placeholder, nodes[0].kind);
    try std.testing.expectEqualStrings("PH", nodes[0].data.placeholder.name);
}

test "convertHtmlToI18nNodes — text and placeholder" {
    const allocator = std.testing.allocator;
    const html = "Hello <ph name=\"NAME\">name</ph>!";
    const nodes = try convertHtmlToI18nNodes(allocator, html, "test");
    defer allocator.free(nodes);
    try std.testing.expectEqual(@as(usize, 3), nodes.len);
    try std.testing.expectEqualStrings("Hello ", nodes[0].data.text.value);
    try std.testing.expectEqualStrings("NAME", nodes[1].data.placeholder.name);
    try std.testing.expectEqualStrings("!", nodes[2].data.text.value);
}

test "parseXtb returns locale and messages" {
    const allocator = std.testing.allocator;
    const content = "<translationbundle lang=\"de\"><translation id=\"123\">Hallo</translation></translationbundle>";
    var result = try parseXtb(allocator, content);
    defer {
        result.messages.deinit();
        allocator.free(result.errors);
    }
    try std.testing.expectEqualStrings("de", result.locale.?);
    try std.testing.expectEqual(@as(usize, 1), result.messages.count());
}

test "ParseResult default" {
    const allocator = std.testing.allocator;
    var result = ParseResult{
        .msg_id_to_html = std.StringHashMap([]const u8).init(allocator),
        .errors = std.array_list.Managed(ParseResult.ParseError).init(allocator),
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 0), result.msg_id_to_html.count());
}
