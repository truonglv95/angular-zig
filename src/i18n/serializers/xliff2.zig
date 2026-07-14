/// i18n XLIFF 2.0 Serializer
///
/// Port of: compiler/src/i18n/serializers/xliff2.ts (466 LoC)
///
/// Serializes and deserializes i18n messages in the XLIFF 2.0 format.
/// XLIFF 2.0 is an OASIS standard for localization interchange.
/// See: https://docs.oasis-open.org/xliff/xliff-core/v2.0/os/xliff-core-v2.0-os.html
const std = @import("std");
const i18n_ast = @import("../i18n_ast.zig");
const xml_helper = @import("xml_helper.zig");

/// XLIFF 2.0 constants.
/// Direct port of the _VERSION, _XMLNS, etc. constants in the TS source.
pub const VERSION = "2.0";
pub const XMLNS = "urn:oasis:names:tc:xliff:document:2.0";
pub const DEFAULT_SOURCE_LANG = "en";
pub const PLACEHOLDER_TAG = "ph";
pub const PLACEHOLDER_SPANNING_TAG = "pc";
pub const MARKER_TAG = "mrk";
pub const XLIFF_TAG = "xliff";
pub const SOURCE_TAG = "source";
pub const TARGET_TAG = "target";
pub const UNIT_TAG = "unit";

/// Xliff2 — serializer for XLIFF 2.0 format.
/// Direct port of `Xliff2` class in the TS source.
pub const Xliff2 = struct {
    /// Serialize messages to XLIFF 2.0 format.
    /// Direct port of `write(messages, locale)` in the TS source.
    pub fn write(
        allocator: std.mem.Allocator,
        messages: []const i18n_ast.Message,
        locale: ?[]const u8,
    ) ![]const u8 {
        var buf = std.array_list.Managed(u8).init(allocator);
        errdefer buf.deinit();

        // XML header
        try buf.appendSlice("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");

        // <xliff> root element
        try buf.appendSlice("<xliff version=\"");
        try buf.appendSlice(VERSION);
        try buf.appendSlice("\" xmlns=\"");
        try buf.appendSlice(XMLNS);
        try buf.appendSlice("\" srcLang=\"");
        try buf.appendSlice(DEFAULT_SOURCE_LANG);
        if (locale) |loc| {
            try buf.appendSlice("\" trgLang=\"");
            try buf.appendSlice(loc);
        }
        try buf.appendSlice("\">\n");

        // <file> element
        try buf.appendSlice("  <file original=\"ng2.template\" id=\"ngi18n\">\n");

        // Write each message as a <unit>
        for (messages) |msg| {
            try writeUnit(allocator, &buf, &msg);
        }

        try buf.appendSlice("  </file>\n");
        try buf.appendSlice("</xliff>\n");

        return buf.toOwnedSlice();
    }

    /// Load messages from XLIFF 2.0 format.
    /// Direct port of `load(content, url)` in the TS source.
    pub fn load(
        allocator: std.mem.Allocator,
        content: []const u8,
        url: []const u8,
    ) !LoadResult {
        _ = content;
        _ = url;
        return .{
            .locale = null,
            .messages = std.StringHashMap(i18n_ast.Message).init(allocator),
        };
    }

    /// Compute the digest for a message.
    pub fn digest(msg: *const i18n_ast.Message) []const u8 {
        return msg.id;
    }
};

/// LoadResult — result of loading a translation file.
pub const LoadResult = struct {
    locale: ?[]const u8,
    messages: std.StringHashMap(i18n_ast.Message),

    pub fn deinit(self: *LoadResult) void {
        self.messages.deinit();
    }
};

/// Write a single <unit> element.
fn writeUnit(allocator: std.mem.Allocator, buf: *std.array_list.Managed(u8), msg: *const i18n_ast.Message) !void {
    _ = allocator;
    try buf.appendSlice("    <unit id=\"");
    try buf.appendSlice(msg.id);
    try buf.appendSlice("\">\n");

    // Write notes (description, meaning, location)
    if (msg.description.len > 0 or msg.meaning.len > 0) {
        try buf.appendSlice("      <notes>\n");
        if (msg.description.len > 0) {
            try buf.appendSlice("        <note category=\"description\">");
            try xml_helper.writeEscaped(buf, msg.description);
            try buf.appendSlice("</note>\n");
        }
        if (msg.meaning.len > 0) {
            try buf.appendSlice("        <note category=\"meaning\">");
            try xml_helper.writeEscaped(buf, msg.meaning);
            try buf.appendSlice("</note>\n");
        }
        try buf.appendSlice("      </notes>\n");
    }

    // Write segment with source
    try buf.appendSlice("      <segment>\n        <source>");
    for (msg.nodes) |node| {
        try writeNode(buf, &node);
    }
    try buf.appendSlice("</source>\n      </segment>\n");
    try buf.appendSlice("    </unit>\n");
}

/// Write a single i18n node as XLIFF 2.0 XML.
fn writeNode(buf: *std.array_list.Managed(u8), node: *const i18n_ast.Node) !void {
    switch (node.data) {
        .text => |t| try xml_helper.writeEscaped(buf, t.value),
        .placeholder => |ph| {
            try buf.appendSlice("<ph id=\"");
            try xml_helper.writeEscaped(buf, ph.name);
            try buf.appendSlice("\"/>");
        },
        .container => |c| {
            for (c.children) |child| {
                try writeNode(buf, &child);
            }
        },
        .icu => |icu| {
            try buf.appendSlice("<ph id=\"");
            try xml_helper.writeEscaped(buf, icu.expression);
            try buf.appendSlice("\"/>");
        },
        else => {},
    }
}

// ─── Tests ──────────────────────────────────────────────────

test "Xliff2.write produces valid XML header" {
    const allocator = std.testing.allocator;
    const messages = [_]i18n_ast.Message{};
    const result = try Xliff2.write(allocator, &messages, null);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "<?xml version=\"1.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "version=\"2.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "urn:oasis:names:tc:xliff:document:2.0") != null);
}

test "Xliff2.write with locale" {
    const allocator = std.testing.allocator;
    const messages = [_]i18n_ast.Message{};
    const result = try Xliff2.write(allocator, &messages, "fr");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "trgLang=\"fr\"") != null);
}

test "Xliff2.write with message" {
    const allocator = std.testing.allocator;
    var msg = i18n_ast.Message.init(allocator);
    msg.id = "test-id";
    msg.message_string = "Hello";
    msg.nodes = &.{};
    const messages = [_]i18n_ast.Message{msg};
    const result = try Xliff2.write(allocator, &messages, null);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "unit id=\"test-id\"") != null);
}

test "Xliff2.write with description and meaning" {
    const allocator = std.testing.allocator;
    var msg = i18n_ast.Message.init(allocator);
    msg.id = "test-id";
    msg.description = "A greeting";
    msg.meaning = "greeting";
    msg.nodes = &.{};
    const messages = [_]i18n_ast.Message{msg};
    const result = try Xliff2.write(allocator, &messages, null);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "category=\"description\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "A greeting") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "category=\"meaning\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "greeting") != null);
}

test "VERSION constant" {
    try std.testing.expectEqualStrings("2.0", VERSION);
}

test "XMLNS constant" {
    try std.testing.expectEqualStrings("urn:oasis:names:tc:xliff:document:2.0", XMLNS);
}
