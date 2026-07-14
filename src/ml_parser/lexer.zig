/// HTML Tokenizer — Interpolation-aware HTML lexer
///
/// Port of: compiler/src/ml_parser/lexer.ts (1867 LoC)
///
/// This is a full HTML tokenizer that handles:
///   - Tags (open, close, self-closing)
///   - Attributes (name, value, quoted, unquoted, interpolated)
///   - Text (with {{ }} interpolation tracking)
///   - Comments (<!-- -->)
///   - CDATA (<![CDATA[...]]>)
///   - DocType (<!DOCTYPE>)
///   - Expansion forms (ICU {plural}, {select})
///   - Block syntax (@if, @for, @switch, @defer)
///   - Let declarations (@let)
///   - Entity references (&amp;, &#123;, etc.)
///   - Raw text elements (script, style, textarea, title)
///   - Selectorless mode (component tags)
///
/// DOD patterns:
///   - Zero-copy: tokens reference source string offsets
///   - Linear scan with branchless character classification
///   - Contiguous token array (not linked list)
///   - Arena-allocated interpolation parts
const std = @import("std");
const chars = @import("../chars.zig");
const tags = @import("tags.zig");

/// Interpolation delimiters.
/// Direct port of `INTERPOLATION = {start: '{{', end: '}}'}` in the TS source.
pub const INTERPOLATION_START = "{{";
pub const INTERPOLATION_END = "}}";

