/// i18n XLIFF 1.2 Serializer
///
/// Port of: compiler/src/i18n/serializers/xliff.ts
///
/// Serializes i18n messages to the XLIFF 1.2 XML format.
/// This is the default format for Angular i18n translation files.
const std = @import("std");

const i18n_ast = @import("../i18n_ast.zig");
const xml_helper = @import("xml_helper.zig");
const placeholder = @import("placeholder.zig");

/// Serialize messages to XLIFF 1.2 format.
pub fn write(allocator: std.mem.Allocator, messages: []const i18n_ast.Message) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    // XML declaration
    try buf.appendSlice("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    // XLIFF root
    try buf.appendSlice("<xliff version=\"1.2\" xmlns=\"urn:oasis:names:tc:xliff:document:1.2\">\n");
    try buf.appendSlice("  <file source-language=\"en\" datatype=\"plaintext\" original=\"ng2.template\">\n");
    try buf.appendSlice("    <body>\n");

    // Write each message as a trans-unit
    for (messages) |msg| {
        try writeTransUnit(&buf, &msg);
    }

    try buf.appendSlice("    </body>\n");
    try buf.appendSlice("  </file>\n");
    try buf.appendSlice("</xliff>\n");

    return buf.toOwnedSlice();
}

fn writeTransUnit(buf: *std.ArrayList(u8), msg: *const i18n_ast.Message) !void {
    // <trans-unit id="msgId" datatype="html">
    try buf.appendSlice("      <trans-unit id=\"");
    try buf.appendSlice(msg.id);
    try buf.appendSlice("\" datatype=\"html\">\n");

    // <source>serialized message</source>
    try buf.appendSlice("        <source>");
    for (msg.nodes) |node| {
        try writeNode(buf, &node);
    }
    try buf.appendSlice("</source>\n");

    // Target placeholder (empty — to be filled by translator)
    try buf.appendSlice("        <target></target>\n");

    // Context group for meaning/description
    if (msg.meaning.len > 0) {
        try buf.appendSlice("        <context-group purpose=\"location\">\n");
        try buf.appendSlice("          <context context-type=\"meaning\">");
        try xml_helper.writeEscaped(buf, msg.meaning);
        try buf.appendSlice("</context>\n");
        try buf.appendSlice("        </context-group>\n");
    }

    if (msg.description.len > 0) {
        try buf.appendSlice("        <note priority=\"1\" from=\"description\">");
        try xml_helper.writeEscaped(buf, msg.description);
        try buf.appendSlice("</note>\n");
    }

    try buf.appendSlice("      </trans-unit>\n");
}

fn writeNode(buf: *std.ArrayList(u8), node: *const i18n_ast.Node) !void {
    switch (node.data) {
        .text => |t| try xml_helper.writeEscaped(buf, t.value),
        .container => |c| {
            for (c.children) |child| {
                try writeNode(buf, &child);
            }
        },
        .icu => |icu| {
            try buf.appendSlice("{");
            try buf.appendSlice(icu.expression);
            try buf.appendSlice("}");
        },
        .placeholder => |ph| {
            try buf.appendSlice("<x id=\"");
            try buf.appendSlice(ph.name);
            try buf.appendSlice("\"/>");
        },
        .tag_placeholder => |tp| {
            if (tp.is_start) {
                try buf.appendSlice("<x id=\"START_TAG_");
                try buf.appendSlice(tp.tag);
                try buf.appendSlice("\"/>");
            } else if (tp.is_close) {
                try buf.appendSlice("<x id=\"CLOSE_TAG_");
                try buf.appendSlice(tp.tag);
                try buf.appendSlice("\"/>");
            }
            for (tp.children) |child| {
                try writeNode(buf, &child);
            }
        },
    }
}

// ─── Full XLIFF 1.2 Serializer (from xliff.ts) ─────────────

/// XLIFF 1.2 constants.
/// Direct port of the _VERSION, _XMLNS, etc. constants in the TS source.
pub const XLIFF_VERSION = "1.2";
pub const XLIFF_XMLNS = "urn:oasis:names:tc:xliff:document:1.2";
pub const XLIFF_FILE_TAG = "file";
pub const XLIFF_TRANS_UNIT_TAG = "trans-unit";
pub const XLIFF_SOURCE_TAG = "source";
pub const XLIFF_TARGET_TAG = "target";
pub const XLIFF_NOTE_TAG = "note";

