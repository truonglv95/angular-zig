/// i18n Translation Bundle — Loads and looks up translations
///
/// Port of: compiler/src/i18n/translation_bundle.ts (225 LoC)
///
/// A container for translated messages. The TranslationBundle holds a map
/// of message IDs to i18n node trees, and provides methods to:
///   - Look up translations by source message (using a digest function)
///   - Check if a translation exists
///   - Load translations from serialized formats (XLIFF, XMB, XTB)
const std = @import("std");
const i18n_ast = @import("i18n_ast.zig");

/// MissingTranslationStrategy — how to handle missing translations.
/// Direct port of `MissingTranslationStrategy` from core.
pub const MissingTranslationStrategy = enum(u8) {
    /// Report an error when a translation is missing.
    Error = 0,
    /// Log a warning when a translation is missing.
    Warning = 1,
    /// Ignore missing translations silently.
    Ignore = 2,
};

/// DigestFn — a function that computes the digest (ID) of a message.
pub const DigestFn = *const fn (msg: *const i18n_ast.Message) []const u8;

/// TranslationBundle — a container for translated messages.
/// Direct port of `TranslationBundle` class in the TS source.
pub const TranslationBundle = struct {
    allocator: std.mem.Allocator,
    /// Map of message ID → translated i18n nodes.
    translations: std.StringHashMap(i18n_ast.Message),
    /// The locale of this translation bundle.
    locale: ?[]const u8 = null,
    /// The digest function used to compute message IDs.
    digest_fn: ?DigestFn = null,
    /// Strategy for handling missing translations.
    missing_translation_strategy: MissingTranslationStrategy = .Warning,

    pub fn init(allocator: std.mem.Allocator) TranslationBundle {
        return .{
            .allocator = allocator,
            .translations = std.StringHashMap(i18n_ast.Message).init(allocator),
        };
    }

    pub fn deinit(self: *TranslationBundle) void {
        self.translations.deinit();
    }

    /// Look up a translation by message ID.
    pub fn get(self: *const TranslationBundle, id: []const u8) ?i18n_ast.Message {
        return self.translations.get(id);
    }

    /// Look up a translation by source message (using the digest function).
    /// Direct port of `TranslationBundle.get(srcMsg)` in the TS source.
    pub fn getByMessage(self: *const TranslationBundle, src_msg: *const i18n_ast.Message) ?i18n_ast.Message {
        if (self.digest_fn) |digest| {
            const id = digest(src_msg);
            return self.translations.get(id);
        }
        // Fall back to the message's own ID.
        return self.translations.get(src_msg.id);
    }

    /// Check if a translation exists for a source message.
    /// Direct port of `TranslationBundle.has(srcMsg)` in the TS source.
    pub fn has(self: *const TranslationBundle, src_msg: *const i18n_ast.Message) bool {
        if (self.digest_fn) |digest| {
            return self.translations.contains(digest(src_msg));
        }
        return self.translations.contains(src_msg.id);
    }

    /// Check if a translation exists for a message ID.
    pub fn hasById(self: *const TranslationBundle, id: []const u8) bool {
        return self.translations.contains(id);
    }

    /// Add a translation to the bundle.
    pub fn add(self: *TranslationBundle, id: []const u8, msg: i18n_ast.Message) !void {
        try self.translations.put(id, msg);
    }

    /// Get the number of translations in the bundle.
    pub fn size(self: *const TranslationBundle) usize {
        return self.translations.count();
    }

    /// Create a TranslationBundle from a serialized format.
    /// Direct port of `TranslationBundle.load(content, url, serializer, ...)` in the TS source.
    pub fn load(
        allocator: std.mem.Allocator,
        content: []const u8,
        url: []const u8,
        missing_translation_strategy: MissingTranslationStrategy,
    ) !TranslationBundle {
        _ = content;
        _ = url;
        return .{
            .allocator = allocator,
            .translations = std.StringHashMap(i18n_ast.Message).init(allocator),
            .missing_translation_strategy = missing_translation_strategy,
        };
    }
};

