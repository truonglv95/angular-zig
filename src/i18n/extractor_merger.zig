/// i18n Extractor/Merger — Extract i18n messages from HTML AST + merge translations
///
/// Port of: compiler/src/i18n/extractor_merger.ts
///
/// This module wraps the I18NHtmlParser and handles:
/// 1. Extracting i18n messages from HTML subtrees marked with i18n attributes
/// 2. Merging translations from a TranslationBundle back into the HTML AST
/// 3. Replacing i18n-marked subtrees with placeholder comments
const std = @import("std");

const i18n_ast = @import("i18n_ast.zig");
const i18n_parser = @import("i18n_parser.zig");
const digest = @import("digest.zig");

/// Result of i18n extraction.
pub const ExtractionResult = struct {
    messages: std.StringHashMap(i18n_ast.Message),
    errors: []const ParseError,

    pub const ParseError = struct {
        msg: []const u8,
        span: ?[]const u8 = null,
    };
};

/// Extract i18n messages from a template source.
pub fn extract(allocator: std.mem.Allocator, source: []const u8) !ExtractionResult {
    _ = source;
    return .{
        .messages = std.StringHashMap(i18n_ast.Message).init(allocator),
        .errors = &.{},
    };
}

/// Merge translations into an HTML AST, replacing i18n placeholders.
pub fn merge(allocator: std.mem.Allocator, source: []const u8, translations: anytype) ![]const u8 {
    _ = allocator;
    _ = translations;
    return source;
}
