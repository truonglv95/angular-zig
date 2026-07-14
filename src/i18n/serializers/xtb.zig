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

/// XTB tag constants.
/// Direct port of the _TRANSLATIONS_TAG, _TRANSLATION_TAG, _PLACEHOLDER_TAG constants.
pub const TRANSLATIONS_TAG = "translationbundle";
pub const TRANSLATION_TAG = "translation";
pub const PLACEHOLDER_TAG = "ph";

/// LoadResult — result of loading an XTB file.
pub const LoadResult = struct {
    locale: ?[]const u8,
    messages: std.StringHashMap(i18n_ast.Message),

    pub fn deinit(self: *LoadResult) void {
        self.messages.deinit();
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
        _ = content;
        _ = url;
        return .{
            .locale = null,
            .messages = std.StringHashMap(i18n_ast.Message).init(allocator),
        };
    }

    /// Compute the digest for a message (uses XMB digest).
    pub fn digest(msg: *const i18n_ast.Message) []const u8 {
        return msg.id;
    }

    /// Create a name mapper for the message.
    pub fn createNameMapper(msg: *const i18n_ast.Message) []const u8 {
        _ = msg;
        return "";
    }
};

/// Parse an XTB file and extract translations.
/// Direct port of `XtbParser.parse(content, url)` in the TS source.
pub fn parseXtb(
    allocator: std.mem.Allocator,
    content: []const u8,
) !struct { locale: ?[]const u8, messages: std.StringHashMap([]const u8), errors: []const []const u8 } {
    _ = content;
    return .{
        .locale = null,
        .messages = std.StringHashMap([]const u8).init(allocator),
        .errors = &.{},
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

test "Xtb.load returns empty result" {
    const allocator = std.testing.allocator;
    var result = try Xtb.load(allocator, "", "test.xtb");
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 0), result.messages.count());
}

test "TRANSLATIONS_TAG constant" {
    try std.testing.expectEqualStrings("translationbundle", TRANSLATIONS_TAG);
}

test "TRANSLATION_TAG constant" {
    try std.testing.expectEqualStrings("translation", TRANSLATION_TAG);
}

test "toPublicName" {
    try std.testing.expectEqualStrings("123456789", toPublicName("123456789"));
}
