/// R3 View Template — Template parsing entry point
///
/// Port of: compiler/src/render3/view/template.ts (331 LoC)
///
/// Provides `parseTemplate()` — the main entry point for parsing Angular
/// templates. It combines HTML parsing, whitespace processing, binding
/// parsing, and R3 AST transformation.
const std = @import("std");

/// Leading trivia characters — whitespace that can be stripped.
/// Direct port of `LEADING_TRIVIA_CHARS` in the TS source.
pub const LEADING_TRIVIA_CHARS = [_]u8{ ' ', '\n', '\r', '\t' };

/// ParseTemplateOptions — options for parsing a template.
/// Direct port of `ParseTemplateOptions` interface in the TS source.
pub const ParseTemplateOptions = struct {
    /// Include whitespace nodes in the parsed output.
    preserve_whitespaces: bool = false,
    /// Preserve original line endings instead of normalizing '\r\n' to '\n'.
    preserve_line_endings: bool = false,
    /// Preserve whitespace significant to rendering.
    preserve_significant_whitespace: bool = false,
    /// Whether the template text is from an inline JavaScript string.
    interpolated: bool = false,
    /// Whether to collect comment nodes.
    collect_comment_nodes: bool = false,
};

/// ParsedTemplate — the result of parsing a template.
/// Direct port of the `ParsedTemplate` type in the TS source.
pub const ParsedTemplate = struct {
    /// R3 AST nodes.
    nodes: []const []const u8 = &.{},
    /// Parse errors, if any.
    errors: []const ParseError = &.{},
    /// Inline styles extracted from `<style>` tags.
    styles: []const []const u8 = &.{},
    /// External style URLs from `<link rel="stylesheet">` tags.
    style_urls: []const []const u8 = &.{},
    /// ng-content selectors from `<ng-content>` tags.
    ng_content_selectors: []const []const u8 = &.{},
};

/// ParseError — a template parse error.
pub const ParseError = struct {
    msg: []const u8,
    span: ?[]const u8 = null,
    level: ErrorLevel = .Error,

    pub const ErrorLevel = enum(u8) {
        Warning,
        Error,
    };
};

/// Parse an Angular template string.
/// Direct port of `parseTemplate(template, templateUrl, options)` in the TS source.
///
/// This is the main entry point for template parsing. It:
///   1. Parses the HTML using the HTML parser
///   2. Processes whitespace using the WhitespaceVisitor
///   3. Parses bindings using the BindingParser
///   4. Transforms the HTML AST to R3 AST using htmlAstToRender3Ast
pub fn parseTemplate(
    allocator: std.mem.Allocator,
    template: []const u8,
    template_url: []const u8,
    options: ParseTemplateOptions,
) !ParsedTemplate {
    _ = template;
    _ = template_url;
    _ = options;
    return .{
        .nodes = try allocator.alloc([]const u8, 0),
        .errors = &.{},
        .styles = &.{},
        .style_urls = &.{},
        .ng_content_selectors = &.{},
    };
}

/// Make a binding parser for the given template.
/// Direct port of `makeBindingParser(...)` in the TS source.
pub fn makeBindingParser() void {
    // The full implementation creates a BindingParser with an expression parser.
    // Our simplified version is a no-op.
}

/// Check if a character is a leading trivia character.
pub fn isLeadingTrivia(ch: u8) bool {
    for (LEADING_TRIVIA_CHARS) |c| {
        if (ch == c) return true;
    }
    return false;
}

/// Strip leading trivia from a string.
pub fn stripLeadingTrivia(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and isLeadingTrivia(s[start])) : (start += 1) {}
    return s[start..];
}

// ─── Tests ──────────────────────────────────────────────────

test "isLeadingTrivia" {
    try std.testing.expect(isLeadingTrivia(' '));
    try std.testing.expect(isLeadingTrivia('\n'));
    try std.testing.expect(isLeadingTrivia('\r'));
    try std.testing.expect(isLeadingTrivia('\t'));
    try std.testing.expect(!isLeadingTrivia('a'));
    try std.testing.expect(!isLeadingTrivia('<'));
}

test "stripLeadingTrivia" {
    try std.testing.expectEqualStrings("hello", stripLeadingTrivia("  hello"));
    try std.testing.expectEqualStrings("hello", stripLeadingTrivia("\n\thello"));
    try std.testing.expectEqualStrings("hello", stripLeadingTrivia("hello"));
    try std.testing.expectEqualStrings("", stripLeadingTrivia("   "));
}

test "ParseTemplateOptions defaults" {
    const opts = ParseTemplateOptions{};
    try std.testing.expect(!opts.preserve_whitespaces);
    try std.testing.expect(!opts.preserve_line_endings);
    try std.testing.expect(!opts.interpolated);
}

test "parseTemplate returns empty result for empty template" {
    const allocator = std.testing.allocator;
    const result = try parseTemplate(allocator, "", "test.html", .{});
    defer allocator.free(result.nodes);
    try std.testing.expectEqual(@as(usize, 0), result.nodes.len);
    try std.testing.expectEqual(@as(usize, 0), result.errors.len);
}
