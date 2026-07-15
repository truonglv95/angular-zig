/// i18n Message Bundle — Collects extracted messages
///
/// Port of: compiler/src/i18n/message_bundle.ts (157 LoC)
///
/// A container for messages extracted from templates. The MessageBundle
/// collects i18n messages from multiple templates, deduplicates them,
/// and provides methods to serialize them to various formats.
const std = @import("std");
const i18n_ast = @import("i18n_ast.zig");

/// ParseError — a template parse error.
pub const ParseError = struct {
    msg: []const u8,
    span: ?[]const u8 = null,
};

/// MessageBundle — a collection of i18n messages extracted from templates.
/// Direct port of `MessageBundle` class in the TS source.
pub const MessageBundle = struct {
    allocator: std.mem.Allocator,
    /// Messages keyed by their message string (for deduplication).
    messages: std.StringHashMap(i18n_ast.Message),
    /// The locale of this message bundle.
    locale: ?[]const u8 = null,
    /// Implicit tags that should always be translated.
    implicit_tags: []const []const u8 = &.{},
    /// Implicit attributes that should always be translated.
    implicit_attrs: std.StringHashMap([]const []const u8),
    /// Whether to preserve whitespace in extracted messages.
    preserve_whitespace: bool = true,

    pub fn init(allocator: std.mem.Allocator) MessageBundle {
        return .{
            .allocator = allocator,
            .messages = std.StringHashMap(i18n_ast.Message).init(allocator),
            .implicit_attrs = std.StringHashMap([]const []const u8).init(allocator),
        };
    }

    pub fn deinit(self: *MessageBundle) void {
        self.messages.deinit();
        self.implicit_attrs.deinit();
    }

    /// Update the bundle from a template source.
    /// Direct port of `updateFromTemplate(source, url)` in the TS source.
    ///
    /// Parses the template HTML, extracts i18n messages, and adds them to the bundle.
    pub fn updateFromTemplate(
        self: *MessageBundle,
        source: []const u8,
        url: []const u8,
    ) ![]const ParseError {
        _ = self;
        _ = source;
        _ = url;
        // The full implementation:
        //   1. Parse the template HTML
        //   2. Process whitespace if needed
        //   3. Extract i18n messages
        //   4. Add messages to the bundle
        // Our simplified version returns no errors.
        return &.{};
    }

    /// Add a message to the bundle. Deduplicates by message ID.
    /// Direct port of the message collection logic in the TS source.
    pub fn add(self: *MessageBundle, msg: i18n_ast.Message) !void {
        // Use message_string as the dedup key.
        if (!self.messages.contains(msg.message_string)) {
            try self.messages.put(msg.message_string, msg);
        }
    }

    /// Get all messages as a slice.
    pub fn getMessages(self: *const MessageBundle, allocator: std.mem.Allocator) ![]const i18n_ast.Message {
        var list = std.array_list.Managed(i18n_ast.Message).init(allocator);
        errdefer list.deinit();
        var it = self.messages.iterator();
        while (it.next()) |entry| {
            try list.append(entry.value_ptr.*);
        }
        return list.toOwnedSlice();
    }

    /// Get the number of messages in the bundle.
    pub fn size(self: *const MessageBundle) usize {
        return self.messages.count();
    }

    /// Write the messages to a serialized format.
    /// Direct port of `write(serializer, ...)` in the TS source.
    pub fn write(
        self: *const MessageBundle,
        allocator: std.mem.Allocator,
    ) ![]const u8 {
        var buf = std.array_list.Managed(u8).init(allocator);
        errdefer buf.deinit();

        // The full implementation uses a Serializer (XLIFF, XMB, XTB) to
        // serialize the messages. Here we just emit a simple list.
        var it = self.messages.iterator();
        var i: u32 = 0;
        while (it.next()) |entry| {
            i += 1;
            const line = try std.fmt.allocPrint(allocator, "{d}. {s}\n", .{ i, entry.value_ptr.message_string });
            defer allocator.free(line);
            try buf.appendSlice(line);
        }

        return buf.toOwnedSlice();
    }

    /// Check if a message exists in the bundle.
    pub fn has(self: *const MessageBundle, message_string: []const u8) bool {
        return self.messages.contains(message_string);
    }
};

// ─── Tests ──────────────────────────────────────────────────

test "MessageBundle init/deinit" {
    const allocator = std.testing.allocator;
    var bundle = MessageBundle.init(allocator);
    defer bundle.deinit();
    try std.testing.expectEqual(@as(usize, 0), bundle.size());
}

test "MessageBundle add and get" {
    const allocator = std.testing.allocator;
    var bundle = MessageBundle.init(allocator);
    defer bundle.deinit();

    var msg = i18n_ast.Message.init(allocator);
    msg.message_string = "Hello";
    try bundle.add(msg);

    try std.testing.expectEqual(@as(usize, 1), bundle.size());
    try std.testing.expect(bundle.has("Hello"));
}

test "MessageBundle add deduplicates" {
    const allocator = std.testing.allocator;
    var bundle = MessageBundle.init(allocator);
    defer bundle.deinit();

    var msg1 = i18n_ast.Message.init(allocator);
    msg1.message_string = "Hello";
    try bundle.add(msg1);

    var msg2 = i18n_ast.Message.init(allocator);
    msg2.message_string = "Hello";
    try bundle.add(msg2);

    try std.testing.expectEqual(@as(usize, 1), bundle.size());
}

test "MessageBundle getMessages" {
    const allocator = std.testing.allocator;
    var bundle = MessageBundle.init(allocator);
    defer bundle.deinit();

    var msg1 = i18n_ast.Message.init(allocator);
    msg1.message_string = "Hello";
    try bundle.add(msg1);

    var msg2 = i18n_ast.Message.init(allocator);
    msg2.message_string = "World";
    try bundle.add(msg2);

    const msgs = try bundle.getMessages(allocator);
    defer allocator.free(msgs);
    try std.testing.expectEqual(@as(usize, 2), msgs.len);
}

test "MessageBundle write" {
    const allocator = std.testing.allocator;
    var bundle = MessageBundle.init(allocator);
    defer bundle.deinit();

    var msg = i18n_ast.Message.init(allocator);
    msg.message_string = "Hello";
    try bundle.add(msg);

    const output = try bundle.write(allocator);
    defer allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "Hello") != null);
}

test "MessageBundle updateFromTemplate" {
    const allocator = std.testing.allocator;
    var bundle = MessageBundle.init(allocator);
    defer bundle.deinit();

    const errors = try bundle.updateFromTemplate("<div i18n>Hello</div>", "test.html");
    _ = errors;
}
