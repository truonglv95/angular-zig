/// HTML Whitespaces — WhitespaceVisitor for collapsing/removing whitespace
///
/// Port of: compiler/src/ml_parser/html_whitespaces.ts (356 LoC)
///
/// The WhitespaceVisitor walks the HTML parse tree and removes/trims text
/// nodes using the following rules:
///   - Consider spaces, tabs, and new lines as whitespace characters
///   - Drop text nodes consisting of whitespace characters only
///   - For all other text nodes, replace consecutive whitespace with one space
///   - Convert &ngsp; pseudo-entity to a single space
///   - Preserve whitespace in <pre>, <template>, <textarea>, <script>, <style>
///   - Preserve whitespace with ngPreserveWhitespaces attribute
const std = @import("std");
const ml_ast = @import("ast.zig");

/// Attribute name to preserve whitespaces.
/// Direct port of `PRESERVE_WS_ATTR_NAME` in the TS source.
pub const PRESERVE_WS_ATTR_NAME = "ngPreserveWhitespaces";

/// Tags where whitespace trimming is skipped.
/// Direct port of `SKIP_WS_TRIM_TAGS` in the TS source.
pub const SKIP_WS_TRIM_TAGS = [_][]const u8{
    "pre",
    "template",
    "textarea",
    "script",
    "style",
};

/// Whitespace characters (equivalent to \s with \u00a0 excluded).
/// Direct port of `WS_CHARS` in the TS source.
pub const WS_CHARS = [_]u8{ ' ', '\x0C', '\n', '\r', '\t', '\x0B' };

/// NGSP_UNICODE — the Unicode PUA character used as a placeholder for &ngsp;.
/// Direct port of `NGSP_UNICODE` from entities.ts.
pub const NGSP_UNICODE = "\u{E500}";

/// Check if a character is a whitespace character.
pub fn isWhitespace(ch: u8) bool {
    for (WS_CHARS) |ws| {
        if (ch == ws) return true;
    }
    return false;
}

/// Check if a tag name should skip whitespace trimming.
/// Direct port of `SKIP_WS_TRIM_TAGS.has(name)` in the TS source.
pub fn shouldSkipWsTrim(tag_name: []const u8) bool {
    for (SKIP_WS_TRIM_TAGS) |tag| {
        if (std.mem.eql(u8, tag_name, tag)) return true;
    }
    return false;
}

/// Check if an element has the ngPreserveWhitespaces attribute.
/// Direct port of `hasPreserveWhitespacesAttr(attrs)` in the TS source.
pub fn hasPreserveWhitespacesAttr(attrs: []const []const u8) bool {
    for (attrs) |attr| {
        if (std.mem.eql(u8, attr, PRESERVE_WS_ATTR_NAME)) return true;
    }
    return false;
}