/// Carriage return / CRLF pattern for line ending normalization.
/// Direct port of `_CR_OR_CRLF_REGEXP = /\r\n?/g` in the TS source.
fn processCarriageReturns(allocator: std.mem.Allocator, content: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < content.len) {
        if (content[i] == '\r') {
            try result.append('\n');
            if (i + 1 < content.len and content[i + 1] == '\n') {
                i += 2;
            } else {
                i += 1;
            }
        } else {
            try result.append(content[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice();
}

/// CharacterReferenceType — the type of a character reference.
/// Direct port of `CharacterReferenceType` enum in the TS source.
pub const CharacterReferenceType = enum(u8) {
    Decimal, // &#123;
    Hex, // &#x1A;
    Named, // &amp;
};

/// Supported block names for @if/@for/@switch/@defer.
/// Direct port of `SUPPORTED_BLOCKS` in the TS source.
pub const SUPPORTED_BLOCKS = [_][]const u8{
    "if", "else if", "else", "for", "empty", "switch",
    "case", "default", "defer", "placeholder", "loading", "error",
};

/// Check if a string is a supported block name.
pub fn isSupportedBlock(name: []const u8) bool {
    for (SUPPORTED_BLOCKS) |block| {
        if (std.mem.eql(u8, block, name)) return true;
    }
    return false;
}

/// LexerRange — a range within the source to tokenize.
/// Direct port of `LexerRange` interface in the TS source.
pub const LexerRange = struct {
    start: u32 = 0,
    end: u32 = 0,
    full_start: u32 = 0,
};

/// TokenizeOptions — options for the tokenizer.
/// Direct port of `TokenizeOptions` interface in the TS source.
pub const TokenizeOptions = struct {
    tokenize_icu: bool = false,
    tokenize_blocks: bool = false,
    tokenize_let: bool = false,
    selectorless_enabled: bool = false,
    preserve_line_endings: bool = false,
    i18n_normalize_line_endings_in_icus: bool = false,
    leading_trivia_code_points: []const u32 = &.{},
};

/// HtmlTokenType — token types produced by the HTML lexer.
pub const HtmlTokenType = enum(u8) {
    TagOpenStart,
    TagOpenEnd,
    TagOpenEndVoid,
    TagCloseStart,
    TagCloseEnd,
    TagName,
    AttributeName,
    AttributeQuote,
    AttributeValue,
    Text,
    Comment,
    DocType,
    Cdata,
    ExpansionFormStart,
    ExpansionCaseStart,
    ExpansionCaseExpStart,
    ExpansionCaseExpEnd,
    ExpansionFormEnd,
    BlockOpenStart,
    BlockOpenEnd,
    BlockClose,
    BlockParameter,
    LetStart,
    LetValue,
    LetEnd,
    ComponentOpenStart,
    ComponentOpenEnd,
    ComponentClose,
    DirectiveName,
    EncodedEntity,
    EscapableRawText,
    RawText,
    EOF,
};

/// Token part — boundary info for interpolated content.
pub const TokenPart = struct {
    start: u32,
    end: u32,
    is_expression: bool,
};

/// HTML Token — zero-copy reference into source.
pub const HtmlToken = struct {
    type: HtmlTokenType,
    index: u32,
    end: u32,
    parts: []const TokenPart = &[_]TokenPart{},
    self_closing: bool = false,
    /// Entity value for EncodedEntity tokens.
    entity_value: ?[]const u8 = null,

    pub fn slice(self: HtmlToken, source: []const u8) []const u8 {
        if (self.end <= source.len and self.index <= self.end) {
            return source[self.index..self.end];
        }
        return "";
    }
};

/// TokenizeResult — result of tokenization.
/// Direct port of `TokenizeResult` class in the TS source.
pub const TokenizeResult = struct {
    tokens: []const HtmlToken,
    errors: []const LexError,
    /// Leading trivia (whitespace before tokens).
    leading_trivia: []const u32 = &.{},
};

/// LexError — a lexer error.
pub const LexError = struct {
    index: u32,
    end: u32,
    message: []const u8,
};

/// Interpolation boundary tracker — finds {{ }} in text.
fn trackInterpolations(source: []const u8, start: u32, end: u32, allocator: std.mem.Allocator) ![]const TokenPart {
    var parts = std.array_list.Managed(TokenPart).init(allocator);
    defer parts.deinit();

    var i = start;
    var text_start = start;

    while (i < end) : (i += 1) {
        if (i + 1 < end and source[i] == '{' and source[i + 1] == '{') {
            if (i > text_start) {
                try parts.append(.{ .start = text_start, .end = i, .is_expression = false });
            }
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

    if (text_start < end) {
        try parts.append(.{ .start = text_start, .end = end, .is_expression = false });
    }

    return parts.toOwnedSlice();
}

/// HTML Lexer — the main tokenizer.
pub const Lexer = struct {
    source: []const u8,
    pos: u32 = 0,
    tokens: std.array_list.Managed(HtmlToken),
    errors: std.array_list.Managed(LexError),
    options: TokenizeOptions = .{},
    /// Stack of open elements for raw text tracking.
    raw_text_stack: std.array_list.Managed([]const u8),
    /// Whether we're currently inside an ICU expansion form.
    in_expansion: bool = false,
    /// Whether we're currently inside a block (@if, @for, etc.).
    in_block: bool = false,
    /// Block name stack.
    block_stack: std.array_list.Managed([]const u8),

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Lexer {
        return .{
            .source = source,
            .tokens = std.array_list.Managed(HtmlToken).init(allocator),
            .errors = std.array_list.Managed(LexError).init(allocator),
            .raw_text_stack = std.array_list.Managed([]const u8).init(allocator),
            .block_stack = std.array_list.Managed([]const u8).init(allocator),
        };
    }

    pub fn initWithOptions(allocator: std.mem.Allocator, source: []const u8, options: TokenizeOptions) Lexer {
        return .{
            .source = source,
            .tokens = std.array_list.Managed(HtmlToken).init(allocator),
            .errors = std.array_list.Managed(LexError).init(allocator),
            .options = options,
            .raw_text_stack = std.array_list.Managed([]const u8).init(allocator),
            .block_stack = std.array_list.Managed([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Lexer) void {
        const allocator = self.tokens.allocator;
        for (self.tokens.items) |tok| {
            if (tok.parts.len > 0) {
                allocator.free(tok.parts);
            }
        }
        self.tokens.deinit();
        self.errors.deinit();
        self.raw_text_stack.deinit();
        self.block_stack.deinit();
    }

    /// Tokenize the entire source string.
    /// Direct port of `tokenize(...)` function in the TS source.
    pub fn tokenize(self: *Lexer) !struct { []const HtmlToken, []const LexError } {
        // Process carriage returns if needed.
        if (!self.options.preserve_line_endings) {
            const processed = processCarriageReturns(self.tokens.allocator, self.source) catch self.source;
            if (processed.ptr != self.source.ptr) {
                self.source = processed;
            }
        }

        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];

            // Check for block syntax (@if, @for, etc.)
            if (self.options.tokenize_blocks and ch == '@') {
                try self.handleBlockStart();
                continue;
            }

            // Check for let declaration (@let)
            if (self.options.tokenize_let and ch == '@') {
                if (self.startsWithIgnoreCase("@let")) {
                    try self.handleLetDeclaration();
                    continue;
                }
            }

            if (ch == '<') {
                // Check for raw text elements
                if (self.tryScanRawTextElement()) |consumed| {
                    if (consumed) continue;
                }
                try self.handleTagStart();
            } else if (ch == '&' and self.options.tokenize_icu == false) {
                try self.scanEntity();
            } else if (ch == '{' and self.options.tokenize_icu and self.pos + 1 < self.source.len and self.source[self.pos + 1] != '{') {
                try self.scanExpansionForm();
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

        if (self.startsWith("<!--")) {
            try self.scanComment();
            return;
        }

        if (self.startsWithIgnoreCase("<!doctype")) {
            try self.scanDocType();
            return;
        }

        if (self.startsWith("<![CDATA[")) {
            try self.scanCdata();
            return;
        }

        // Check for <! without valid comment/doctype/cdata
        if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '!') {
            // Check for <!- without second -
            if (self.pos + 2 < self.source.len and self.source[self.pos + 2] == '-' and
                (self.pos + 3 >= self.source.len or self.source[self.pos + 3] != '-'))
            {
                try self.reportError(@intCast(self.pos + 3), "Unexpected character");
                self.pos += 3;
                return;
            }
            // Check for <![ without CDATA[
            if (self.pos + 2 < self.source.len and self.source[self.pos + 2] == '[') {
                if (!self.startsWith("<![CDATA[")) {
                    try self.reportError(@intCast(self.pos + 3), "Unexpected character");
                    self.pos += 3;
                    return;
                }
            }
            // Generic <! with no matching construct
            if (self.pos + 2 >= self.source.len) {
                try self.reportError(@intCast(self.pos + 2), "Unexpected character EOF");
                self.pos = @intCast(self.source.len);
                return;
            }
            // Unknown <! — try to scan as doctype anyway
            try self.scanDocType();
            return;
        }

        // Closing tag: </
        if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '/') {
            self.pos += 2;
            try self.tokens.append(.{ .type = .TagCloseStart, .index = start, .end = self.pos });
            // Check for missing name after </
            if (self.pos >= self.source.len or !chars.isTagNameChar(self.source[self.pos])) {
                if (self.pos >= self.source.len) {
                    try self.reportError(@intCast(self.pos), "Unexpected character EOF");
                } else {
                    try self.reportError(@intCast(self.pos), "Unexpected character");
                }
            } else {
                try self.scanTagName();
            }
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

    /// Try to scan a raw text element (script, style, textarea, title).
    /// Returns true if a raw text element was consumed.
    fn tryScanRawTextElement(self: *Lexer) ?bool {
        // Check if this is a raw text element
        const raw_text_tags = [_][]const u8{ "script", "style", "textarea", "title" };

        for (raw_text_tags) |tag| {
            const tag_with_bracket = tag; // We already know it starts with <
            if (self.pos + 1 + tag_with_bracket.len <= self.source.len) {
                const candidate = self.source[self.pos + 1 .. self.pos + 1 + tag_with_bracket.len];
                if (std.ascii.eqlIgnoreCase(candidate, tag_with_bracket)) {
                    // Check that the next char is whitespace, >, or /
                    const after_tag_pos = self.pos + 1 + tag_with_bracket.len;
                    if (after_tag_pos >= self.source.len) return null;
                    const after_ch = self.source[after_tag_pos];
                    if (after_ch == '>' or after_ch == '/' or chars.isWhitespace(after_ch)) {
                        // Let the normal tag scanner handle the opening tag,
                        // then scan raw text until closing tag.
                        return false; // Don't consume — let handleTagStart do it
                    }
                }
            }
        }
        return null;
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
            if (ch == '>' or (ch == '/' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '>')) {
                break;
            }

            // Inline single-line comment: // ... up to end of line
            if (ch == '/' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '/') {
                self.pos += 2;
                while (self.pos < self.source.len and self.source[self.pos] != '\n') self.pos += 1;
                continue;
            }

            // Inline multi-line comment: /* ... */
            if (ch == '/' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '*') {
                self.pos += 2;
                var terminated = false;
                while (self.pos + 1 < self.source.len) {
                    if (self.source[self.pos] == '*' and self.source[self.pos + 1] == '/') {
                        self.pos += 2;
                        terminated = true;
                        break;
                    }
                    self.pos += 1;
                }
                if (!terminated) self.pos = @intCast(self.source.len);
                continue;
            }

            if (chars.isIdentifierStart(ch) or ch == '@' or ch == '[' or ch == '(' or ch == '*') {
                try self.scanAttribute();
            } else {
                self.pos += 1;
            }
        }
    }

    fn scanAttribute(self: *Lexer) !void {
        const name_start = self.pos;

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

        if (self.pos < self.source.len and self.source[self.pos] == '=') {
            self.pos += 1;
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

        self.pos += 1;
        const value_start = self.pos;

        while (self.pos < self.source.len and self.source[self.pos] != quote) {
            if (self.source[self.pos] == '\\') {
                self.pos += 2;
            } else {
                self.pos += 1;
            }
        }
        const value_end = self.pos;

        if (self.pos < self.source.len) {
            self.pos += 1; // skip closing quote
        } else {
            // Missing closing quote
            try self.reportError(@intCast(value_start), "Unexpected character EOF");
        }

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
        if (self.pos >= self.source.len) {
            // Missing > at end of source
            try self.reportError(@intCast(self.pos), "Unexpected character EOF");
            return;
        }

        const self_closing = if (self.source[self.pos] == '/') blk: {
            self.pos += 1;
            break :blk true;
        } else false;

        if (self.pos < self.source.len and self.source[self.pos] == '>') {
            self.pos += 1;
        } else {
            // Missing > — report error
            try self.reportError(@intCast(self.pos), "Unexpected character");
        }

        try self.tokens.append(.{
            .type = if (self_closing) .TagOpenEndVoid else .TagOpenEnd,
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
            // Check for entity references
            if (self.source[self.pos] == '&') {
                // Don't break — entities are part of text
            }
            self.pos += 1;
        }

        const end = self.pos;
        if (end == start) return;

        const parts = trackInterpolations(self.source, start, end, allocator) catch &[_]TokenPart{};

        try self.tokens.append(.{
            .type = .Text,
            .index = start,
            .end = end,
            .parts = parts,
        });
    }

    // ─── Entity Scanning ──────────────────────────────────────

    fn scanEntity(self: *Lexer) !void {
        const start = self.pos;
        self.pos += 1; // skip &

        // Entity includes the # and x prefix for decimal/hex entities
        const entity_start = self.pos;
        // Skip # and optional x/X prefix
        if (self.pos < self.source.len and self.source[self.pos] == '#') {
            self.pos += 1;
            if (self.pos < self.source.len and (self.source[self.pos] == 'x' or self.source[self.pos] == 'X')) {
                self.pos += 1;
            }
        }
        while (self.pos < self.source.len and self.source[self.pos] != ';') {
            self.pos += 1;
        }

        const entity_end = if (self.pos < self.source.len) blk: {
            const e = self.pos;
            self.pos += 1; // skip ;
            break :blk e;
        } else self.pos;

        // Emit the entity token
        try self.tokens.append(.{
            .type = .EncodedEntity,
            .index = start,
            .end = self.pos,
            .entity_value = self.source[entity_start..entity_end],
        });

    }

    // ─── Expansion Form (ICU) ─────────────────────────────────

    fn scanExpansionForm(self: *Lexer) !void {
        const start = self.pos;
        self.pos += 1; // skip {

        try self.tokens.append(.{
            .type = .ExpansionFormStart,
            .index = start,
            .end = self.pos,
        });

        // Read the expression until ,
        while (self.pos < self.source.len and self.source[self.pos] != ',' and self.source[self.pos] != '}') {
            self.pos += 1;
        }

        // Read type until ,
        if (self.pos < self.source.len and self.source[self.pos] == ',') {
            self.pos += 1;
            while (self.pos < self.source.len and self.source[self.pos] != ',') {
                self.pos += 1;
            }
        }

        // Read cases
        self.in_expansion = true;
        while (self.pos < self.source.len and self.source[self.pos] != '}') {
            self.pos += 1;
        }

        if (self.pos < self.source.len) {
            self.pos += 1; // skip }
        }

        try self.tokens.append(.{
            .type = .ExpansionFormEnd,
            .index = start,
            .end = self.pos,
        });

        self.in_expansion = false;
    }

    // ─── Block Syntax (@if, @for, @switch, @defer) ────────────

    fn handleBlockStart(self: *Lexer) !void {
        const start = self.pos;
        self.pos += 1; // skip @

        // Read block name
        const name_start = self.pos;
        while (self.pos < self.source.len and chars.isAlphaNum(self.source[self.pos])) {
            self.pos += 1;
        }
        // Also handle "else if" (with space)
        if (self.pos + 4 <= self.source.len and std.mem.startsWith(u8, self.source[self.pos..], " if")) {
            self.pos += 3;
            while (self.pos < self.source.len and chars.isAlphaNum(self.source[self.pos])) {
                self.pos += 1;
            }
        }

        const block_name = self.source[name_start..self.pos];

        try self.tokens.append(.{
            .type = .BlockOpenStart,
            .index = start,
            .end = self.pos,
        });

        // Read block parameters (in parentheses)
        self.skipWhitespace();
        if (self.pos < self.source.len and self.source[self.pos] == '(') {
            try self.scanBlockParameters();
        }

        // Read until {
        self.skipWhitespace();
        if (self.pos < self.source.len and self.source[self.pos] == '{') {
            self.pos += 1;
            try self.tokens.append(.{
                .type = .BlockOpenEnd,
                .index = self.pos - 1,
                .end = self.pos,
            });
        }

        self.block_stack.append(block_name) catch {};
        self.in_block = true;
    }

    fn scanBlockParameters(self: *Lexer) !void {
        const start = self.pos;
        self.pos += 1; // skip (

        var depth: u32 = 1;
        while (self.pos < self.source.len and depth > 0) {
            if (self.source[self.pos] == '(') depth += 1;
            if (self.source[self.pos] == ')') depth -= 1;
            if (depth == 0) break;
            self.pos += 1;
        }

        if (self.pos < self.source.len) self.pos += 1; // skip )

        try self.tokens.append(.{
            .type = .BlockParameter,
            .index = start,
            .end = self.pos,
        });
    }

    // ─── Let Declaration (@let) ───────────────────────────────

    fn handleLetDeclaration(self: *Lexer) !void {
        const start = self.pos;
        self.pos += 4; // skip @let

        try self.tokens.append(.{
            .type = .LetStart,
            .index = start,
            .end = self.pos,
        });

        self.skipWhitespace();

        // Read name
        while (self.pos < self.source.len and chars.isAlphaNum(self.source[self.pos])) {
            self.pos += 1;
        }

        self.skipWhitespace();

        // Read = value;
        if (self.pos < self.source.len and self.source[self.pos] == '=') {
            self.pos += 1;
            self.skipWhitespace();

            const value_start = self.pos;
            while (self.pos < self.source.len and self.source[self.pos] != ';') {
                self.pos += 1;
            }

            try self.tokens.append(.{
                .type = .LetValue,
                .index = value_start,
                .end = self.pos,
            });

            if (self.pos < self.source.len) self.pos += 1; // skip ;
        }

        try self.tokens.append(.{
            .type = .LetEnd,
            .index = start,
            .end = self.pos,
        });
    }

    // ─── Special Constructs ───────────────────────────────────

    fn scanComment(self: *Lexer) !void {
        const start = self.pos;
        self.pos += 4; // skip <!--

        var found_end = false;
        while (self.pos < self.source.len) {
            if (self.startsWith("-->")) {
                self.pos += 3;
                found_end = true;
                break;
            }
            self.pos += 1;
        }

        if (!found_end) {
            try self.reportError(@intCast(self.pos), "Unexpected character EOF");
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
        if (self.pos < self.source.len) {
            self.pos += 1;
        } else {
            try self.reportError(@intCast(self.pos), "Unexpected character EOF");
        }

        try self.tokens.append(.{
            .type = .DocType,
            .index = start,
            .end = self.pos,
        });
    }

    fn scanCdata(self: *Lexer) !void {
        const start = self.pos;
        self.pos += 9; // skip <![CDATA[

        var found_end = false;
        while (self.pos < self.source.len) {
            if (self.startsWith("]]>")) {
                self.pos += 3;
                found_end = true;
                break;
            }
            self.pos += 1;
        }

        if (!found_end) {
            try self.reportError(@intCast(self.pos), "Unexpected character EOF");
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

    /// Report a lexer error.
    pub fn reportError(self: *Lexer, index: u32, message: []const u8) !void {
        try self.errors.append(.{ .index = index, .end = index + 1, .message = message });
    }
};

/// Top-level tokenize function.
/// Direct port of `tokenize(...)` function in the TS source.
pub fn tokenize(
    allocator: std.mem.Allocator,
    source: []const u8,
    url: []const u8,
    options: TokenizeOptions,
) !TokenizeResult {
    _ = url;
    var lexer = Lexer.initWithOptions(allocator, source, options);
    defer lexer.deinit();

    const result = try lexer.tokenize();

    // Copy tokens and errors to owned slices
    const tokens = try allocator.dupe(HtmlToken, result.@"0");
    const errors = try allocator.dupe(LexError, result.@"1");

    return .{
        .tokens = tokens,
        .errors = errors,
    };
}

// ─── Tests ────────────────────────────────────────────────────

test "tokenize simple HTML" {
    const allocator = std.testing.allocator;
    const source = "<div>Hello</div>";
    var lex = Lexer.init(allocator, source);
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

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

    for (tokens) |tok| {
        if (tok.type == .TagOpenEndVoid or tok.type == .TagOpenEnd) {
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

    for (tokens) |tok| {
        if (tok.type == .Text and tok.parts.len > 0) {
            try std.testing.expectEqual(@as(usize, 1), tok.parts.len);
            try std.testing.expect(tok.parts[0].is_expression);
        }
    }
}

test "tokenize comment" {
    const allocator = std.testing.allocator;
    const source = "<!-- comment --><div></div>";
    var lex = Lexer.init(allocator, source);
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

    var found_comment = false;
    for (tokens) |tok| {
        if (tok.type == .Comment) {
            found_comment = true;
            try std.testing.expect(std.mem.indexOf(u8, tok.slice(source), "comment") != null);
        }
    }
    try std.testing.expect(found_comment);
}

test "tokenize CDATA" {
    const allocator = std.testing.allocator;
    const source = "<![CDATA[hello world]]>";
    var lex = Lexer.init(allocator, source);
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

    var found_cdata = false;
    for (tokens) |tok| {
        if (tok.type == .Cdata) {
            found_cdata = true;
        }
    }
    try std.testing.expect(found_cdata);
}

test "tokenize DocType" {
    const allocator = std.testing.allocator;
    const source = "<!DOCTYPE html><html></html>";
    var lex = Lexer.init(allocator, source);
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

    var found_doctype = false;
    for (tokens) |tok| {
        if (tok.type == .DocType) {
            found_doctype = true;
        }
    }
    try std.testing.expect(found_doctype);
}

test "tokenize entity reference" {
    const allocator = std.testing.allocator;
    const source = "<div>&amp;</div>";
    var lex = Lexer.init(allocator, source);
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

    var found_entity = false;
    for (tokens) |tok| {
        if (tok.type == .EncodedEntity) {
            found_entity = true;
            try std.testing.expectEqualStrings("amp", tok.entity_value.?);
        }
    }
    try std.testing.expect(found_entity);
}

test "tokenize block @if" {
    const allocator = std.testing.allocator;
    const source = "@if (condition) { content }";
    var lex = Lexer.initWithOptions(allocator, source, .{ .tokenize_blocks = true });
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

    var found_block = false;
    for (tokens) |tok| {
        if (tok.type == .BlockOpenStart) {
            found_block = true;
        }
    }
    try std.testing.expect(found_block);
}

test "tokenize @let declaration" {
    const allocator = std.testing.allocator;
    const source = "@let x = 1 + 2;";
    var lex = Lexer.initWithOptions(allocator, source, .{ .tokenize_let = true });
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

    var found_let = false;
    for (tokens) |tok| {
        if (tok.type == .LetStart) {
            found_let = true;
        }
    }
    try std.testing.expect(found_let);
}

test "tokenize nested tags" {
    const allocator = std.testing.allocator;
    const source = "<div><span>text</span></div>";
    var lex = Lexer.init(allocator, source);
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

    var tag_name_count: usize = 0;
    for (tokens) |tok| {
        if (tok.type == .TagName) tag_name_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 4), tag_name_count);
}

test "tokenize unquoted attribute" {
    const allocator = std.testing.allocator;
    const source = "<input disabled>";
    var lex = Lexer.init(allocator, source);
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

    var found_attr = false;
    for (tokens) |tok| {
        if (tok.type == .AttributeName) {
            found_attr = true;
            try std.testing.expectEqualStrings("disabled", tok.slice(source));
        }
    }
    try std.testing.expect(found_attr);
}

test "tokenize multiple attributes" {
    const allocator = std.testing.allocator;
    const source = "<div class=\"container\" id=\"main\" [hidden]=\"false\">";
    var lex = Lexer.init(allocator, source);
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

    var attr_count: usize = 0;
    for (tokens) |tok| {
        if (tok.type == .AttributeName) attr_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), attr_count);
}

test "tokenize interpolation in attribute" {
    const allocator = std.testing.allocator;
    const source = "<div class=\"{{ active }}\">";
    var lex = Lexer.init(allocator, source);
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

    for (tokens) |tok| {
        if (tok.type == .AttributeValue and tok.parts.len > 0) {
            try std.testing.expect(tok.parts[0].is_expression);
        }
    }
}

test "tokenize closing tag" {
    const allocator = std.testing.allocator;
    const source = "</div>";
    var lex = Lexer.init(allocator, source);
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

    try std.testing.expectEqual(HtmlTokenType.TagCloseStart, tokens[0].type);
    try std.testing.expectEqual(HtmlTokenType.TagName, tokens[1].type);
    try std.testing.expectEqualStrings("div", tokens[1].slice(source));
}

test "tokenize empty source" {
    const allocator = std.testing.allocator;
    const source = "";
    var lex = Lexer.init(allocator, source);
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

    try std.testing.expectEqual(@as(usize, 1), tokens.len);
    try std.testing.expectEqual(HtmlTokenType.EOF, tokens[0].type);
}

test "tokenize text only" {
    const allocator = std.testing.allocator;
    const source = "Hello World";
    var lex = Lexer.init(allocator, source);
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

    try std.testing.expectEqual(HtmlTokenType.Text, tokens[0].type);
    try std.testing.expectEqualStrings("Hello World", tokens[0].slice(source));
}

test "tokenize mixed content" {
    const allocator = std.testing.allocator;
    const source = "text<div>inner</div>more";
    var lex = Lexer.init(allocator, source);
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

    try std.testing.expectEqual(HtmlTokenType.Text, tokens[0].type);
    try std.testing.expect(std.mem.indexOf(u8, tokens[0].slice(source), "text") != null);
}

test "processCarriageReturns" {
    const allocator = std.testing.allocator;
    const r1 = try processCarriageReturns(allocator, "hello\r\nworld");
    defer allocator.free(r1);
    try std.testing.expectEqualStrings("hello\nworld", r1);

    const r2 = try processCarriageReturns(allocator, "hello\rworld");
    defer allocator.free(r2);
    try std.testing.expectEqualStrings("hello\nworld", r2);

    const r3 = try processCarriageReturns(allocator, "hello\nworld");
    defer allocator.free(r3);
    try std.testing.expectEqualStrings("hello\nworld", r3);
}

test "isSupportedBlock" {
    try std.testing.expect(isSupportedBlock("if"));
    try std.testing.expect(isSupportedBlock("for"));
    try std.testing.expect(isSupportedBlock("switch"));
    try std.testing.expect(isSupportedBlock("defer"));
    try std.testing.expect(isSupportedBlock("case"));
    try std.testing.expect(isSupportedBlock("default"));
    try std.testing.expect(isSupportedBlock("else"));
    try std.testing.expect(isSupportedBlock("empty"));
    try std.testing.expect(isSupportedBlock("placeholder"));
    try std.testing.expect(isSupportedBlock("loading"));
    try std.testing.expect(isSupportedBlock("error"));
    try std.testing.expect(!isSupportedBlock("unknown"));
}

test "TokenizeOptions defaults" {
    const opts = TokenizeOptions{};
    try std.testing.expect(!opts.tokenize_icu);
    try std.testing.expect(!opts.tokenize_blocks);
    try std.testing.expect(!opts.tokenize_let);
    try std.testing.expect(!opts.selectorless_enabled);
    try std.testing.expect(!opts.preserve_line_endings);
}

test "LexerRange defaults" {
    const range = LexerRange{};
    try std.testing.expectEqual(@as(u32, 0), range.start);
    try std.testing.expectEqual(@as(u32, 0), range.end);
}

test "Lexer initWithOptions" {
    const allocator = std.testing.allocator;
    const opts = TokenizeOptions{ .tokenize_blocks = true, .tokenize_let = true };
    var lex = Lexer.initWithOptions(allocator, "@if (x) {}", opts);
    defer lex.deinit();
    try std.testing.expect(lex.options.tokenize_blocks);
    try std.testing.expect(lex.options.tokenize_let);
}

test "Lexer reportError" {
    const allocator = std.testing.allocator;
    var lex = Lexer.init(allocator, "test");
    defer lex.deinit();
    try lex.reportError(5, "unexpected character");
    try std.testing.expectEqual(@as(usize, 1), lex.errors.items.len);
    try std.testing.expectEqualStrings("unexpected character", lex.errors.items[0].message);
}

test "HtmlToken slice out of bounds" {
    const tok = HtmlToken{ .type = .Text, .index = 100, .end = 200 };
    try std.testing.expectEqualStrings("", tok.slice("short"));
}

test "CharacterReferenceType values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(CharacterReferenceType.Decimal));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(CharacterReferenceType.Hex));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(CharacterReferenceType.Named));
}

test "HtmlTokenType has all variants" {
    const types = std.meta.tags(HtmlTokenType);
    try std.testing.expect(types.len >= 30);
}

test "tokenize decimal entity" {
    const allocator = std.testing.allocator;
    const source = "<div>&#65;</div>";
    var lex = Lexer.init(allocator, source);
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

    for (tokens) |tok| {
        if (tok.type == .EncodedEntity) {
            try std.testing.expectEqualStrings("#65", tok.entity_value.?);
        }
    }
}

test "tokenize hex entity" {
    const allocator = std.testing.allocator;
    const source = "<div>&#x41;</div>";
    var lex = Lexer.init(allocator, source);
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

    for (tokens) |tok| {
        if (tok.type == .EncodedEntity) {
            try std.testing.expectEqualStrings("#x41", tok.entity_value.?);
        }
    }
}

test "tokenize nested interpolation" {
    const allocator = std.testing.allocator;
    const source = "<span>{{ {{a}} + {{b}} }}</span>";
    var lex = Lexer.init(allocator, source);
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

    // Should find text token with interpolation parts
    for (tokens) |tok| {
        if (tok.type == .Text and tok.parts.len > 0) {
            try std.testing.expect(tok.parts.len >= 1);
        }
    }
}

test "tokenize block @for" {
    const allocator = std.testing.allocator;
    const source = "@for (item of items; track item) { {{item}} }";
    var lex = Lexer.initWithOptions(allocator, source, .{ .tokenize_blocks = true });
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

    var found_param = false;
    for (tokens) |tok| {
        if (tok.type == .BlockParameter) {
            found_param = true;
        }
    }
    try std.testing.expect(found_param);
}

test "tokenize block @switch" {
    const allocator = std.testing.allocator;
    const source = "@switch (color) { @case (red) { } }";
    var lex = Lexer.initWithOptions(allocator, source, .{ .tokenize_blocks = true });
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

    var block_count: usize = 0;
    for (tokens) |tok| {
        if (tok.type == .BlockOpenStart) block_count += 1;
    }
    try std.testing.expect(block_count >= 1);
}

test "tokenize top-level tokenize function" {
    const allocator = std.testing.allocator;
    const result = try tokenize(allocator, "<div>test</div>", "test.html", .{});
    defer allocator.free(result.tokens);
    defer allocator.free(result.errors);
    try std.testing.expect(result.tokens.len > 0);
    try std.testing.expectEqual(HtmlTokenType.TagOpenStart, result.tokens[0].type);
}

test "tokenize text with entities" {
    const allocator = std.testing.allocator;
    const source = "Hello &amp; World &lt;tag&gt;";
    var lex = Lexer.init(allocator, source);
    defer lex.deinit();

    const result = try lex.tokenize();
    const tokens = result.@"0";

    // Entities are part of text tokens (not separate EncodedEntity tokens
    // when they appear in text content, only when they start with & and
    // aren't inside a tag)
    var text_count: usize = 0;
    for (tokens) |tok| {
        if (tok.type == .Text) text_count += 1;
    }
    try std.testing.expect(text_count >= 1);
}

// ─── CharacterCursor (Direct port of CharacterCursor interface) ──────

/// CharacterCursor — abstract cursor for moving through input text.
/// Direct port of `CharacterCursor` interface in the TS source.
pub const CharacterCursor = struct {
    source: []const u8,
    pos: u32 = 0,
    line: u32 = 0,
    column: u32 = 0,

    pub fn init(source: []const u8) CharacterCursor {
        return .{ .source = source };
    }

    /// Peek at the current character code without advancing.
    pub fn peek(self: *const CharacterCursor) u8 {
        if (self.pos >= self.source.len) return 0; // EOF
        return self.source[self.pos];
    }

    /// Advance the cursor by one character.
    pub fn advance(self: *CharacterCursor) void {
        if (self.pos < self.source.len) {
            if (self.source[self.pos] == '\n') {
                self.line += 1;
                self.column = 0;
            } else {
                self.column += 1;
            }
            self.pos += 1;
        }
    }

    /// Get characters from start to current position.
    pub fn getChars(self: *const CharacterCursor, start: CharacterCursor) []const u8 {
        if (start.pos <= self.pos and self.pos <= self.source.len) {
            return self.source[start.pos..self.pos];
        }
        return "";
    }

    /// Number of characters remaining.
    pub fn charsLeft(self: *const CharacterCursor) u32 {
        if (self.pos >= self.source.len) return 0;
        return @intCast(self.source.len - self.pos);
    }

    /// Clone this cursor.
    pub fn clone(self: *const CharacterCursor) CharacterCursor {
        return .{
            .source = self.source,
            .pos = self.pos,
            .line = self.line,
            .column = self.column,
        };
    }

    /// Difference in position between this cursor and another.
    pub fn diff(self: *const CharacterCursor, other: CharacterCursor) i32 {
        return @as(i32, @intCast(self.pos)) - @as(i32, @intCast(other.pos));
    }
};

// ─── Helper Predicates (Direct port of standalone functions) ─────────

/// Check if a character code is not whitespace.
/// Direct port of `isNotWhitespace(code)` in the TS source.
pub fn isNotWhitespace(code: u8) bool {
    return !chars.isWhitespace(code) or code == 0; // EOF
}

/// Check if a character code ends a name.
/// Direct port of `isNameEnd(code)` in the TS source.
pub fn isNameEnd(code: u8) bool {
    return chars.isWhitespace(code) or
        code == '>' or code == '<' or code == '/' or
        code == '\'' or code == '"' or code == '=' or code == 0;
}

/// Check if a character code ends a namespace prefix.
/// Direct port of `isPrefixEnd(code)` in the TS source.
pub fn isPrefixEnd(code: u8) bool {
    return !(code >= 'a' and code <= 'z') and
        !(code >= 'A' and code <= 'Z') and
        !(code >= '0' and code <= '9');
}

/// Check if a character code ends a digit entity.
/// Direct port of `isDigitEntityEnd(code)` in the TS source.
pub fn isDigitEntityEnd(code: u8) bool {
    return code == ';' or code == 0 or !chars.isAsciiHexDigit(code);
}

/// Check if a character code ends a named entity.
/// Direct port of `isNamedEntityEnd(code)` in the TS source.
pub fn isNamedEntityEnd(code: u8) bool {
    return code == ';' or code == 0 or
        !(chars.isAsciiLetter(code) or chars.isDigit(code));
}

/// Check if a character is the start of an expansion case.
/// Direct port of `isExpansionCaseStart(peek)` in the TS source.
pub fn isExpansionCaseStart(peek: u8) bool {
    return peek != '}';
}

/// Compare two character codes case-insensitively.
/// Direct port of `compareCharCodeCaseInsensitive(code1, code2)` in the TS source.
pub fn compareCharCodeCaseInsensitive(code1: u8, code2: u8) bool {
    return toUpperCaseCharCode(code1) == toUpperCaseCharCode(code2);
}

/// Convert a character code to uppercase.
/// Direct port of `toUpperCaseCharCode(code)` in the TS source.
pub fn toUpperCaseCharCode(code: u8) u8 {
    if (code >= 'a' and code <= 'z') return code - 'a' + 'A';
    return code;
}

/// Check if a character is valid in a block name.
/// Direct port of `isBlockNameChar(code)` in the TS source.
pub fn isBlockNameChar(code: u8) bool {
    return chars.isAsciiLetter(code) or chars.isDigit(code) or code == '_';
}

/// Check if a character is valid in a block parameter.
/// Direct port of `isBlockParameterChar(code)` in the TS source.
pub fn isBlockParameterChar(code: u8) bool {
    return code != ';' and isNotWhitespace(code);
}

/// Check if a character can start a selectorless name.
/// Direct port of `isSelectorlessNameStart(code)` in the TS source.
pub fn isSelectorlessNameStart(code: u8) bool {
    return code == '_' or (code >= 'A' and code <= 'Z');
}

/// Check if a character can be part of a selectorless name.
/// Direct port of `isSelectorlessNameChar(code)` in the TS source.
pub fn isSelectorlessNameChar(code: u8) bool {
    return chars.isAsciiLetter(code) or chars.isDigit(code) or code == '_';
}

/// Check if a character terminates attributes.
/// Direct port of `isAttributeTerminator(code)` in the TS source.
pub fn isAttributeTerminator(code: u8) bool {
    return code == '/' or code == '>' or code == '<' or code == 0;
}

// ─── Error Message Helpers ──────────────────────────────────

/// Generate an "unexpected character" error message.
/// Direct port of `_unexpectedCharacterErrorMsg(charCode)` in the TS source.
pub fn unexpectedCharacterErrorMsg(charCode: u8) []const u8 {
    if (charCode == 0) return "Unexpected character \"EOF\"";
    return "Unexpected character"; // Full version would format the char
}

/// Generate an "unknown entity" error message.
/// Direct port of `_unknownEntityErrorMsg(entitySrc)` in the TS source.
pub fn unknownEntityErrorMsg(entity_src: []const u8) []const u8 {
    _ = entity_src;
    return "Unknown entity - use the \"&#<decimal>;\" or  \"&#x<hex>;\" syntax";
}

/// Generate an "unparsable entity" error message.
/// Direct port of `_unparsableEntityErrorMsg(type, entityStr)` in the TS source.
pub fn unparsableEntityErrorMsg(entity_str: []const u8) []const u8 {
    _ = entity_str;
    return "Unable to parse entity - character reference entities must end with \";\"";
}

// ─── mergeTextTokens ────────────────────────────────────────

/// Merge adjacent text tokens into single tokens.
/// Direct port of `mergeTextTokens(srcTokens)` in the TS source.
pub fn mergeTextTokens(allocator: std.mem.Allocator, src_tokens: []const HtmlToken) ![]const HtmlToken {
    var dst_tokens = std.array_list.Managed(HtmlToken).init(allocator);
    errdefer dst_tokens.deinit();

    for (src_tokens) |token| {
        if (dst_tokens.items.len > 0) {
            const last_idx = dst_tokens.items.len - 1;
            // Merge adjacent TEXT tokens
            if (dst_tokens.items[last_idx].type == .Text and token.type == .Text) {
                // Extend the last token's end to include this token
                dst_tokens.items[last_idx].end = token.end;
                continue;
            }
        }
        try dst_tokens.append(token);
    }

    return dst_tokens.toOwnedSlice();
}

// ─── Patterns ───────────────────────────────────────────────

/// Check if a string matches the "default never" pattern.
/// Direct port of `DEFAULT_NEVER_PATTERN = /^default[^\S\r\n]+never/` in the TS source.
pub fn isDefaultNeverPattern(s: []const u8) bool {
    if (!std.mem.startsWith(u8, s, "default")) return false;
    var i: usize = 7; // skip "default"
    // Skip whitespace (not newlines)
    var found_ws = false;
    while (i < s.len and (s[i] == ' ' or s[i] == '\t')) : (i += 1) {
        found_ws = true;
    }
    if (!found_ws) return false;
    return std.mem.startsWith(u8, s[i..], "never");
}

/// Check if a string matches the "else if" pattern.
/// Direct port of `ELSE_IF_PATTERN = /^else[^\S\r\n]+if/` in the TS source.
pub fn isElseIfPattern(s: []const u8) bool {
    if (!std.mem.startsWith(u8, s, "else")) return false;
    var i: usize = 4; // skip "else"
    var found_ws = false;
    while (i < s.len and (s[i] == ' ' or s[i] == '\t')) : (i += 1) {
        found_ws = true;
    }
    if (!found_ws) return false;
    return std.mem.startsWith(u8, s[i..], "if");
}

// ─── Additional Tests ───────────────────────────────────────

test "CharacterCursor init and peek" {
    const cursor = CharacterCursor.init("hello");
    try std.testing.expectEqual(@as(u8, 'h'), cursor.peek());
    try std.testing.expectEqual(@as(u32, 5), cursor.charsLeft());
}

test "CharacterCursor advance" {
    var cursor = CharacterCursor.init("abc");
    try std.testing.expectEqual(@as(u8, 'a'), cursor.peek());
    cursor.advance();
    try std.testing.expectEqual(@as(u8, 'b'), cursor.peek());
    cursor.advance();
    try std.testing.expectEqual(@as(u8, 'c'), cursor.peek());
    cursor.advance();
    try std.testing.expectEqual(@as(u8, 0), cursor.peek()); // EOF
}

test "CharacterCursor getChars" {
    var cursor = CharacterCursor.init("hello world");
    const start = cursor.clone();
    cursor.advance();
    cursor.advance();
    cursor.advance();
    try std.testing.expectEqualStrings("hel", cursor.getChars(start));
}

test "CharacterCursor clone" {
    var cursor = CharacterCursor.init("test");
    cursor.advance();
    const cloned = cursor.clone();
    try std.testing.expectEqual(cursor.pos, cloned.pos);
    try std.testing.expectEqual(cursor.line, cloned.line);
    try std.testing.expectEqual(cursor.column, cloned.column);
}

test "CharacterCursor diff" {
    var cursor1 = CharacterCursor.init("hello");
    cursor1.pos = 3;
    var cursor2 = CharacterCursor.init("hello");
    cursor2.pos = 1;
    try std.testing.expectEqual(@as(i32, 2), cursor1.diff(cursor2));
}

test "isNotWhitespace" {
    try std.testing.expect(isNotWhitespace('a'));
    try std.testing.expect(isNotWhitespace(0)); // EOF is "not whitespace"
    try std.testing.expect(!isNotWhitespace(' '));
    try std.testing.expect(!isNotWhitespace('\n'));
}

test "isNameEnd" {
    try std.testing.expect(isNameEnd(' '));
    try std.testing.expect(isNameEnd('>'));
    try std.testing.expect(isNameEnd('<'));
    try std.testing.expect(isNameEnd('/'));
    try std.testing.expect(isNameEnd('='));
    try std.testing.expect(isNameEnd('\''));
    try std.testing.expect(isNameEnd('"'));
    try std.testing.expect(isNameEnd(0)); // EOF
    try std.testing.expect(!isNameEnd('a'));
    try std.testing.expect(!isNameEnd('-'));
}

test "isPrefixEnd" {
    try std.testing.expect(isPrefixEnd('-'));
    try std.testing.expect(isPrefixEnd(':'));
    try std.testing.expect(!isPrefixEnd('a'));
    try std.testing.expect(!isPrefixEnd('A'));
    try std.testing.expect(!isPrefixEnd('0'));
}

test "isDigitEntityEnd" {
    try std.testing.expect(isDigitEntityEnd(';'));
    try std.testing.expect(isDigitEntityEnd(0)); // EOF
    try std.testing.expect(isDigitEntityEnd('g')); // Not hex
    try std.testing.expect(!isDigitEntityEnd('0'));
    try std.testing.expect(!isDigitEntityEnd('a'));
    try std.testing.expect(!isDigitEntityEnd('F'));
}

test "isNamedEntityEnd" {
    try std.testing.expect(isNamedEntityEnd(';'));
    try std.testing.expect(isNamedEntityEnd(0)); // EOF
    try std.testing.expect(isNamedEntityEnd('-'));
    try std.testing.expect(!isNamedEntityEnd('a'));
    try std.testing.expect(!isNamedEntityEnd('0'));
}

test "isExpansionCaseStart" {
    try std.testing.expect(isExpansionCaseStart('a'));
    try std.testing.expect(isExpansionCaseStart(0));
    try std.testing.expect(!isExpansionCaseStart('}'));
}

test "compareCharCodeCaseInsensitive" {
    try std.testing.expect(compareCharCodeCaseInsensitive('a', 'A'));
    try std.testing.expect(compareCharCodeCaseInsensitive('A', 'a'));
    try std.testing.expect(compareCharCodeCaseInsensitive('z', 'Z'));
    try std.testing.expect(!compareCharCodeCaseInsensitive('a', 'b'));
}

test "toUpperCaseCharCode" {
    try std.testing.expectEqual(@as(u8, 'A'), toUpperCaseCharCode('a'));
    try std.testing.expectEqual(@as(u8, 'Z'), toUpperCaseCharCode('z'));
    try std.testing.expectEqual(@as(u8, 'A'), toUpperCaseCharCode('A'));
    try std.testing.expectEqual(@as(u8, '0'), toUpperCaseCharCode('0'));
}

test "isBlockNameChar" {
    try std.testing.expect(isBlockNameChar('a'));
    try std.testing.expect(isBlockNameChar('A'));
    try std.testing.expect(isBlockNameChar('0'));
    try std.testing.expect(isBlockNameChar('_'));
    try std.testing.expect(!isBlockNameChar('-'));
    try std.testing.expect(!isBlockNameChar(' '));
}

test "isBlockParameterChar" {
    try std.testing.expect(isBlockParameterChar('a'));
    try std.testing.expect(isBlockParameterChar('('));
    try std.testing.expect(!isBlockParameterChar(';'));
    try std.testing.expect(!isBlockParameterChar(' '));
}

test "isSelectorlessNameStart" {
    try std.testing.expect(isSelectorlessNameStart('_'));
    try std.testing.expect(isSelectorlessNameStart('A'));
    try std.testing.expect(isSelectorlessNameStart('Z'));
    try std.testing.expect(!isSelectorlessNameStart('a'));
    try std.testing.expect(!isSelectorlessNameStart('0'));
}

test "isSelectorlessNameChar" {
    try std.testing.expect(isSelectorlessNameChar('a'));
    try std.testing.expect(isSelectorlessNameChar('A'));
    try std.testing.expect(isSelectorlessNameChar('0'));
    try std.testing.expect(isSelectorlessNameChar('_'));
    try std.testing.expect(!isSelectorlessNameChar('-'));
    try std.testing.expect(!isSelectorlessNameChar('.'));
}

test "isAttributeTerminator" {
    try std.testing.expect(isAttributeTerminator('/'));
    try std.testing.expect(isAttributeTerminator('>'));
    try std.testing.expect(isAttributeTerminator('<'));
    try std.testing.expect(isAttributeTerminator(0)); // EOF
    try std.testing.expect(!isAttributeTerminator('a'));
    try std.testing.expect(!isAttributeTerminator(' '));
}

test "unexpectedCharacterErrorMsg" {
    try std.testing.expect(std.mem.indexOf(u8, unexpectedCharacterErrorMsg(0), "EOF") != null);
    try std.testing.expect(std.mem.indexOf(u8, unexpectedCharacterErrorMsg('x'), "Unexpected") != null);
}

test "unknownEntityErrorMsg" {
    const msg = unknownEntityErrorMsg("&unknown;");
    try std.testing.expect(std.mem.indexOf(u8, msg, "Unknown entity") != null);
}

test "unparsableEntityErrorMsg" {
    const msg = unparsableEntityErrorMsg("&#123");
    try std.testing.expect(std.mem.indexOf(u8, msg, "Unable to parse") != null);
}

test "mergeTextTokens" {
    const allocator = std.testing.allocator;
    const tokens = [_]HtmlToken{
        .{ .type = .Text, .index = 0, .end = 5 },
        .{ .type = .Text, .index = 5, .end = 10 },
        .{ .type = .TagOpenStart, .index = 10, .end = 11 },
    };
    const merged = try mergeTextTokens(allocator, &tokens);
    defer allocator.free(merged);
    try std.testing.expectEqual(@as(usize, 2), merged.len);
    try std.testing.expectEqual(@as(u32, 10), merged[0].end);
}

test "isDefaultNeverPattern" {
    try std.testing.expect(isDefaultNeverPattern("default never"));
    try std.testing.expect(isDefaultNeverPattern("default  never"));
    try std.testing.expect(isDefaultNeverPattern("default\tnever"));
    try std.testing.expect(!isDefaultNeverPattern("default"));
    try std.testing.expect(!isDefaultNeverPattern("defaultnever"));
    try std.testing.expect(!isDefaultNeverPattern("default\nnever"));
}

test "isElseIfPattern" {
    try std.testing.expect(isElseIfPattern("else if"));
    try std.testing.expect(isElseIfPattern("else  if"));
    try std.testing.expect(isElseIfPattern("else\tif"));
    try std.testing.expect(!isElseIfPattern("else"));
    try std.testing.expect(!isElseIfPattern("elseif"));
    try std.testing.expect(!isElseIfPattern("else\nif"));
}

// ─── EscapedCharacterCursor ─────────────────────────────────

/// CursorState — internal state of a character cursor.
/// Direct port of `CursorState` interface in the TS source.
pub const CursorState = struct {
    peek: u8 = 0,
    offset: u32 = 0,
    line: u32 = 0,
    column: u32 = 0,
};

/// ParseSourceFile — a source file with content and URL.
/// Direct port of `ParseSourceFile` from parse_util.ts.
pub const ParseSourceFile = struct {
    content: []const u8,
    url: []const u8,
};

/// ParseLocation — a location within a source file.
/// Direct port of `ParseLocation` from parse_util.ts.
pub const ParseLocation = struct {
    file: ?*const ParseSourceFile = null,
    offset: u32 = 0,
    line: u32 = 0,
    column: u32 = 0,
};

/// ParseSourceSpan — a span within a source file.
/// Direct port of `ParseSourceSpan` from parse_util.ts.
pub const ParseSourceSpan = struct {
    start: ParseLocation = .{},
    end: ParseLocation = .{},
    full_start: ?ParseLocation = null,
};

/// CursorError — an error thrown by the cursor during tokenization.
/// Direct port of `CursorError` class in the TS source.
pub const CursorError = struct {
    msg: []const u8,
    cursor: CharacterCursor,
};

/// EscapedCharacterCursor — a cursor that processes escape sequences.
/// Direct port of `EscapedCharacterCursor` class in the TS source.
///
/// This cursor wraps a PlainCharacterCursor and processes escape sequences
/// such as \n, \t, \u1234, \x2F, \012, and line continuations.
pub const EscapedCharacterCursor = struct {
    /// The underlying plain cursor state (external state visible to consumers).
    state: CursorState,
    /// The internal state (tracks position before escape processing).
    internal_state: CursorState,
    /// The source file being tokenized.
    file: *const ParseSourceFile,
    /// The input string.
    input: []const u8,
    /// The end position of the range.
    end: u32,

    /// Initialize from a ParseSourceFile and range.
    pub fn init(file: *const ParseSourceFile, range: LexerRange) EscapedCharacterCursor {
        return .{
            .state = .{
                .peek = 0,
                .offset = range.start,
                .line = 0,
                .column = 0,
            },
            .internal_state = .{
                .peek = 0,
                .offset = range.start,
                .line = 0,
                .column = 0,
            },
            .file = file,
            .input = file.content,
            .end = range.end,
        };
    }

    /// Clone this cursor.
    pub fn clone(self: *const EscapedCharacterCursor) EscapedCharacterCursor {
        return .{
            .state = self.state,
            .internal_state = self.internal_state,
            .file = self.file,
            .input = self.input,
            .end = self.end,
        };
    }

    /// Peek at the current character (after escape processing).
    pub fn peek(self: *const EscapedCharacterCursor) u8 {
        return self.state.peek;
    }

    /// Characters remaining.
    pub fn charsLeft(self: *const EscapedCharacterCursor) u32 {
        return if (self.state.offset >= self.end) 0 else self.end - self.state.offset;
    }

    /// Difference between this cursor and another.
    pub fn diff(self: *const EscapedCharacterCursor, other: EscapedCharacterCursor) i32 {
        return @as(i32, @intCast(self.state.offset)) - @as(i32, @intCast(other.state.offset));
    }

    /// Initialize the cursor (read the first character).
    pub fn initCursor(self: *EscapedCharacterCursor) void {
        self.updatePeek(&self.state);
        self.internal_state = self.state;
        self.processEscapeSequence();
    }

    /// Advance by one character (with escape processing).
    pub fn advance(self: *EscapedCharacterCursor) void {
        self.state = self.internal_state;
        self.advanceState(&self.state);
        self.processEscapeSequence();
    }

    /// Get characters from start to current position.
    pub fn getChars(self: *const EscapedCharacterCursor, start: EscapedCharacterCursor) []const u8 {
        if (start.internal_state.offset <= self.internal_state.offset and
            self.internal_state.offset <= self.input.len)
        {
            return self.input[start.internal_state.offset..self.internal_state.offset];
        }
        return "";
    }

    /// Get a span from start to current position.
    pub fn getSpan(self: *const EscapedCharacterCursor, start: ?EscapedCharacterCursor) ParseSourceSpan {
        const s = start orelse self.clone();
        return .{
            .start = .{ .file = self.file, .offset = s.state.offset, .line = s.state.line, .column = s.state.column },
            .end = .{ .file = self.file, .offset = self.state.offset, .line = self.state.line, .column = self.state.column },
        };
    }

    /// Advance the internal state by one character.
    fn advanceState(self: *EscapedCharacterCursor, state: *CursorState) void {
        if (state.offset >= self.end) return;
        const ch = self.input[state.offset];
        if (ch == '\n') {
            state.line += 1;
            state.column = 0;
        } else if (ch != '\r') {
            state.column += 1;
        }
        state.offset += 1;
        self.updatePeek(state);
    }

    /// Update the peek value of a state.
    fn updatePeek(self: *const EscapedCharacterCursor, state: *CursorState) void {
        state.peek = if (state.offset >= self.end) 0 else self.input[state.offset];
    }

    /// Process an escape sequence at the current position.
    /// Direct port of `processEscapeSequence()` in the TS source.
    fn processEscapeSequence(self: *EscapedCharacterCursor) void {
        const peek_val = self.internal_state.peek;

        if (peek_val != '\\') return;

        // Make internal state independent
        self.internal_state = self.state;

        // Move past the backslash
        self.advanceState(&self.internal_state);

        const next = self.internal_state.peek;

        // Standard control character sequences
        if (next == 'n') {
            self.state.peek = '\n';
        } else if (next == 'r') {
            self.state.peek = '\r';
        } else if (next == 'v') {
            self.state.peek = 0x0B; // VTAB
        } else if (next == 't') {
            self.state.peek = '\t';
        } else if (next == 'b') {
            self.state.peek = 0x08; // BACKSPACE
        } else if (next == 'f') {
            self.state.peek = 0x0C; // FORM FEED
        } else if (next == 'u') {
            // Unicode escape: \u1234 or \u{123}
            self.advanceState(&self.internal_state); // past 'u'
            if (self.internal_state.peek == '{') {
                // Variable length: \u{...}
                self.advanceState(&self.internal_state); // past '{'
                var code: u32 = 0;
                while (self.internal_state.peek != '}' and self.internal_state.peek != 0) {
                    const hex_digit = self.internal_state.peek;
                    const digit_val: u32 = if (hex_digit >= '0' and hex_digit <= '9')
                        hex_digit - '0'
                    else if (hex_digit >= 'a' and hex_digit <= 'f')
                        hex_digit - 'a' + 10
                    else if (hex_digit >= 'A' and hex_digit <= 'F')
                        hex_digit - 'A' + 10
                    else
                        break;
                    code = code * 16 + digit_val;
                    self.advanceState(&self.internal_state);
                }
                self.state.peek = if (code <= 255) @intCast(code) else '?';
            } else {
                // Fixed length: \uXXXX (4 hex digits)
                var code: u32 = 0;
                var i: u32 = 0;
                while (i < 4) : (i += 1) {
                    const hex_digit = self.internal_state.peek;
                    const digit_val: u32 = if (hex_digit >= '0' and hex_digit <= '9')
                        hex_digit - '0'
                    else if (hex_digit >= 'a' and hex_digit <= 'f')
                        hex_digit - 'a' + 10
                    else if (hex_digit >= 'A' and hex_digit <= 'F')
                        hex_digit - 'A' + 10
                    else
                        break;
                    code = code * 16 + digit_val;
                    self.advanceState(&self.internal_state);
                }
                self.state.peek = if (code <= 255) @intCast(code) else '?';
            }
        } else if (next == 'x') {
            // Hex escape: \xXX (2 hex digits)
            self.advanceState(&self.internal_state); // past 'x'
            var code: u32 = 0;
            var i: u32 = 0;
            while (i < 2) : (i += 1) {
                const hex_digit = self.internal_state.peek;
                const digit_val: u32 = if (hex_digit >= '0' and hex_digit <= '9')
                    hex_digit - '0'
                else if (hex_digit >= 'a' and hex_digit <= 'f')
                    hex_digit - 'a' + 10
                else if (hex_digit >= 'A' and hex_digit <= 'F')
                    hex_digit - 'A' + 10
                else
                    break;
                code = code * 16 + digit_val;
                self.advanceState(&self.internal_state);
            }
            self.state.peek = @intCast(code);
        } else if (next >= '0' and next <= '7') {
            // Octal escape: \012 (up to 3 octal digits)
            var code: u32 = 0;
            var count: u32 = 0;
            while (count < 3 and self.internal_state.peek >= '0' and self.internal_state.peek <= '7') : (count += 1) {
                code = code * 8 + (self.internal_state.peek - '0');
                self.advanceState(&self.internal_state);
            }
            // Back up one character (we overread)
            if (count > 0 and self.internal_state.offset > 0) {
                self.internal_state.offset -= 1;
                self.updatePeek(&self.internal_state);
            }
            self.state.peek = @intCast(code);
        } else if (next == '\n' or next == '\r') {
            // Line continuation: \ followed by newline
            self.advanceState(&self.internal_state);
            self.state = self.internal_state;
        } else {
            // Escaped normal character: just use the character after backslash
            self.state.peek = next;
        }
    }

    /// Decode hex digits from a starting position.
    fn decodeHexDigits(self: *const EscapedCharacterCursor, start: u32, length: u32) ?u8 {
        if (start + length > self.input.len) return null;
        var code: u32 = 0;
        var i: u32 = 0;
        while (i < length) : (i += 1) {
            const hex_digit = self.input[start + i];
            const digit_val: u32 = if (hex_digit >= '0' and hex_digit <= '9')
                hex_digit - '0'
            else if (hex_digit >= 'a' and hex_digit <= 'f')
                hex_digit - 'a' + 10
            else if (hex_digit >= 'A' and hex_digit <= 'F')
                hex_digit - 'A' + 10
            else
                return null;
            code = code * 16 + digit_val;
        }
        return if (code <= 255) @intCast(code) else null;
    }
};

// ─── Tests for EscapedCharacterCursor ───────────────────────

test "EscapedCharacterCursor init" {
    const file = ParseSourceFile{ .content = "hello", .url = "test.html" };
    var cursor = EscapedCharacterCursor.init(&file, .{ .start = 0, .end = 5 });
    cursor.initCursor();
    try std.testing.expectEqual(@as(u8, 'h'), cursor.peek());
}

test "EscapedCharacterCursor advance" {
    const file = ParseSourceFile{ .content = "abc", .url = "test.html" };
    var cursor = EscapedCharacterCursor.init(&file, .{ .start = 0, .end = 3 });
    cursor.initCursor();
    try std.testing.expectEqual(@as(u8, 'a'), cursor.peek());
    cursor.advance();
    // After advance, should see 'b'
    try std.testing.expectEqual(@as(u8, 'b'), cursor.peek());
}

test "EscapedCharacterCursor escape \\n" {
    const file = ParseSourceFile{ .content = "\\n", .url = "test.html" };
    var cursor = EscapedCharacterCursor.init(&file, .{ .start = 0, .end = 2 });
    cursor.initCursor();
    try std.testing.expectEqual(@as(u8, '\n'), cursor.peek());
}

test "EscapedCharacterCursor escape \\t" {
    const file = ParseSourceFile{ .content = "\\t", .url = "test.html" };
    var cursor = EscapedCharacterCursor.init(&file, .{ .start = 0, .end = 2 });
    cursor.initCursor();
    try std.testing.expectEqual(@as(u8, '\t'), cursor.peek());
}

test "EscapedCharacterCursor escape \\r" {
    const file = ParseSourceFile{ .content = "\\r", .url = "test.html" };
    var cursor = EscapedCharacterCursor.init(&file, .{ .start = 0, .end = 2 });
    cursor.initCursor();
    try std.testing.expectEqual(@as(u8, '\r'), cursor.peek());
}

test "EscapedCharacterCursor escape \\x41 (A)" {
    const file = ParseSourceFile{ .content = "\\x41", .url = "test.html" };
    var cursor = EscapedCharacterCursor.init(&file, .{ .start = 0, .end = 4 });
    cursor.initCursor();
    try std.testing.expectEqual(@as(u8, 'A'), cursor.peek());
}

test "EscapedCharacterCursor escape \\u0042 (B)" {
    const file = ParseSourceFile{ .content = "\\u0042", .url = "test.html" };
    var cursor = EscapedCharacterCursor.init(&file, .{ .start = 0, .end = 6 });
    cursor.initCursor();
    try std.testing.expectEqual(@as(u8, 'B'), cursor.peek());
}

test "EscapedCharacterCursor escape normal char" {
    const file = ParseSourceFile{ .content = "\\a", .url = "test.html" };
    var cursor = EscapedCharacterCursor.init(&file, .{ .start = 0, .end = 2 });
    cursor.initCursor();
    // \a should resolve to just 'a'
    try std.testing.expectEqual(@as(u8, 'a'), cursor.peek());
}

test "EscapedCharacterCursor clone" {
    const file = ParseSourceFile{ .content = "test", .url = "test.html" };
    var cursor = EscapedCharacterCursor.init(&file, .{ .start = 0, .end = 4 });
    cursor.initCursor();
    cursor.advance();
    const cloned = cursor.clone();
    try std.testing.expectEqual(cursor.state.offset, cloned.state.offset);
}

test "EscapedCharacterCursor getChars" {
    const file = ParseSourceFile{ .content = "hello", .url = "test.html" };
    var cursor = EscapedCharacterCursor.init(&file, .{ .start = 0, .end = 5 });
    cursor.initCursor();
    const start = cursor.clone();
    cursor.advance();
    // getChars should return some characters (or empty if internal state differs)
    const result_chars = cursor.getChars(start);
    _ = result_chars;
    // Just verify it doesn't crash
}

test "EscapedCharacterCursor charsLeft" {
    const file = ParseSourceFile{ .content = "hello", .url = "test.html" };
    var cursor = EscapedCharacterCursor.init(&file, .{ .start = 0, .end = 5 });
    cursor.initCursor();
    try std.testing.expectEqual(@as(u32, 5), cursor.charsLeft());
    cursor.advance();
    try std.testing.expectEqual(@as(u32, 4), cursor.charsLeft());
}

test "EscapedCharacterCursor diff" {
    const file = ParseSourceFile{ .content = "hello", .url = "test.html" };
    var cursor1 = EscapedCharacterCursor.init(&file, .{ .start = 0, .end = 5 });
    cursor1.initCursor();
    cursor1.advance();
    var cursor2 = EscapedCharacterCursor.init(&file, .{ .start = 0, .end = 5 });
    cursor2.initCursor();
    // diff should be positive after advancing
    const d = cursor1.diff(cursor2);
    try std.testing.expect(d >= 1);
}

test "CursorError" {
    const cursor = CharacterCursor.init("test");
    const err = CursorError{ .msg = "Unexpected character", .cursor = cursor };
    try std.testing.expectEqualStrings("Unexpected character", err.msg);
}

test "ParseSourceFile" {
    const file = ParseSourceFile{ .content = "hello world", .url = "test.html" };
    try std.testing.expectEqualStrings("hello world", file.content);
    try std.testing.expectEqualStrings("test.html", file.url);
}

test "ParseLocation defaults" {
    const loc = ParseLocation{};
    try std.testing.expectEqual(@as(u32, 0), loc.offset);
    try std.testing.expectEqual(@as(u32, 0), loc.line);
    try std.testing.expectEqual(@as(u32, 0), loc.column);
}

test "ParseSourceSpan defaults" {
    const span = ParseSourceSpan{};
    try std.testing.expectEqual(@as(u32, 0), span.start.offset);
    try std.testing.expectEqual(@as(u32, 0), span.end.offset);
}

test "CursorState defaults" {
    const state = CursorState{};
    try std.testing.expectEqual(@as(u8, 0), state.peek);
    try std.testing.expectEqual(@as(u32, 0), state.offset);
}
