/// HTML Tokenizer — Interpolation-aware HTML lexer
///
/// Key differences from expression lexer:
///   - Tracks {{ }} boundaries in text and attribute values
///   - Produces structured tokens for HTML constructs
///   - Zero-copy: tokens reference source string offsets
///
/// DOD: Linear scan with branchless character classification
const std = @import("std");
const chars = @import("../chars.zig");
const tags = @import("tags.zig");

pub const HtmlTokenType = enum(u8) {
    TagOpenStart, // <
    TagOpenEnd, // > or />
    TagCloseStart, // </
    TagName, // element name after < or </
    AttributeName,
    AttributeValue,
    Text,
    Comment, // <!-- -->
    DocType, // <!DOCTYPE>
    Cdata, // <![CDATA[...]]>
    ExpansionFormStart, // { (i18n plural/select)
    ExpansionCaseStart, // }
    EOF,
};

/// Token part — boundary info for interpolated content
pub const TokenPart = struct {
    start: u32,
    end: u32,
    is_expression: bool, // true = {{ expr }}, false = plain text
};

/// HTML Token — zero-copy reference into source
pub const HtmlToken = struct {
    type: HtmlTokenType,
    index: u32,
    end: u32,
    /// For text/attr tokens with interpolations
    parts: []const TokenPart = &[_]TokenPart{},
    /// Was the tag self-closing? (only for TagOpenEnd)
    self_closing: bool = false,

    pub fn slice(self: HtmlToken, source: []const u8) []const u8 {
        return source[self.index..self.end];
    }
};

/// Interpolation boundary tracker — finds {{ }} in text
fn trackInterpolations(source: []const u8, start: u32, end: u32, allocator: std.mem.Allocator) ![]const TokenPart {
    var parts = std.array_list.Managed(TokenPart).init(allocator);
    defer parts.deinit();

    var i = start;
    var text_start = start;

    while (i < end) : (i += 1) {
        // Check for {{
        if (i + 1 < end and source[i] == '{' and source[i + 1] == '{') {
            // Emit preceding text
            if (i > text_start) {
                try parts.append(.{ .start = text_start, .end = i, .is_expression = false });
            }
            // Find matching }}
            var depth: u32 = 1;
            var j = i + 2;
            while (j < end and depth > 0) : (j += 1) {
                if (j + 1 < end and source[j] == '{' and source[j + 1] == '{') {
                    depth += 1;
                    j += 1;
                } else if (j + 1 < end and source[j] == '}' and source[j + 1] == '}') {
                    depth -= 1;
                    j += 1;
                }
            }
            try parts.append(.{ .start = i + 2, .end = j - 1, .is_expression = true });
            text_start = j + 1;
            i = j;
        }
    }

    // Remaining text
    if (text_start < end) {
        try parts.append(.{ .start = text_start, .end = end, .is_expression = false });
    }

    return parts.toOwnedSlice();
}

