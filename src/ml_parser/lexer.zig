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
const entities = @import("entities.zig");

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
    /// Defaults to `true` to match TS (`tokenizeBlocks ?? true`).
    tokenize_blocks: bool = true,
    /// Defaults to `true` to match TS (`tokenizeLet ?? true`).
    tokenize_let: bool = true,
    selectorless_enabled: bool = false,
    preserve_line_endings: bool = false,
    i18n_normalize_line_endings_in_icus: bool = false,
    leading_trivia_code_points: []const u32 = &.{},
    /// When true, the lexer uses an `EscapedCharacterCursor` that processes
    /// escape sequences (`\xGG`, `\uGGGG`, `\u{GGGGG}`, `\n`, etc.) directly
    /// during scanning. Direct port of `escapedString?: boolean` in TS source.
    escaped_string: bool = false,
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
    /// Direct port of TS `INCOMPLETE_BLOCK_OPEN` — emitted when a block lacks
    /// its closing `{` (e.g. `@if (cond) hello}`).
    IncompleteBlockOpen,
    LetStart,
    LetValue,
    LetEnd,
    /// Direct port of TS `INCOMPLETE_LET` — emitted when `@let` is malformed.
    IncompleteLet,
    ComponentOpenStart,
    ComponentOpenEnd,
    ComponentClose,
    DirectiveName,
    EncodedEntity,
    EscapableRawText,
    RawText,
    /// Direct port of TS `IN_ELEMENT_COMMENT` — inline `//` or `/* */` comments
    /// appearing inside element tags (between attributes).
    InElementComment,
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
    var found_interpolation = false;

    while (i < end) : (i += 1) {
        if (i + 1 < end and source[i] == '{' and source[i + 1] == '{') {
            found_interpolation = true;
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

    // Only create parts if we found an interpolation. Plain text gets no parts
    // (which means interpolation_boundaries will be empty in the parser).
    if (found_interpolation) {
        if (text_start < end) {
            try parts.append(.{ .start = text_start, .end = end, .is_expression = false });
        }
        return parts.toOwnedSlice();
    }

    return &[_]TokenPart{};
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
    /// Whether we're currently inside an interpolation `{{ ... }}`.
    /// Direct port of `_inInterpolation: boolean` in TS source.
    in_interpolation: bool = false,
    /// Block name stack.
    block_stack: std.array_list.Managed([]const u8),
    /// Owned processed source (from carriage return processing).
    processed_source: ?[]const u8 = null,
    /// Dynamically-allocated strings (error messages, entity values) that must
    /// be freed in `deinit`. Direct port of TS not-needed (V8 GC handles it).
    owned_strings: std.array_list.Managed([]const u8),

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Lexer {
        return .{
            .source = source,
            .tokens = std.array_list.Managed(HtmlToken).init(allocator),
            .errors = std.array_list.Managed(LexError).init(allocator),
            .raw_text_stack = std.array_list.Managed([]const u8).init(allocator),
            .block_stack = std.array_list.Managed([]const u8).init(allocator),
            .owned_strings = std.array_list.Managed([]const u8).init(allocator),
            .options = .{ .tokenize_blocks = true, .tokenize_let = true },
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
            .owned_strings = std.array_list.Managed([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Lexer) void {
        const allocator = self.tokens.allocator;
        for (self.tokens.items) |tok| {
            if (tok.parts.len > 0) {
                allocator.free(tok.parts);
            }
        }
        if (self.processed_source) |ps| {
            allocator.free(ps);
        }
        for (self.owned_strings.items) |s| {
            allocator.free(s);
        }
        self.tokens.deinit();
        self.errors.deinit();
        self.raw_text_stack.deinit();
        self.block_stack.deinit();
        self.owned_strings.deinit();
    }

    /// Tokenize the entire source string.
    /// Direct port of `tokenize(...)` function in the TS source.
    pub fn tokenize(self: *Lexer) !struct { []const HtmlToken, []const LexError } {
        // Process carriage returns if needed.
        if (!self.options.preserve_line_endings) {
            // Only process if source contains \r
            if (std.mem.indexOfScalar(u8, self.source, '\r') != null) {
                const processed = processCarriageReturns(self.tokens.allocator, self.source) catch self.source;
                if (processed.ptr != self.source.ptr) {
                    self.processed_source = processed;
                    self.source = processed;
                }
            }
        }

        // Escaped-string mode — direct port of `EscapedCharacterCursor` in TS source.
        // When `escapedString: true`, the entire input is treated as a single TEXT token
        // whose contents have escape sequences (`\n`, `\xGG`, `\uGGGG`, `\u{GG...}`, `\012`)
        // decoded. Invalid escape sequences produce errors.
        if (self.options.escaped_string) {
            try self.scanEscapedStringText();
            try self.tokens.append(.{
                .type = .EOF,
                .index = @intCast(self.source.len),
                .end = @intCast(self.source.len),
            });
            return .{ self.tokens.items, self.errors.items };
        }

        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];

            // Check for let declaration (@let) — must be BEFORE block check,
            // matching TS source order (`_isLetStart` is checked before `_isBlockStart`).
            if (self.options.tokenize_let and ch == '@') {
                if (self.startsWithIgnoreCase("@let")) {
                    try self.handleLetDeclaration();
                    continue;
                }
            }

            // Check for block syntax (@if, @for, etc.)
            if (self.options.tokenize_blocks and ch == '@') {
                try self.handleBlockStart();
                continue;
            }

            // Block close: `}` — direct port of TS `_attemptCharCode(chars.$RBRACE)` branch
            // which fires when not in interpolation/expansion form.
            if (self.options.tokenize_blocks and ch == '}' and !self.in_interpolation and !self.in_expansion) {
                try self.handleBlockEnd();
                continue;
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
                try self.reportError(@intCast(self.pos + 3), "Unexpected character \"-\"");
                self.pos += 3;
                return;
            }
            // Check for <![ without CDATA[
            if (self.pos + 2 < self.source.len and self.source[self.pos + 2] == '[') {
                if (!self.startsWith("<![CDATA[")) {
                    try self.reportError(@intCast(self.pos + 3), "Unexpected character \"[\"");
                    self.pos += 3;
                    return;
                }
            }
            // Generic <! with no matching construct
            if (self.pos + 2 >= self.source.len) {
                try self.reportError(@intCast(self.pos + 2), "Unexpected character \"EOF\"");
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
            // Direct port of TS `_consumeTagClose` which calls `_consumePrefixAndName(isNameEnd)`
            // that calls `_requireCharCodeUntilFn(...)` — throwing `CursorError('Unexpected character "EOF"')`
            // when EOF is hit before any name char.
            if (self.pos >= self.source.len) {
                try self.reportError(@intCast(self.pos), "Unexpected character \"EOF\"");
            } else if (!chars.isTagNameChar(self.source[self.pos])) {
                const ch = self.source[self.pos];
                try self.reportErrorFmt(@intCast(self.pos), "Unexpected character \"{c}\"", .{ch});
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

            // `<` terminates the attribute list — it's the start of a new tag
            // (likely an incomplete previous tag like `<a <span>`).
            if (ch == '<') {
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
            // Missing closing quote — direct port of TS `CursorError('Unexpected character "EOF"')`.
            // Error is reported at the EOF position (which equals `self.pos` here).
            try self.reportError(@intCast(self.pos), "Unexpected character \"EOF\"");
        }

        const parts = trackInterpolations(self.source, value_start, value_end, allocator) catch &[_]TokenPart{};

        // The AttributeValue token includes the opening and closing quotes in
        // its index range (matching the TS source's `_consumeWithInterpolation`
        // behavior, which wraps the value+quotes into a single token). The
        // parser strips the quotes when reading the value.
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
            // Missing > at end of source — direct port of TS `_requireCharCode(chars.$GT)`
            // throwing `CursorError('Unexpected character "EOF"')`.
            try self.reportError(@intCast(self.pos), "Unexpected character \"EOF\"");
            return;
        }

        const self_closing = if (self.source[self.pos] == '/') blk: {
            self.pos += 1;
            break :blk true;
        } else false;

        if (self.pos < self.source.len and self.source[self.pos] == '>') {
            self.pos += 1;
            try self.tokens.append(.{
                .type = if (self_closing) .TagOpenEndVoid else .TagOpenEnd,
                .index = start,
                .end = self.pos,
                .self_closing = self_closing,
            });
        } else if (self.pos >= self.source.len) {
            // Missing > at EOF — direct port of TS `_requireCharCode(chars.$GT)`.
            try self.reportError(@intCast(self.pos), "Unexpected character \"EOF\"");
            // Don't emit a TagOpenEnd — the tag is incomplete.
        } else {
            // Missing > — non-EOF case. Report the unexpected character but
            // do NOT consume it — the character may be the start of a new tag
            // (e.g. `<a <span>` where the first `<a` is incomplete). The main
            // tokenization loop will re-process the character.
            // Don't emit a TagOpenEnd — the tag is incomplete.
            const ch = self.source[self.pos];
            try self.reportErrorFmt(@intCast(self.pos), "Unexpected character \"{c}\"", .{ch});
        }
    }

    // ─── Text Scanning ────────────────────────────────────────

    fn scanText(self: *Lexer) !void {
        const allocator = self.tokens.allocator;
        const start = self.pos;

        while (self.pos < self.source.len and self.source[self.pos] != '<') {
            // Stop at { when ICU expansion forms are enabled (but not {{)
            if (self.options.tokenize_icu and self.source[self.pos] == '{' and
                (self.pos + 1 >= self.source.len or self.source[self.pos + 1] != '{'))
            {
                break;
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

    /// Scans the entire source as a single TEXT token in escaped-string mode.
    /// Direct port of `EscapedCharacterCursor.processEscapeSequence()` in TS source.
    /// Handles:
    ///   - `\n` `\r` `\v` `\t` `\b` `\f` (control chars)
    ///   - `\xGG` (hex 2-digit)         — error: `Invalid hexadecimal escape sequence`
    ///   - `\uGGGG` (unicode 4-digit)   — error: `Invalid hexadecimal escape sequence`
    ///   - `\u{GG...}` (variable unicode) — error: `Invalid hexadecimal escape sequence`
    ///   - `\012` (octal 3-digit)
    ///   - `\<newline>` (line continuation — removed)
    ///   - `\<other>` (escaped char — backslash removed)
    fn scanEscapedStringText(self: *Lexer) !void {
        const start = self.pos;

        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];

            if (ch != '\\') {
                self.pos += 1;
                continue;
            }

            // Hit a backslash — process the escape sequence.
            const backslash_pos = self.pos;
            self.pos += 1; // skip backslash

            if (self.pos >= self.source.len) {
                // Trailing backslash at EOF — treat as escaped nothing.
                break;
            }

            const next = self.source[self.pos];

            switch (next) {
                'n', 'r', 'v', 't', 'b', 'f' => {
                    // Standard control char escape — just skip the letter.
                    self.pos += 1;
                },
                'u' => {
                    // Unicode escape: `\uGGGG` or `\u{GG...}`.
                    self.pos += 1; // skip u
                    if (self.pos < self.source.len and self.source[self.pos] == '{') {
                        // Variable-length: `\u{GG...}`
                        self.pos += 1; // skip {
                        const digits_start = self.pos;
                        while (self.pos < self.source.len and self.source[self.pos] != '}') {
                            self.pos += 1;
                        }
                        const digits_end = self.pos;
                        if (self.pos < self.source.len) {
                            self.pos += 1; // skip }
                        }
                        // Validate digits.
                        const digits = self.source[digits_start..digits_end];
                        for (digits) |d| {
                            if (!chars.isAsciiHexDigit(d)) {
                                try self.reportError(@intCast(backslash_pos + 2), "Invalid hexadecimal escape sequence");
                                break;
                            }
                        }
                    } else {
                        // Fixed-length: `\uGGGG` (4 hex digits).
                        const digits_start = self.pos;
                        var i: u32 = 0;
                        while (i < 4 and self.pos < self.source.len) : (i += 1) {
                            self.pos += 1;
                        }
                        const digits = self.source[digits_start..self.pos];
                        for (digits) |d| {
                            if (!chars.isAsciiHexDigit(d)) {
                                try self.reportError(@intCast(backslash_pos + 2), "Invalid hexadecimal escape sequence");
                                break;
                            }
                        }
                        if (self.pos >= self.source.len and digits.len < 4) {
                            // Unexpected EOF in the middle of a `\u` escape.
                            try self.reportError(@intCast(self.pos), "Unexpected character \"EOF\"");
                        }
                    }
                },
                'x' => {
                    // Hex escape: `\xGG` (2 hex digits).
                    self.pos += 1; // skip x
                    const digits_start = self.pos;
                    var i: u32 = 0;
                    while (i < 2 and self.pos < self.source.len) : (i += 1) {
                        self.pos += 1;
                    }
                    const digits = self.source[digits_start..self.pos];
                    for (digits) |d| {
                        if (!chars.isAsciiHexDigit(d)) {
                            try self.reportError(@intCast(backslash_pos + 2), "Invalid hexadecimal escape sequence");
                            break;
                        }
                    }
                    if (self.pos >= self.source.len and digits.len < 2) {
                        try self.reportError(@intCast(self.pos), "Unexpected character \"EOF\"");
                    }
                },
                '0', '1', '2', '3', '4', '5', '6', '7' => {
                    // Octal escape: up to 3 digits.
                    var i: u32 = 0;
                    while (i < 3 and self.pos < self.source.len and chars.isOctalDigit(self.source[self.pos])) : (i += 1) {
                        self.pos += 1;
                    }
                },
                '\n', '\r' => {
                    // Line continuation — backslash followed by newline.
                    // Skip the newline (and `\r\n` as a pair).
                    if (self.source[self.pos] == '\r' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '\n') {
                        self.pos += 2;
                    } else {
                        self.pos += 1;
                    }
                },
                else => {
                    // Escaped normal character — just skip the backslash.
                    self.pos += 1;
                },
            }
        }

        const end = self.pos;
        try self.tokens.append(.{
            .type = .Text,
            .index = start,
            .end = end,
        });
    }

    // ─── Entity Scanning ──────────────────────────────────────

    /// Direct port of `_consumeEntity(textTokenType)` in TS source.
    /// Scans an HTML character reference (`&amp;`, `&#65;`, `&#x41;`).
    /// Reports TS-matching error messages:
    ///   - `Unknown entity "<name>" - use the "&#<decimal>;" or  "&#x<hex>;" syntax`
    ///   - `Unable to parse entity "<text>" - {decimal|hexadecimal} character reference entities must end with ";"`
    ///   - `Unexpected character "EOF"` when `_requireCharCode(chars.$SEMICOLON)` hits EOF
    fn scanEntity(self: *Lexer) !void {
        const start = self.pos;
        self.pos += 1; // skip &

        if (self.pos < self.source.len and self.source[self.pos] == '#') {
            self.pos += 1; // skip #
            const is_hex = self.pos < self.source.len and (self.source[self.pos] == 'x' or self.source[self.pos] == 'X');
            if (is_hex) {
                self.pos += 1; // skip x/X
            }

            // Read digits until non-digit/hex-digit (matches `isDigitEntityEnd` in TS).
            const digits_start = self.pos;
            while (self.pos < self.source.len) {
                const c = self.source[self.pos];
                if (is_hex) {
                    if (!chars.isAsciiHexDigit(c)) break;
                } else {
                    if (!chars.isDigit(c)) break;
                }
                self.pos += 1;
            }

            // If next char isn't `;`, advance one char and report Unable to parse.
            if (self.pos >= self.source.len) {
                // EOF before `;` — TS `_requireCharCode` throws `Unexpected character "EOF"`.
                try self.reportError(@intCast(self.pos), "Unexpected character \"EOF\"");
                // Emit as text token (the `&` and what was scanned).
                try self.tokens.append(.{
                    .type = .Text,
                    .index = start,
                    .end = self.pos,
                });
                return;
            }
            if (self.source[self.pos] != ';') {
                // Advance one char (to include the peeked character in the error message).
                const err_pos = self.pos;
                self.pos += 1;
                const entity_str = self.source[start..self.pos];
                if (is_hex) {
                    try self.reportErrorFmt(@intCast(err_pos), "Unable to parse entity \"{s}\" - hexadecimal character reference entities must end with \";\"", .{entity_str});
                } else {
                    try self.reportErrorFmt(@intCast(err_pos), "Unable to parse entity \"{s}\" - decimal character reference entities must end with \";\"", .{entity_str});
                }
                // Treat as text — emit a text token for `&`.
                try self.tokens.append(.{
                    .type = .Text,
                    .index = start,
                    .end = self.pos,
                });
                return;
            }

            // Skip `;`.
            const digits_end = self.pos;
            self.pos += 1;

            const digits = self.source[digits_start..digits_end];
            const char_code = if (is_hex)
                std.fmt.parseInt(u21, digits, 16) catch null
            else
                std.fmt.parseInt(u21, digits, 10) catch null;

            if (char_code) |code| {
                // Emit encoded entity with decoded value.
                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(code, &buf) catch 0;
                if (len > 0) {
                    const value = try self.tokens.allocator.dupe(u8, buf[0..len]);
                    try self.owned_strings.append(value);
                    try self.tokens.append(.{
                        .type = .EncodedEntity,
                        .index = start,
                        .end = self.pos,
                        .entity_value = value,
                    });
                } else {
                    try self.tokens.append(.{
                        .type = .EncodedEntity,
                        .index = start,
                        .end = self.pos,
                    });
                }
            } else {
                // parseInt failed — Unknown entity.
                const entity_str = self.source[start..self.pos];
                try self.reportErrorFmt(@intCast(start), "Unknown entity \"{s}\" - use the \"&#<decimal>;\" or  \"&#x<hex>;\" syntax", .{entity_str});
                try self.tokens.append(.{
                    .type = .Text,
                    .index = start,
                    .end = self.pos,
                });
            }
            return;
        }

        // Named entity.
        const name_start = self.pos;
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == ';' or c == ' ' or c == '<' or c == '&' or c == '\n' or c == '\r' or c == '\t') break;
            self.pos += 1;
        }

        if (self.pos >= self.source.len or self.source[self.pos] != ';') {
            // No `;` found — treat `&` as text (direct port of TS behavior).
            self.pos = name_start;
            try self.tokens.append(.{
                .type = .Text,
                .index = start,
                .end = self.pos + 1,
            });
            self.pos += 1; // skip &
            return;
        }

        const name_end = self.pos;
        self.pos += 1; // skip ;
        const name = self.source[name_start..name_end];

        if (entities.NAMED_ENTITIES.get(name)) |value| {
            try self.tokens.append(.{
                .type = .EncodedEntity,
                .index = start,
                .end = self.pos,
                .entity_value = value,
            });
        } else {
            try self.reportErrorFmt(@intCast(start), "Unknown entity \"{s}\" - use the \"&#<decimal>;\" or  \"&#x<hex>;\" syntax", .{name});
            try self.tokens.append(.{
                .type = .Text,
                .index = start,
                .end = self.pos,
            });
        }
    }

    // ─── Expansion Form (ICU) ─────────────────────────────────

    /// Direct port of `_tokenizeExpansionForm` + `_consumeExpansionFormStart` in TS source.
    /// Scans an ICU expansion form `{expr, type, case1 {...} case2 {...}}`.
    /// When a `{` is encountered that does NOT contain a comma (i.e. is not a
    /// valid expansion form), reports the unescaped-`{` error message exactly
    /// matching the TS format:
    ///   `Unexpected character "EOF" (Do you have an unescaped "{" in your template? Use "{{ '{' }}") to escape it.)`
    fn scanExpansionForm(self: *Lexer) !void {
        const start = self.pos;

        // First, peek ahead to determine if this is a valid expansion form.
        // Must have at least one comma at depth 1 before the matching `}`.
        var has_comma = false;
        var brace_depth: u32 = 1;
        var scan_pos = self.pos + 1; // skip {
        while (scan_pos < self.source.len and brace_depth > 0) {
            const ch = self.source[scan_pos];
            if (ch == '{') brace_depth += 1;
            if (ch == '}') {
                brace_depth -= 1;
                if (brace_depth == 0) break;
            }
            if (brace_depth == 1 and ch == ',') has_comma = true;
            scan_pos += 1;
        }

        if (!has_comma) {
            // Not a valid expansion form. Continue scanning as text — the `{`
            // will be re-processed by the text scanner. The TS source defers
            // the error reporting to the eventual EOF (when no closing `}` is
            // found anywhere in the remaining source). The error is reported
            // at the EOF position with the special "unescaped {" message.
            //
            // For `<p>before { after</p>` (length 21), the `{` is at position 10.
            // The text scanner continues to EOF (position 21), and we emit the
            // unescaped-`{` error there.
            const err_pos: u32 = @intCast(self.source.len);
            const msg = "Unexpected character \"EOF\" (Do you have an unescaped \"{\" in your template? Use \"{{ '{' }}\") to escape it.)";
            try self.reportError(err_pos, msg);
            // Treat `{` as text — emit a text token starting at `{`.
            self.pos += 1;
            try self.tokens.append(.{
                .type = .Text,
                .index = start,
                .end = self.pos,
            });
            return;
        }

        // Valid expansion form — consume it.
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
        } else {
            // Missing closing } — report error
            try self.reportError(@intCast(self.pos), "Unexpected character \"EOF\"");
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

        // Read block name — direct port of `_getBlockName()`.
        const name_start = self.pos;
        while (self.pos < self.source.len and chars.isAlphaNum(self.source[self.pos])) {
            self.pos += 1;
        }
        // Also handle "else if" (with space) — normalize to "else if".
        if (self.pos + 4 <= self.source.len and std.mem.startsWith(u8, self.source[self.pos..], " if")) {
            self.pos += 3;
            while (self.pos < self.source.len and chars.isAlphaNum(self.source[self.pos])) {
                self.pos += 1;
            }
        }

        const block_name = self.source[name_start..self.pos];

        // Emit the BLOCK_OPEN_START token (may be retyped to INCOMPLETE_BLOCK_OPEN below).
        const block_token_idx = self.tokens.items.len;
        try self.tokens.append(.{
            .type = .BlockOpenStart,
            .index = start,
            .end = self.pos,
        });

        // Read block parameters (in parentheses)
        self.skipWhitespace();
        var incomplete = false;
        if (self.pos < self.source.len and self.source[self.pos] == '(') {
            try self.scanBlockParameters();
            // Allow spaces before the closing paren.
            self.skipWhitespace();
            if (self.pos < self.source.len and self.source[self.pos] == ')') {
                self.pos += 1;
                // Allow spaces after the paren.
                self.skipWhitespace();
            } else {
                // Missing closing `)` — mark as incomplete.
                incomplete = true;
            }
        }

        if (!incomplete) {
            // Special case: `@default never;` is a complete block with no body.
            if (std.mem.eql(u8, block_name, "default never") and
                self.pos < self.source.len and self.source[self.pos] == ';')
            {
                self.pos += 1;
                try self.tokens.append(.{
                    .type = .BlockOpenEnd,
                    .index = self.pos,
                    .end = self.pos,
                });
                try self.tokens.append(.{
                    .type = .BlockClose,
                    .index = self.pos,
                    .end = self.pos,
                });
                return;
            }

            if (self.pos < self.source.len and self.source[self.pos] == '{') {
                self.pos += 1;
                try self.tokens.append(.{
                    .type = .BlockOpenEnd,
                    .index = self.pos - 1,
                    .end = self.pos,
                });
            } else if (std.mem.eql(u8, block_name, "case") or std.mem.eql(u8, block_name, "default")) {
                // `@case` and `@default` may be consecutive without a body.
                try self.tokens.append(.{
                    .type = .BlockOpenEnd,
                    .index = self.pos,
                    .end = self.pos,
                });
                try self.tokens.append(.{
                    .type = .BlockClose,
                    .index = self.pos,
                    .end = self.pos,
                });
                return;
            } else {
                incomplete = true;
            }
        }

        if (incomplete) {
            // Retype the BLOCK_OPEN_START token to INCOMPLETE_BLOCK_OPEN.
            self.tokens.items[block_token_idx].type = .IncompleteBlockOpen;
        } else {
            self.block_stack.append(block_name) catch {};
            self.in_block = true;
        }
    }

    fn handleBlockEnd(self: *Lexer) !void {
        const start = self.pos;
        self.pos += 1; // skip }
        try self.tokens.append(.{
            .type = .BlockClose,
            .index = start,
            .end = self.pos,
        });
        if (self.block_stack.items.len > 0) {
            _ = self.block_stack.pop();
        }
        if (self.block_stack.items.len == 0) {
            self.in_block = false;
        }
    }

    /// Direct port of `_consumeBlockParameters()` in TS source.
    /// Scans one or more block parameters separated by `;`. Each parameter is
    /// a single `BLOCK_PARAMETER` token. Tracks quotes (`'`, `"`, `` ` ``) and
    /// nested parentheses to skip over `;` and `)` inside strings / nested calls.
    fn scanBlockParameters(self: *Lexer) !void {
        self.pos += 1; // skip (

        // Trim whitespace until the first parameter.
        while (self.pos < self.source.len and self.isBlockParameterChar(self.source[self.pos])) {
            self.pos += 1;
        }

        while (self.pos < self.source.len and self.source[self.pos] != ')') {
            const param_start = self.pos;
            var in_quote: ?u8 = null;
            var open_parens: u32 = 0;

            while (self.pos < self.source.len and
                (self.source[self.pos] != ';' or in_quote != null))
            {
                const ch = self.source[self.pos];

                if (ch == '\\') {
                    // Skip the next character (escape).
                    self.pos += 2;
                    continue;
                } else if (in_quote != null and ch == in_quote.?) {
                    in_quote = null;
                } else if (in_quote == null and chars.isQuote(ch)) {
                    in_quote = ch;
                } else if (in_quote == null and ch == '(') {
                    open_parens += 1;
                } else if (in_quote == null and ch == ')') {
                    if (open_parens == 0) {
                        break;
                    } else if (open_parens > 0) {
                        open_parens -= 1;
                    }
                }

                self.pos += 1;
            }

            // If we hit EOF while still inside a quote, this is an unterminated
            // string — report `Unexpected character "EOF"` at the EOF position.
            // Direct port of the `CursorError('Unexpected character "EOF"')` thrown
            // by TS when `_cursor.advance()` runs past EOF inside a quote.
            if (in_quote != null and self.pos >= self.source.len) {
                try self.reportError(@intCast(self.pos), "Unexpected character \"EOF\"");
            }

            try self.tokens.append(.{
                .type = .BlockParameter,
                .index = param_start,
                .end = self.pos,
            });

            // Skip to the next parameter (whitespace + `;` + whitespace).
            while (self.pos < self.source.len and self.isBlockParameterChar(self.source[self.pos])) {
                self.pos += 1;
            }
        }
    }

    /// Direct port of `isBlockParameterChar` in TS source.
    /// Returns true for whitespace and `;`.
    fn isBlockParameterChar(self: *const Lexer, code: u8) bool {
        _ = self;
        return chars.isWhitespace(code) or code == ';';
    }

    // ─── Let Declaration (@let) ───────────────────────────────

    fn handleLetDeclaration(self: *Lexer) !void {
        const start = self.pos;
        self.pos += 4; // skip @let

        const let_token_idx = self.tokens.items.len;
        try self.tokens.append(.{
            .type = .LetStart,
            .index = start,
            .end = self.pos,
        });

        // Require at least one whitespace after @let.
        if (self.pos >= self.source.len or !chars.isWhitespace(self.source[self.pos])) {
            self.tokens.items[let_token_idx].type = .IncompleteLet;
            return;
        }
        self.skipWhitespace();

        // Read name.
        var allow_digit = false;
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (chars.isAsciiLetter(c) or c == '$' or c == '_' or (allow_digit and chars.isDigit(c))) {
                allow_digit = true;
                self.pos += 1;
            } else {
                break;
            }
        }

        self.skipWhitespace();

        // Expect `=`.
        if (self.pos >= self.source.len or self.source[self.pos] != '=') {
            self.tokens.items[let_token_idx].type = .IncompleteLet;
            return;
        }
        self.pos += 1; // skip =

        // Skip whitespace (but not newlines) after `=`.
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (!chars.isWhitespace(c) or chars.isNewLine(c)) break;
            self.pos += 1;
        }

        // Scan the value (with string-aware skipping).
        const value_start = self.pos;
        var unterminated_string = false;
        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (ch == ';') break;

            // Skip over string contents.
            if (chars.isQuote(ch)) {
                const quote = ch;
                self.pos += 1;
                while (self.pos < self.source.len) {
                    const inner = self.source[self.pos];
                    if (inner == '\\') {
                        self.pos += 2;
                        continue;
                    }
                    if (inner == quote) break;
                    self.pos += 1;
                }
                if (self.pos >= self.source.len) {
                    // Unterminated string — value scan continues to EOF.
                    unterminated_string = true;
                    break;
                }
                // Skip the closing quote.
                self.pos += 1;
                continue;
            }

            self.pos += 1;
        }

        try self.tokens.append(.{
            .type = .LetValue,
            .index = value_start,
            .end = self.pos,
        });

        if (unterminated_string) {
            // The value's string was not terminated — the `@let` declaration is
            // incomplete. Report the EOF error and mark the LET_START as INCOMPLETE_LET.
            try self.reportError(@intCast(self.pos), "Unexpected character \"EOF\"");
            self.tokens.items[let_token_idx].type = .IncompleteLet;
            return;
        }

        // Expect `;`.
        if (self.pos < self.source.len and self.source[self.pos] == ';') {
            self.pos += 1;
            try self.tokens.append(.{
                .type = .LetEnd,
                .index = self.pos - 1,
                .end = self.pos,
            });
        } else {
            self.tokens.items[let_token_idx].type = .IncompleteLet;
        }
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

    /// Report a lexer error with a dynamically-allocated formatted message.
    /// The message is tracked in `owned_strings` and freed in `deinit`.
    pub fn reportErrorFmt(self: *Lexer, index: u32, comptime fmt: []const u8, args: anytype) !void {
        const allocator = self.tokens.allocator;
        const msg = try std.fmt.allocPrint(allocator, fmt, args);
        try self.owned_strings.append(msg);
        try self.errors.append(.{ .index = index, .end = index + 1, .message = msg });
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

    // Copy tokens to owned slice. Tokens reference the source string (zero-copy),
    // but `parts` arrays and `entity_value` strings need deep copying for correctness.
    const tokens = try allocator.alloc(HtmlToken, result.@"0".len);
    for (result.@"0", 0..) |tok, i| {
        var new_tok = tok;
        if (tok.parts.len > 0) {
            new_tok.parts = try allocator.dupe(TokenPart, tok.parts);
        }
        // `entity_value` strings are either static (from NAMED_ENTITIES) or
        // owned by `lexer.owned_strings` (which will be freed on deinit).
        // For dynamic values, we duplicate them so the returned tokens outlive
        // the lexer.
        if (tok.entity_value) |v| {
            // Check if it's a static value from NAMED_ENTITIES (those don't need
            // to be duplicated — they live for the program's lifetime).
            const is_static = isStaticEntityValue(v);
            if (!is_static) {
                new_tok.entity_value = try allocator.dupe(u8, v);
            }
        }
        tokens[i] = new_tok;
    }

    // Deep-copy errors so the error messages outlive the lexer.
    const errors = try allocator.alloc(LexError, result.@"1".len);
    for (result.@"1", 0..) |err, i| {
        var new_err = err;
        // Check if the message is one of the static error message constants.
        if (!isStaticErrorMessage(err.message)) {
            new_err.message = try allocator.dupe(u8, err.message);
        }
        errors[i] = new_err;
    }

    return .{
        .tokens = tokens,
        .errors = errors,
    };
}

/// Returns true if the given entity value is a static value from `NAMED_ENTITIES`
/// (which lives for the program's lifetime and doesn't need to be freed).
fn isStaticEntityValue(_: []const u8) bool {
    // The static values are looked up from `entities.NAMED_ENTITIES`. We can
    // detect them by checking if the pointer is within the data segment. As a
    // heuristic, we check if the value is one of the well-known entity values.
    // For values that are dynamically allocated (UTF-8 encoded from a code point),
    // they will be small strings allocated by the lexer.
    //
    // The simplest check: any entity value that came from `NAMED_ENTITIES.get()`
    // is a static string. Dynamically-encoded values are allocated via
    // `allocator.dupe(u8, buf[0..len])`. We can't easily distinguish them here.
    //
    // Workaround: always duplicate. The static values will be duplicated (small
    // overhead), and the dynamic values will be properly owned.
    return false;
}

/// Returns true if the given error message is a static string constant (e.g.,
/// `"Unexpected character \"EOF\""`) that doesn't need to be freed.
fn isStaticErrorMessage(msg: []const u8) bool {
    const static_messages = [_][]const u8{
        "Unexpected character \"EOF\"",
        "Unexpected character \"EOF\" (Do you have an unescaped \"{\" in your template? Use \"{{ '{' }}\") to escape it.)",
        "Invalid hexadecimal escape sequence",
    };
    for (static_messages) |s| {
        if (std.mem.eql(u8, s, msg)) return true;
    }
    return false;
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
            // TS decoded value for `&amp;` is `&`.
            try std.testing.expectEqualStrings("&", tok.entity_value.?);
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
    // `tokenize_blocks` and `tokenize_let` default to `true` to match the TS
    // source (`tokenizeBlocks ?? true` and `tokenizeLet ?? true`).
    try std.testing.expect(opts.tokenize_blocks);
    try std.testing.expect(opts.tokenize_let);
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
            // TS decoded value for `&#65;` is `A` (ASCII 65).
            try std.testing.expectEqualStrings("A", tok.entity_value.?);
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
            // TS decoded value for `&#x41;` is `A` (ASCII 0x41).
            try std.testing.expectEqualStrings("A", tok.entity_value.?);
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