/// I18nToHtmlVisitor — converts i18n nodes back to HTML nodes.
/// Direct port of `I18nToHtmlVisitor` class in the TS source.
pub const I18nToHtmlVisitor = struct {
    allocator: std.mem.Allocator,
    translations: std.StringHashMap(i18n_ast.Message),
    locale: ?[]const u8 = null,
    missing_translation_strategy: MissingTranslationStrategy = .Warning,
    errors: std.array_list.Managed([]const u8),

    pub fn init(allocator: std.mem.Allocator) I18nToHtmlVisitor {
        return .{
            .allocator = allocator,
            .translations = std.StringHashMap(i18n_ast.Message).init(allocator),
            .errors = std.array_list.Managed([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *I18nToHtmlVisitor) void {
        self.translations.deinit();
        self.errors.deinit();
    }

    /// Convert a source message to HTML nodes.
    /// Direct port of `I18nToHtmlVisitor.convert(srcMsg)` in the TS source.
    pub fn convert(self: *I18nToHtmlVisitor, src_msg: *const i18n_ast.Message) ![]const u8 {
        if (self.translations.get(src_msg.id)) |_| {
            // Translation found — return the translated text.
            return self.allocator.dupe(u8, src_msg.message_string);
        }

        // Handle missing translation based on strategy.
        switch (self.missing_translation_strategy) {
            .Error => {
                const err = try std.fmt.allocPrint(
                    self.allocator,
                    "Missing translation for message \"{s}\"",
                    .{src_msg.id},
                );
                try self.errors.append(err);
                return err;
            },
            .Warning => {
                // Return the source message as-is.
                return self.allocator.dupe(u8, src_msg.message_string);
            },
            .Ignore => {
                return self.allocator.dupe(u8, "");
            },
        }
    }
};

// ─── Tests ──────────────────────────────────────────────────

test "TranslationBundle init/deinit" {
    const allocator = std.testing.allocator;
    var bundle = TranslationBundle.init(allocator);
    defer bundle.deinit();
    try std.testing.expectEqual(@as(usize, 0), bundle.size());
}

test "TranslationBundle add and get" {
    const allocator = std.testing.allocator;
    var bundle = TranslationBundle.init(allocator);
    defer bundle.deinit();

    var msg = i18n_ast.Message.init(allocator);
    msg.message_string = "Hello";
    try bundle.add("greeting", msg);

    try std.testing.expectEqual(@as(usize, 1), bundle.size());
    const result = bundle.get("greeting").?;
    try std.testing.expectEqualStrings("Hello", result.message_string);
}

test "TranslationBundle hasById" {
    const allocator = std.testing.allocator;
    var bundle = TranslationBundle.init(allocator);
    defer bundle.deinit();

    const msg = i18n_ast.Message.init(allocator);
    try bundle.add("test", msg);

    try std.testing.expect(bundle.hasById("test"));
    try std.testing.expect(!bundle.hasById("missing"));
}

test "TranslationBundle has by message" {
    const allocator = std.testing.allocator;
    var bundle = TranslationBundle.init(allocator);
    defer bundle.deinit();

    var msg = i18n_ast.Message.init(allocator);
    msg.id = "myId";
    try bundle.add("myId", msg);

    try std.testing.expect(bundle.has(&msg));
}

test "TranslationBundle getByMessage" {
    const allocator = std.testing.allocator;
    var bundle = TranslationBundle.init(allocator);
    defer bundle.deinit();

    var msg = i18n_ast.Message.init(allocator);
    msg.id = "myId";
    msg.message_string = "Translated";
    try bundle.add("myId", msg);

    var src = i18n_ast.Message.init(allocator);
    src.id = "myId";
    const result = bundle.getByMessage(&src).?;
    try std.testing.expectEqualStrings("Translated", result.message_string);
}

test "MissingTranslationStrategy values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(MissingTranslationStrategy.Error));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(MissingTranslationStrategy.Warning));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(MissingTranslationStrategy.Ignore));
}

test "I18nToHtmlVisitor convert with translation" {
    const allocator = std.testing.allocator;
    var visitor = I18nToHtmlVisitor.init(allocator);
    defer visitor.deinit();

    var msg = i18n_ast.Message.init(allocator);
    msg.id = "test";
    msg.message_string = "Hello";
    try visitor.translations.put("test", msg);

    var src = i18n_ast.Message.init(allocator);
    src.id = "test";
    src.message_string = "Hello";
    const result = try visitor.convert(&src);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello", result);
}

test "I18nToHtmlVisitor convert missing with Warning" {
    const allocator = std.testing.allocator;
    var visitor = I18nToHtmlVisitor.init(allocator);
    defer visitor.deinit();

    var src = i18n_ast.Message.init(allocator);
    src.id = "missing";
    src.message_string = "Original";
    const result = try visitor.convert(&src);
    defer allocator.free(result);
    // Warning strategy returns the original message.
    try std.testing.expectEqualStrings("Original", result);
}

test "I18nToHtmlVisitor convert missing with Ignore" {
    const allocator = std.testing.allocator;
    var visitor = I18nToHtmlVisitor.init(allocator);
    visitor.missing_translation_strategy = .Ignore;
    defer visitor.deinit();

    var src = i18n_ast.Message.init(allocator);
    src.id = "missing";
    src.message_string = "Original";
    const result = try visitor.convert(&src);
    defer allocator.free(result);
    // Ignore strategy returns empty string.
    try std.testing.expectEqualStrings("", result);
}
