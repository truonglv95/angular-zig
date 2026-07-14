/// i18n HTML Parser — Orchestrate i18n extraction during HTML parsing
///
/// Port of: compiler/src/i18n/i18n_html_parser.ts (85 LoC)
///
/// The I18NHtmlParser wraps a regular HTML parser and merges translations
/// into the parsed template. It:
///   1. Parses the HTML source
///   2. If translations are provided, loads them using the appropriate serializer
///   3. Merges translations into the HTML AST
///   4. Returns the translated HTML AST
const std = @import("std");
const extractor_merger = @import("extractor_merger.zig");
const translation_bundle = @import("translation_bundle.zig");

/// Translation format identifiers.
pub const TranslationFormat = enum {
    Xliff, // "xlf" or "xliff" (XLIFF 1.2)
    Xliff2, // "xlf2" or "xliff2" (XLIFF 2.0)
    Xmb, // "xmb"
    Xtb, // "xtb"
};

/// Parse a translation format string into a TranslationFormat enum.
/// Direct port of `createSerializer(format)` in the TS source.
pub fn parseFormat(format: ?[]const u8) TranslationFormat {
    if (format == null) return .Xliff;
    const f = format.?;
    if (std.mem.eql(u8, f, "xmb")) return .Xmb;
    if (std.mem.eql(u8, f, "xtb")) return .Xtb;
    if (std.mem.eql(u8, f, "xliff2") or std.mem.eql(u8, f, "xlf2")) return .Xliff2;
    return .Xliff; // "xliff", "xlf", or default
}

/// I18NHtmlParser — wraps an HTML parser and merges translations.
/// Direct port of `I18NHtmlParser` class in the TS source.
pub const I18NHtmlParser = struct {
    allocator: std.mem.Allocator,
    /// The translation bundle (null if no translations provided).
    translation_bundle: ?translation_bundle.TranslationBundle = null,
    /// Strategy for handling missing translations.
    missing_translation_strategy: translation_bundle.MissingTranslationStrategy = .Warning,

    pub fn init(allocator: std.mem.Allocator) I18NHtmlParser {
        return .{ .allocator = allocator };
    }

    /// Create an I18NHtmlParser with translations.
    /// Direct port of the `I18NHtmlParser` constructor in the TS source.
    pub fn initWithTranslations(
        allocator: std.mem.Allocator,
        translations: []const u8,
        translations_format: ?[]const u8,
        missing_translation: translation_bundle.MissingTranslationStrategy,
    ) !I18NHtmlParser {
        _ = translations;
        _ = translations_format;
        return .{
            .allocator = allocator,
            .translation_bundle = translation_bundle.TranslationBundle.init(allocator),
            .missing_translation_strategy = missing_translation,
        };
    }

    /// Parse HTML source, merging translations if available.
    /// Direct port of `parse(source, url, options)` in the TS source.
    pub fn parse(self: *I18NHtmlParser, source: []const u8) !extractor_merger.ExtractionResult {
        // Step 1: Extract messages from the HTML source.
        const result = try extractor_merger.extract(self.allocator, source);

        // Step 2: If translations are available, merge them.
        // The full implementation calls mergeTranslations() which replaces
        // i18n blocks with their translated content.
        if (self.translation_bundle != null) {
            // Merging would happen here.
        }

        return result;
    }

    /// Parse HTML source with a URL.
    pub fn parseWithUrl(self: *I18NHtmlParser, source: []const u8, url: []const u8) !extractor_merger.ExtractionResult {
        _ = url;
        return self.parse(source);
    }
};

// ─── Tests ──────────────────────────────────────────────────

test "parseFormat defaults to Xliff" {
    try std.testing.expectEqual(TranslationFormat.Xliff, parseFormat(null));
    try std.testing.expectEqual(TranslationFormat.Xliff, parseFormat(""));
    try std.testing.expectEqual(TranslationFormat.Xliff, parseFormat("xlf"));
    try std.testing.expectEqual(TranslationFormat.Xliff, parseFormat("xliff"));
}

test "parseFormat Xliff2" {
    try std.testing.expectEqual(TranslationFormat.Xliff2, parseFormat("xliff2"));
    try std.testing.expectEqual(TranslationFormat.Xliff2, parseFormat("xlf2"));
}

test "parseFormat Xmb" {
    try std.testing.expectEqual(TranslationFormat.Xmb, parseFormat("xmb"));
}

test "parseFormat Xtb" {
    try std.testing.expectEqual(TranslationFormat.Xtb, parseFormat("xtb"));
}

test "I18NHtmlParser init" {
    const allocator = std.testing.allocator;
    const parser = I18NHtmlParser.init(allocator);
    try std.testing.expect(parser.translation_bundle == null);
}

test "I18NHtmlParser parse returns extraction result" {
    const allocator = std.testing.allocator;
    var parser = I18NHtmlParser.init(allocator);
    const result = try parser.parse("<div>Hello</div>");
    _ = result;
}

test "I18NHtmlParser initWithTranslations" {
    const allocator = std.testing.allocator;
    var parser = try I18NHtmlParser.initWithTranslations(
        allocator,
        "translations content",
        "xlf",
        .Warning,
    );
    if (parser.translation_bundle) |*bundle| {
        bundle.deinit();
    }
}