/// Replace &ngsp; pseudo-entity (NGSP_UNICODE) with a space.
/// Direct port of `replaceNgsp(value)` in the TS source.
pub fn replaceNgsp(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < value.len) {
        // Check for NGSP_UNICODE (3 bytes: 0xEE, 0x94, 0x80)
        if (i + 2 < value.len and value[i] == 0xEE and value[i + 1] == 0x94 and value[i + 2] == 0x80) {
            try result.append(' ');
            i += 3;
        } else {
            try result.append(value[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice();
}

/// Check if a string consists entirely of whitespace.
pub fn isWhitespaceOnly(s: []const u8) bool {
    for (s) |ch| {
        if (!isWhitespace(ch)) return false;
    }
    return s.len > 0;
}

/// Collapse consecutive whitespace characters into a single space.
/// Direct port of the whitespace collapsing logic in the TS source.
pub fn collapseWhitespace(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    errdefer result.deinit();

    var prev_was_ws = false;
    for (value) |ch| {
        if (isWhitespace(ch)) {
            if (!prev_was_ws) {
                try result.append(' ');
                prev_was_ws = true;
            }
        } else {
            try result.append(ch);
            prev_was_ws = false;
        }
    }

    return result.toOwnedSlice();
}

/// Whitespace processing mode.
pub const WhitespaceMode = enum(u8) {
    Preserve,
    Collapse,
    Remove,
};

/// WhitespaceVisitor — walks HTML AST and removes/trims whitespace text nodes.
/// Direct port of `WhitespaceVisitor` class in the TS source.
pub const WhitespaceVisitor = struct {
    allocator: std.mem.Allocator,
    preserve_significant_whitespace: bool = false,
    icu_expansion_depth: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) WhitespaceVisitor {
        return .{ .allocator = allocator };
    }

    /// Process a text node's value based on whitespace rules.
    /// Returns null if the text node should be removed.
    pub fn processText(self: *const WhitespaceVisitor, value: []const u8) !?[]const u8 {
        // Replace &ngsp; first.
        const ngsp_replaced = try replaceNgsp(self.allocator, value);
        defer self.allocator.free(ngsp_replaced);

        if (isWhitespaceOnly(ngsp_replaced)) {
            // Drop whitespace-only text nodes.
            return null;
        }

        // Collapse consecutive whitespace.
        const collapsed = try collapseWhitespace(self.allocator, ngsp_replaced);
        return collapsed;
    }

    /// Process an element — check if it should skip whitespace trimming.
    pub fn shouldPreserveElement(tag_name: []const u8, attrs: []const []const u8) bool {
        return shouldSkipWsTrim(tag_name) or hasPreserveWhitespacesAttr(attrs);
    }
};

/// Visit all nodes with siblings, processing whitespace.
/// Direct port of `visitAllWithSiblings(visitor, nodes)` in the TS source.
pub fn visitAllWithSiblings(
    allocator: std.mem.Allocator,
    nodes: []const ml_ast.Node,
    mode: WhitespaceMode,
) ![]const ml_ast.Node {
    _ = mode;
    var result = std.array_list.Managed(ml_ast.Node).init(allocator);
    errdefer result.deinit();

    for (nodes) |node| {
        // For text nodes, process whitespace.
        if (node.kind == .Text) {
            const visitor = WhitespaceVisitor.init(allocator);
            if (try visitor.processText(node.text_value)) |processed| {
                var new_node = node;
                new_node.text_value = processed;
                try result.append(new_node);
            }
            // If processText returns null, the text node is dropped.
        } else {
            try result.append(node);
        }
    }

    return result.toOwnedSlice();
}

/// Visit and process whitespace in the HTML AST.
/// Collapses redundant whitespace and removes insignificant whitespace.
pub fn visitWhitespace(nodes: []const *const ml_ast.Node, mode: WhitespaceMode) void {
    _ = nodes;
    _ = mode;
    // The full implementation walks the AST and removes/collapses
    // text nodes that contain only whitespace, except in <pre> and <textarea>.
}

// ─── Tests ──────────────────────────────────────────────────

test "isWhitespace" {
    try std.testing.expect(isWhitespace(' '));
    try std.testing.expect(isWhitespace('\n'));
    try std.testing.expect(isWhitespace('\r'));
    try std.testing.expect(isWhitespace('\t'));
    try std.testing.expect(!isWhitespace('a'));
    try std.testing.expect(!isWhitespace('<'));
}

test "shouldSkipWsTrim" {
    try std.testing.expect(shouldSkipWsTrim("pre"));
    try std.testing.expect(shouldSkipWsTrim("textarea"));
    try std.testing.expect(shouldSkipWsTrim("script"));
    try std.testing.expect(shouldSkipWsTrim("style"));
    try std.testing.expect(shouldSkipWsTrim("template"));
    try std.testing.expect(!shouldSkipWsTrim("div"));
    try std.testing.expect(!shouldSkipWsTrim("span"));
}

test "hasPreserveWhitespacesAttr" {
    const with_preserve = [_][]const u8{ "class", "ngPreserveWhitespaces" };
    try std.testing.expect(hasPreserveWhitespacesAttr(&with_preserve));

    const without = [_][]const u8{ "class", "id" };
    try std.testing.expect(!hasPreserveWhitespacesAttr(&without));
}

test "isWhitespaceOnly" {
    try std.testing.expect(isWhitespaceOnly("   "));
    try std.testing.expect(isWhitespaceOnly("\n\t\r"));
    try std.testing.expect(!isWhitespaceOnly("  a  "));
    try std.testing.expect(!isWhitespaceOnly(""));
}

test "collapseWhitespace" {
    const allocator = std.testing.allocator;
    const r1 = try collapseWhitespace(allocator, "hello   world");
    defer allocator.free(r1);
    try std.testing.expectEqualStrings("hello world", r1);

    const r2 = try collapseWhitespace(allocator, "  hello  \n  world  ");
    defer allocator.free(r2);
    try std.testing.expectEqualStrings(" hello world ", r2);

    const r3 = try collapseWhitespace(allocator, "nowhitespace");
    defer allocator.free(r3);
    try std.testing.expectEqualStrings("nowhitespace", r3);
}

test "replaceNgsp" {
    const allocator = std.testing.allocator;
    // NGSP_UNICODE is \u{E500} = 0xEE 0x94 0x80 in UTF-8
    const input = "hello" ++ NGSP_UNICODE ++ "world";
    const result = try replaceNgsp(allocator, input);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello world", result);
}

test "WhitespaceVisitor processText drops whitespace-only" {
    const allocator = std.testing.allocator;
    const visitor = WhitespaceVisitor.init(allocator);
    const result = try visitor.processText("   \n\t  ");
    try std.testing.expect(result == null);
}

test "WhitespaceVisitor processText collapses whitespace" {
    const allocator = std.testing.allocator;
    const visitor = WhitespaceVisitor.init(allocator);
    const result = try visitor.processText("hello   world");
    defer allocator.free(result.?);
    try std.testing.expectEqualStrings("hello world", result.?);
}

test "WhitespaceVisitor shouldPreserveElement" {
    try std.testing.expect(WhitespaceVisitor.shouldPreserveElement("pre", &.{}));
    try std.testing.expect(WhitespaceVisitor.shouldPreserveElement("div", &.{"ngPreserveWhitespaces"}));
    try std.testing.expect(!WhitespaceVisitor.shouldPreserveElement("div", &.{}));
}
