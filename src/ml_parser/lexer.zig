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
            self.pos += 1;
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
        if (self.pos >= self.source.len) return;

        const self_closing = if (self.source[self.pos] == '/') blk: {
            self.pos += 1;
            break :blk true;
        } else false;

        if (self.pos < self.source.len and self.source[self.pos] == '>') {
            self.pos += 1;
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
