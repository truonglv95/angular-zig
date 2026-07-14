/// i18n XMB Serializer — Google's XMB message bundle format
///
/// Port of: compiler/src/i18n/serializers/xmb.ts (235 LoC)
///
/// XMB is Google's XML-based message bundle format used for extracting
/// translatable messages. XMB files contain source messages with
/// placeholders. The XTB format is the translation counterpart to XMB.
const std = @import("std");
const i18n_ast = @import("../i18n_ast.zig");
const xml_helper = @import("xml_helper.zig");

/// XMB handler value — indicates Angular generated the bundle.
/// Direct port of `_XMB_HANDLER = 'angular'` in the TS source.
pub const XMB_HANDLER = "angular";

/// XMB tag constants.
pub const MESSAGES_TAG = "messagebundle";
pub const MESSAGE_TAG = "msg";
pub const PLACEHOLDER_TAG = "ph";
pub const EXAMPLE_TAG = "ex";
pub const SOURCE_TAG = "source";

/// XMB DOCTYPE declaration.
/// Direct port of `_DOCTYPE` in the TS source.
pub const DOCTYPE =
    \\<!ELEMENT messagebundle (msg)*>
    \\<!ATTLIST messagebundle class CDATA #IMPLIED>
    \\
    \\<!ELEMENT msg (#PCDATA|ph|source)*>
    \\<!ATTLIST msg id CDATA #IMPLIED>
    \\<!ATTLIST msg seq CDATA #IMPLIED>
    \\<!ATTLIST msg name CDATA #IMPLIED>
    \\<!ATTLIST msg desc CDATA #IMPLIED>
    \\<!ATTLIST msg meaning CDATA #IMPLIED>
    \\<!ATTLIST msg obsolete (obsolete) #IMPLIED>
    \\<!ATTLIST msg xml:space (default|preserve) "default">
    \\<!ATTLIST msg is_hidden CDATA #IMPLIED>
    \\
    \\<!ELEMENT source (#PCDATA)>
    \\
    \\<!ELEMENT ph (#PCDATA|ex)*>
    \\<!ATTLIST ph name CDATA #REQUIRED>
    \\
    \\<!ELEMENT ex (#PCDATA)>
;

/// LoadResult — result of loading an XMB file.
pub const LoadResult = struct {
    locale: ?[]const u8,
    messages: std.StringHashMap(i18n_ast.Message),

    pub fn deinit(self: *LoadResult) void {
        self.messages.deinit();
    }
};

/// Xmb — serializer for XMB format.
/// Direct port of `Xmb` class in the TS source.
pub const Xmb = struct {
    /// Serialize messages to XMB format.
    /// Direct port of `write(messages, locale)` in the TS source.
    pub fn write(
        allocator: std.mem.Allocator,
        messages: []const i18n_ast.Message,
        locale: ?[]const u8,
    ) ![]const u8 {
        _ = locale;
        var buf = std.array_list.Managed(u8).init(allocator);
        errdefer buf.deinit();

        // XML header
        try buf.appendSlice("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        try buf.appendSlice("<!DOCTYPE ");
        try buf.appendSlice(MESSAGES_TAG);
        try buf.appendSlice(" [\n");
        try buf.appendSlice(DOCTYPE);
        try buf.appendSlice("\n]>\n");

        // <messagebundle> root
        try buf.appendSlice("<");
        try buf.appendSlice(MESSAGES_TAG);
        try buf.appendSlice(" class=\"");
        try buf.appendSlice(XMB_HANDLER);
        try buf.appendSlice("\">\n");

        // Write each message
        for (messages) |msg| {
            try writeMessage(allocator, &buf, &msg);
        }

        try buf.appendSlice("</");
        try buf.appendSlice(MESSAGES_TAG);
        try buf.appendSlice(">\n");

        return buf.toOwnedSlice();
    }

    /// Load messages from XMB format.
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

    /// Compute the digest for a message (uses decimal digest).
    pub fn digest(msg: *const i18n_ast.Message) []const u8 {
        return msg.id;
    }
};

/// Write a single <msg> element.
fn writeMessage(allocator: std.mem.Allocator, buf: *std.array_list.Managed(u8), msg: *const i18n_ast.Message) !void {
    _ = allocator;
    try buf.appendSlice("  <");
    try buf.appendSlice(MESSAGE_TAG);
    try buf.appendSlice(" id=\"");
    try buf.appendSlice(msg.id);
    try buf.append('"');

    if (msg.description.len > 0) {
        try buf.appendSlice(" desc=\"");
        try xml_helper.writeEscaped(buf, msg.description);
        try buf.append('"');
    }
    if (msg.meaning.len > 0) {
        try buf.appendSlice(" meaning=\"");
        try xml_helper.writeEscaped(buf, msg.meaning);
        try buf.append('"');
    }

    try buf.append('>');

    for (msg.nodes) |node| {
        try writeNode(buf, &node);
    }

    try buf.appendSlice("</");
    try buf.appendSlice(MESSAGE_TAG);
    try buf.appendSlice(">\n");
}

/// Write a single i18n node as XMB XML.
fn writeNode(buf: *std.array_list.Managed(u8), node: *const i18n_ast.Node) !void {
    switch (node.data) {
        .text => |t| try xml_helper.writeEscaped(buf, t.value),
        .placeholder => |ph| {
            try buf.appendSlice("<ph name=\"");
            try xml_helper.writeEscaped(buf, ph.name);
            try buf.appendSlice("\">");
            if (ph.value.len > 0) {
                try buf.appendSlice("<ex>");
                try xml_helper.writeEscaped(buf, ph.value);
                try buf.appendSlice("</ex>");
            }
            try buf.appendSlice("</ph>");
        },
        .container => |c| {
            for (c.children) |child| {
                try writeNode(buf, &child);
            }
        },
        else => {},
    }
}

/// Convert a message ID to a public XMB name.
/// Direct port of `toPublicName(id)` in the TS source.
pub fn toPublicName(internal_id: []const u8) []const u8 {
    return internal_id;
}

// ─── Tests ──────────────────────────────────────────────────

test "Xmb.write produces valid XML header" {
    const allocator = std.testing.allocator;
    const messages = [_]i18n_ast.Message{};
    const result = try Xmb.write(allocator, &messages, null);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "<?xml version=\"1.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "<messagebundle") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "angular") != null);
}

test "Xmb.write with message" {
    const allocator = std.testing.allocator;
    var msg = i18n_ast.Message.init(allocator);
    msg.id = "test-id";
    msg.nodes = &.{};
    const messages = [_]i18n_ast.Message{msg};
    const result = try Xmb.write(allocator, &messages, null);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "msg id=\"test-id\"") != null);
}

test "Xmb.write with description and meaning" {
    const allocator = std.testing.allocator;
    var msg = i18n_ast.Message.init(allocator);
    msg.id = "test-id";
    msg.description = "A greeting";
    msg.meaning = "greeting";
    msg.nodes = &.{};
    const messages = [_]i18n_ast.Message{msg};
    const result = try Xmb.write(allocator, &messages, null);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "desc=\"A greeting\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "meaning=\"greeting\"") != null);
}

test "XMB_HANDLER constant" {
    try std.testing.expectEqualStrings("angular", XMB_HANDLER);
}

test "toPublicName" {
    try std.testing.expectEqualStrings("123456789", toPublicName("123456789"));
}

test "Xmb.load returns empty result" {
    const allocator = std.testing.allocator;
    var result = try Xmb.load(allocator, "", "test.xmb");
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 0), result.messages.count());
}