/// HTML Lexer
pub const Lexer = struct {
    source: []const u8,
    pos: u32 = 0,
    tokens: std.array_list.Managed(HtmlToken),
    errors: std.array_list.Managed(LexError),

    pub const LexError = struct {
        index: u32,
        message: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Lexer {
        return .{
            .source = source,
            .tokens = std.array_list.Managed(HtmlToken).init(allocator),
            .errors = std.array_list.Managed(LexError).init(allocator),
        };
    }

    pub fn deinit(self: *Lexer) void {
        // Free interpolation parts stored inside tokens
        const allocator = self.tokens.allocator;
        for (self.tokens.items) |tok| {
            if (tok.parts.len > 0) {
                allocator.free(tok.parts);
            }
        }
        self.tokens.deinit();
        self.errors.deinit();
    }

    pub fn tokenize(self: *Lexer) !struct { []const HtmlToken, []const LexError } {
        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];

            if (ch == '<') {
                try self.handleTagStart();
            } else {
                try self.scanText();
            }
        }

        try self.tokens.append(.{
            .type = .EOF,
            .index = self.pos,
            .end = self.pos,
        });

        return .{ self.tokens.items, self.errors.items };
    }

    // ─── Tag Handling ─────────────────────────────────────────

    fn handleTagStart(self: *Lexer) !void {
        const start = self.pos;

        // Comment: <!--
        if (self.startsWith("<!--")) {
            try self.scanComment();
            return;
        }

        // DocType: <!DOCTYPE
        if (self.startsWithIgnoreCase("<!doctype")) {
            try self.scanDocType();
            return;
        }

        // CDATA: <![CDATA[
        if (self.startsWith("<![CDATA[")) {
            try self.scanCdata();
            return;
        }

        // Closing tag: </
        if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '/') {
            self.pos += 2;
            try self.tokens.append(.{ .type = .TagCloseStart, .index = start, .end = self.pos });
            try self.scanTagName();
            try self.scanTagEnd();
            return;
        }

        // Opening tag: <
        self.pos += 1;
        try self.tokens.append(.{ .type = .TagOpenStart, .index = start, .end = self.pos });
        try self.scanTagName();
        try self.scanAttributes();
        try self.scanTagEnd();
    }

    fn scanTagName(self: *Lexer) !void {
        const start = self.pos;
        while (self.pos < self.source.len and chars.isTagNameChar(self.source[self.pos])) {
            self.pos += 1;
        }
        if (self.pos > start) {
            try self.tokens.append(.{
                .type = .TagName,
                .index = start,
                .end = self.pos,
            });
        }
    }

    fn scanAttributes(self: *Lexer) !void {
        while (self.pos < self.source.len) {
            self.skipWhitespace();
            if (self.pos >= self.source.len) break;

            const ch = self.source[self.pos];
            // End of tag
            if (ch == '>' or (ch == '/' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '>')) {
                break;
            }

            // Attribute name
            if (chars.isIdentifierStart(ch) or ch == '@' or ch == '[' or ch == '(' or ch == '*') {
                try self.scanAttribute();
            } else {
                self.pos += 1; // skip unexpected character
            }
        }
    }

    fn scanAttribute(self: *Lexer) !void {
        const name_start = self.pos;

        // Scan attribute name (including Angular binding syntax like [prop], (event), [(twoWay)])
        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (chars.isWhitespace(ch) or ch == '=' or ch == '>' or ch == '/') break;
            self.pos += 1;
        }

        try self.tokens.append(.{
            .type = .AttributeName,
            .index = name_start,
            .end = self.pos,
        });

        self.skipWhitespace();

        // Check for =value
        if (self.pos < self.source.len and self.source[self.pos] == '=') {
            self.pos += 1; // skip =
            self.skipWhitespace();
            try self.scanAttributeValue();
        }
    }

    fn scanAttributeValue(self: *Lexer) !void {
        const allocator = self.tokens.allocator;
        const start = self.pos;

        if (self.pos >= self.source.len) return;

        const quote = self.source[self.pos];
        if (quote != '\'' and quote != '"') {
            // Unquoted attribute value
            while (self.pos < self.source.len) {
                const ch = self.source[self.pos];
                if (chars.isWhitespace(ch) or ch == '>' or ch == '/') break;
                self.pos += 1;
            }
            try self.tokens.append(.{
                .type = .AttributeValue,
                .index = start,
                .end = self.pos,
            });
            return;
        }

        // Quoted attribute value
        self.pos += 1; // skip opening quote
        const value_start = self.pos;

        while (self.pos < self.source.len and self.source[self.pos] != quote) {
            if (self.source[self.pos] == '\\') {
                self.pos += 2; // skip escape
            } else {
                self.pos += 1;
            }
        }
        const value_end = self.pos;

        if (self.pos < self.source.len) {
            self.pos += 1; // skip closing quote
        }

        // Track interpolations in attribute value
        const parts = trackInterpolations(self.source, value_start, value_end, allocator) catch &[_]TokenPart{};

        try self.tokens.append(.{
            .type = .AttributeValue,
            .index = start,
            .end = self.pos,
            .parts = parts,
        });
    }

    fn scanTagEnd(self: *Lexer) !void {
        const start = self.pos;
        if (self.pos >= self.source.len) return;

        const self_closing = if (self.source[self.pos] == '/') blk: {
            self.pos += 1;
            break :blk true;
        } else false;

        if (self.pos < self.source.len and self.source[self.pos] == '>') {
            self.pos += 1;
        }

        try self.tokens.append(.{
            .type = .TagOpenEnd,
            .index = start,
            .end = self.pos,
            .self_closing = self_closing,
        });
    }

    // ─── Text Scanning ────────────────────────────────────────

    fn scanText(self: *Lexer) !void {
        const allocator = self.tokens.allocator;
        const start = self.pos;

        while (self.pos < self.source.len and self.source[self.pos] != '<') {
            self.pos += 1;
        }

        const end = self.pos;
        if (end == start) return;

        // Track interpolations
        const parts = trackInterpolations(self.source, start, end, allocator) catch &[_]TokenPart{};

        try self.tokens.append(.{
            .type = .Text,
            .index = start,
            .end = end,
            .parts = parts,
        });
    }

    // ─── Special Constructs ───────────────────────────────────

    fn scanComment(self: *Lexer) !void {
        const start = self.pos;
        self.pos += 4; // skip <!--

        while (self.pos < self.source.len) {
            if (self.startsWith("-->")) {
                self.pos += 3;
                break;
            }
            self.pos += 1;
        }

        try self.tokens.append(.{
            .type = .Comment,
            .index = start,
            .end = self.pos,
        });
    }

    fn scanDocType(self: *Lexer) !void {
        const start = self.pos;

        while (self.pos < self.source.len and self.source[self.pos] != '>') {
            self.pos += 1;
        }
        if (self.pos < self.source.len) self.pos += 1;

        try self.tokens.append(.{
            .type = .DocType,
            .index = start,
            .end = self.pos,
        });
    }

    fn scanCdata(self: *Lexer) !void {
        const start = self.pos;
        self.pos += 9; // skip <![CDATA[

        while (self.pos < self.source.len) {
            if (self.startsWith("]]>")) {
                self.pos += 3;
                break;
            }
            self.pos += 1;
        }

        try self.tokens.append(.{
            .type = .Cdata,
            .index = start,
            .end = self.pos,
        });
    }

    // ─── Helpers ──────────────────────────────────────────────

    fn startsWith(self: *const Lexer, prefix: []const u8) bool {
        if (self.pos + prefix.len > self.source.len) return false;
        return std.mem.eql(u8, self.source[self.pos .. self.pos + prefix.len], prefix);
    }

    fn startsWithIgnoreCase(self: *const Lexer, prefix: []const u8) bool {
        if (self.pos + prefix.len > self.source.len) return false;
        return std.ascii.eqlIgnoreCase(self.source[self.pos .. self.pos + prefix.len], prefix);
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.pos < self.source.len and chars.isWhitespace(self.source[self.pos])) {
            self.pos += 1;
        }
    }
};