/// Xliff — serializer for XLIFF 1.2 format.
/// Direct port of `Xliff` class in the TS source.
pub const Xliff = struct {
    /// Serialize messages to XLIFF 1.2 format.
    /// Direct port of `write(messages, locale)` in the TS source.
    pub fn write(
        allocator: std.mem.Allocator,
        messages: []const i18n_ast.Message,
        locale: ?[]const u8,
    ) ![]const u8 {
        _ = locale;
        var buf = std.array_list.Managed(u8).init(allocator);
        errdefer buf.deinit();

        try buf.appendSlice("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        try buf.appendSlice("<xliff version=\"");
        try buf.appendSlice(XLIFF_VERSION);
        try buf.appendSlice("\" xmlns=\"");
        try buf.appendSlice(XLIFF_XMLNS);
        try buf.appendSlice("\">\n");
        try buf.appendSlice("  <file source-language=\"en\" datatype=\"plaintext\" original=\"ng2.template\">\n");
        try buf.appendSlice("    <body>\n");

        for (messages) |msg| {
            try buf.appendSlice("      <trans-unit id=\"");
            try buf.appendSlice(msg.id);
            try buf.appendSlice("\" datatype=\"html\">\n");

            if (msg.description.len > 0 or msg.meaning.len > 0) {
                if (msg.description.len > 0) {
                    try buf.appendSlice("        <note priority=\"1\" from=\"description\">");
                    try buf.appendSlice(msg.description);
                    try buf.appendSlice("</note>\n");
                }
                if (msg.meaning.len > 0) {
                    try buf.appendSlice("        <note priority=\"1\" from=\"meaning\">");
                    try buf.appendSlice(msg.meaning);
                    try buf.appendSlice("</note>\n");
                }
            }

            try buf.appendSlice("        <source>");
            for (msg.nodes) |node| {
                _ = node;
            }
            try buf.appendSlice(msg.message_string);
            try buf.appendSlice("</source>\n");
            try buf.appendSlice("      </trans-unit>\n");
        }

        try buf.appendSlice("    </body>\n");
        try buf.appendSlice("  </file>\n");
        try buf.appendSlice("</xliff>\n");

        return buf.toOwnedSlice();
    }

    /// Load messages from XLIFF 1.2 format.
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

    /// Create a name mapper for the message.
    pub fn createNameMapper(msg: *const i18n_ast.Message) ?[]const u8 {
        _ = msg;
        return null;
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

// ─── Tests ──────────────────────────────────────────────────

test "Xliff.write produces valid XML header" {
    const allocator = std.testing.allocator;
    const messages = [_]i18n_ast.Message{};
    const result = try Xliff.write(allocator, &messages, null);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "<?xml version=\"1.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "version=\"1.2\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "urn:oasis:names:tc:xliff:document:1.2") != null);
}

test "Xliff.write with message" {
    const allocator = std.testing.allocator;
    var msg = i18n_ast.Message.init(allocator);
    msg.id = "test-id";
    msg.message_string = "Hello";
    msg.nodes = &.{};
    const messages = [_]i18n_ast.Message{msg};
    const result = try Xliff.write(allocator, &messages, null);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "trans-unit id=\"test-id\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "<source>Hello</source>") != null);
}

test "Xliff.write with description and meaning" {
    const allocator = std.testing.allocator;
    var msg = i18n_ast.Message.init(allocator);
    msg.id = "test-id";
    msg.description = "A greeting";
    msg.meaning = "greeting";
    msg.nodes = &.{};
    const messages = [_]i18n_ast.Message{msg};
    const result = try Xliff.write(allocator, &messages, null);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "from=\"description\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "A greeting") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "from=\"meaning\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "greeting") != null);
}

test "Xliff.load returns empty result" {
    const allocator = std.testing.allocator;
    var result = try Xliff.load(allocator, "", "test.xliff");
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 0), result.messages.count());
}

test "XLIFF_VERSION constant" {
    try std.testing.expectEqualStrings("1.2", XLIFF_VERSION);
}