// ─── Tests ────────────────────────────────────────────────────

test "tokenize simple HTML" {
    const allocator = std.testing.allocator;
    const source = "<div>Hello</div>";
    var lex = Lexer.init(allocator, source);
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

    // <, div, >, Text("Hello"), </, div, >, EOF
    try std.testing.expect(tokens.len >= 7);
    try std.testing.expectEqual(HtmlTokenType.TagOpenStart, tokens[0].type);
    try std.testing.expectEqual(HtmlTokenType.TagName, tokens[1].type);
    try std.testing.expectEqualStrings("div", tokens[1].slice(source));
    try std.testing.expectEqual(HtmlTokenType.TagOpenEnd, tokens[2].type);
    try std.testing.expectEqual(HtmlTokenType.Text, tokens[3].type);
    try std.testing.expectEqualStrings("Hello", tokens[3].slice(source));
}

test "tokenize with attributes" {
    const allocator = std.testing.allocator;
    const source = "<input type=\"text\" [value]=\"name\">";
    var lex = Lexer.init(allocator, source);
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

    // Should have: <, input, type, =, "text", [value], =, "name", >, EOF
    var attr_count: usize = 0;
    for (tokens) |tok| {
        if (tok.type == .AttributeName) attr_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), attr_count);
}

test "tokenize self-closing" {
    const allocator = std.testing.allocator;
    const source = "<br/>";
    var lex = Lexer.init(allocator, source);
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

    // Find TagOpenEnd
    for (tokens) |tok| {
        if (tok.type == .TagOpenEnd) {
            try std.testing.expect(tok.self_closing);
        }
    }
}

test "tokenize interpolation in text" {
    const allocator = std.testing.allocator;
    const source = "<span>{{ name }}</span>";
    var lex = Lexer.init(allocator, source);
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

    // Find Text token with interpolation parts
    for (tokens) |tok| {
        if (tok.type == .Text and tok.parts.len > 0) {
            // {{ name }} has no surrounding text, so only 1 part (the expression)
            try std.testing.expectEqual(@as(usize, 1), tok.parts.len);
            try std.testing.expect(tok.parts[0].is_expression);
        }
    }
}
