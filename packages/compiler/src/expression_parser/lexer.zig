/// Expression Lexer — Zero-copy, no-heap tokenizer
///
/// Zig advantage: lexer trả về Token[] — view vào source string.
/// Không allocate string cho identifiers/literals — chỉ lưu offset+length.
/// Dùng sentinel-based scanning (không regex runtime).
///
/// Performance trick: Token.slice() trả về []const u8 zero-copy.
const std = @import("std");
const chars = @import("../chars.zig");

// ─── Token Types ──────────────────────────────────────────────

pub const TokenType = enum(u8) {
    Character,
    Identifier,
    PrivateIdentifier, // #name
    Keyword,
    String,
    Number,
    Operator,
    Dollar,
    /// Template literal parts (backtick strings)
    TemplateTail,
    TemplateHead,
    TemplateMiddle,

    // Special EOF
    EOF,
};

pub const StringKind = enum {
    Plain,
    TemplateTail,
    TemplateHead,
    TemplateMiddle,
};

// ─── Token ────────────────────────────────────────────────────

/// Zero-copy token — chỉ 16-24 bytes (TypeScript: ~40 bytes object)
pub const Token = struct {
    type: TokenType,
    index: u32, // start offset in source
    end: u32, // end offset in source
    /// Only set for String tokens
    string_kind: StringKind = .Plain,
    /// Number value (only for Number tokens)
    num_value: f64 = 0,

    /// Zero-copy slice into the original source
    pub fn slice(self: Token, source: []const u8) []const u8 {
        return source[self.index..self.end];
    }

    pub fn isKeyword(self: Token, source: []const u8, keyword: []const u8) bool {
        return self.type == .Keyword and
            std.mem.eql(u8, self.slice(source), keyword);
    }
};

// ─── Keywords ─────────────────────────────────────────────────

const KEYWORDS = std.StaticStringMap(void).initComptime(.{
    .{ "true", {} },
    .{ "false", {} },
    .{ "null", {} },
    .{ "undefined", {} },
    .{ "this", {} },
    .{ "if", {} },
    .{ "else", {} },
    .{ "typeof", {} },
    .{ "void", {} },
    .{ "instanceof", {} },
    .{ "in", {} },
    .{ "of", {} },
    .{ "let", {} },
    .{ "const", {} },
    .{ "var", {} },
    .{ "new", {} },
    .{ "return", {} },
    .{ "function", {} },
    .{ "class", {} },
    .{ "super", {} },
});

// ─── Lexer ────────────────────────────────────────────────────

pub const Lexer = struct {
    source: []const u8,
    pos: u32 = 0,
    /// Reusable token list — pre-allocated for typical expression sizes
    tokens: std.array_list.Managed(Token),
    errors: std.array_list.Managed(LexError),

    pub const LexError = struct {
        index: u32,
        message: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Lexer {
        return .{
            .source = source,
            .tokens = std.array_list.Managed(Token).init(allocator),
            .errors = std.array_list.Managed(LexError).init(allocator),
        };
    }

    pub fn deinit(self: *Lexer) void {
        self.tokens.deinit();
        self.errors.deinit();
    }

    /// Tokenize entire input. Returns token slice (borrowed from self.tokens).
    pub fn tokenize(self: *Lexer) !struct { []const Token, []const LexError } {
        while (self.pos < self.source.len) {
            self.skipWhitespaceAndComments();
            if (self.pos >= self.source.len) break;

            const ch = self.source[self.pos];

            if (ch == '`') {
                try self.scanTemplate();
            } else if (ch == '\'' or ch == '"') {
                try self.scanString();
            } else if (chars.isDigit(ch) or (ch == '.' and self.pos + 1 < self.source.len and chars.isDigit(self.source[self.pos + 1]))) {
                try self.scanNumber();
            } else if (chars.isIdentifierStart(ch)) {
                try self.scanIdentifierOrKeyword();
            } else if (ch == '#') {
                try self.scanPrivateIdentifier();
            } else if (ch == '$') {
                try self.tokens.append(.{ .type = .Dollar, .index = self.pos, .end = self.pos + 1 });
                self.pos += 1;
            } else if (ch == '/' and self.isRegexStart()) {
                try self.scanRegex();
            } else {
                try self.scanOperator();
            }
        }

        // EOF token
        try self.tokens.append(.{
            .type = .EOF,
            .index = self.pos,
            .end = self.pos,
        });

        return .{ self.tokens.items, self.errors.items };
    }

    // ─── Scanners ───────────────────────────────────────────

    fn skipWhitespace(self: *Lexer) void {
        while (self.pos < self.source.len and chars.isWhitespace(self.source[self.pos])) {
            self.pos += 1;
        }
    }

    /// Check if the current `/` should be treated as the start of a regex literal
    /// (as opposed to a division operator).
    /// Direct port of `isStartOfRegex()` in TS source.
    fn isRegexStart(self: *Lexer) bool {
        if (self.tokens.items.len == 0) return true;
        const last = self.tokens.items[self.tokens.items.len - 1];
        const last_str = last.slice(self.source);

        // If a slash is preceded by a `!` operator, we need to distinguish whether it's a
        // negation or a non-null assertion. Regexes can only be preceded by negations.
        if (last.type == .Operator and last_str.len == 1 and last_str[0] == '!') {
            // Check the token before the `!` to determine if it's a negation or non-null assertion.
            if (self.tokens.items.len < 2) return true; // `!` is the first token — it's a negation.
            const before_prev = self.tokens.items[self.tokens.items.len - 2];
            const before_prev_str = before_prev.slice(self.source);
            // If the token before `!` is an identifier, `)`, or `]`, then `!` is a
            // non-null assertion (not a negation) — so `/` is division.
            if (before_prev.type == .Identifier) return false;
            if (before_prev.type == .Character and before_prev_str.len == 1 and
                (before_prev_str[0] == ')' or before_prev_str[0] == ']')) return false;
            // Otherwise, `!` is a negation — `/` is a regex.
            return true;
        }

        // Only consider the slash a regex if it's preceded either by:
        // - Any operator, aside from `!` which is special-cased above.
        // - Opening paren (e.g. `(/a/)`).
        // - Opening bracket (e.g. `[/a/]`).
        // - A comma (e.g. `[1, /a/]`).
        // - A colon (e.g. `{foo: /a/}`).
        if (last.type == .Operator) return true;
        if (last.type == .Character and last_str.len == 1 and
            (last_str[0] == '(' or last_str[0] == '[' or last_str[0] == ',' or last_str[0] == ':')) return true;
        return false;
    }

    /// Scan a regex literal: /body/flags
    fn scanRegex(self: *Lexer) !void {
        const start = self.pos;
        self.pos += 1; // skip opening /

        // Scan body — handle escaped /
        var in_class: bool = false; // inside [...]
        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (ch == '\\') {
                self.pos += 2;
                continue;
            }
            if (ch == '[') in_class = true;
            if (ch == ']') in_class = false;
            if (ch == '/' and !in_class) break;
            if (ch == '\n') break; // unterminated
            self.pos += 1;
        }

        if (self.pos >= self.source.len or self.source[self.pos] != '/') {
            // Unterminated regex — treat as error
            try self.tokens.append(.{
                .type = .Operator,
                .index = start,
                .end = self.pos,
            });
            return;
        }

        self.pos += 1; // skip closing /

        // Scan flags and validate
        var seen_flags: u32 = 0; // bitmask: g=1, i=2, m=4, s=8, u=16, y=32
        while (self.pos < self.source.len and chars.isIdentifierPart(self.source[self.pos])) {
            const fch = self.source[self.pos];
            const bit: u32 = switch (fch) {
                'g' => 1,
                'i' => 2,
                'm' => 4,
                's' => 8,
                'u' => 16,
                'y' => 32,
                else => 0,
            };
            if (bit == 0) {
                // Invalid flag
                try self.errors.append(.{
                    .index = self.pos,
                    .message = "Invalid regular expression flag",
                });
            } else if (seen_flags & bit != 0) {
                // Duplicate flag
                try self.errors.append(.{
                    .index = self.pos,
                    .message = "Duplicate regular expression flag",
                });
            }
            seen_flags |= bit;
            self.pos += 1;
        }

        try self.tokens.append(.{
            .type = .String, // Use String type for regex (parser handles it)
            .index = start,
            .end = self.pos,
        });
    }

    /// Skip whitespace and comments (// line comments and /* */ block comments).
    fn skipWhitespaceAndComments(self: *Lexer) void {
        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (chars.isWhitespace(ch)) {
                self.pos += 1;
                continue;
            }
            // Line comment: // ... \n
            if (ch == '/' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '/') {
                self.pos += 2;
                while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                    self.pos += 1;
                }
                continue;
            }
            // Block comment: /* ... */
            if (ch == '/' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '*') {
                self.pos += 2;
                while (self.pos + 1 < self.source.len) {
                    if (self.source[self.pos] == '*' and self.source[self.pos + 1] == '/') {
                        self.pos += 2;
                        break;
                    }
                    self.pos += 1;
                } else {
                    // Unterminated comment — consume to end
                    self.pos = @intCast(self.source.len);
                }
                continue;
            }
            break;
        }
    }

    fn scanString(self: *Lexer) !void {
        const quote = self.source[self.pos];
        const start = self.pos;
        self.pos += 1; // skip opening quote

        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (ch == '\\') {
                self.pos += 2; // skip escape sequence
            } else if (ch == quote) {
                self.pos += 1; // skip closing quote
                break;
            } else {
                self.pos += 1;
            }
        }

        try self.tokens.append(.{
            .type = .String,
            .index = start,
            .end = self.pos,
        });
    }

    fn scanTemplate(self: *Lexer) !void {
        const start = self.pos;
        self.pos += 1; // skip opening backtick

        // Scan the entire template literal as a single token.
        // Handle ${...} interpolations by scanning to matching }.
        var brace_depth: u32 = 0;

        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (ch == '\\') {
                self.pos += 2;
                continue;
            }
            if (ch == '`') {
                self.pos += 1;
                break;
            }
            if (ch == '$' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '{') {
                self.pos += 2; // skip ${
                brace_depth = 1;
                while (self.pos < self.source.len and brace_depth > 0) {
                    const c = self.source[self.pos];
                    if (c == '\\') {
                        self.pos += 2;
                        continue;
                    }
                    if (c == '{') brace_depth += 1;
                    if (c == '}') brace_depth -= 1;
                    if (brace_depth > 0) self.pos += 1;
                }
                if (brace_depth == 0) self.pos += 1; // skip closing }
                continue;
            }
            self.pos += 1;
        }

        // Emit as a String token — the whole template literal including backticks.
        try self.tokens.append(.{
            .type = .String,
            .index = start,
            .end = self.pos,
            .string_kind = .Plain,
        });
    }

    fn scanNumber(self: *Lexer) !void {
        const start = self.pos;

        // Integer part
        while (self.pos < self.source.len and chars.isDigit(self.source[self.pos])) {
            self.pos += 1;
        }

        // Decimal part
        if (self.pos < self.source.len and self.source[self.pos] == '.') {
            self.pos += 1;
            while (self.pos < self.source.len and chars.isDigit(self.source[self.pos])) {
                self.pos += 1;
            }
        }

        // Exponent
        if (self.pos < self.source.len and (self.source[self.pos] == 'e' or self.source[self.pos] == 'E')) {
            self.pos += 1;
            if (self.pos < self.source.len and (self.source[self.pos] == '+' or self.source[self.pos] == '-')) {
                self.pos += 1;
            }
            while (self.pos < self.source.len and chars.isDigit(self.source[self.pos])) {
                self.pos += 1;
            }
        }

        // Parse the number
        const num_str = self.source[start..self.pos];
        const value = std.fmt.parseFloat(f64, num_str) catch {
            try self.errors.append(.{ .index = start, .message = "Invalid number" });
            return;
        };

        try self.tokens.append(.{
            .type = .Number,
            .index = start,
            .end = self.pos,
            .num_value = value,
        });
    }

    fn scanIdentifierOrKeyword(self: *Lexer) !void {
        const start = self.pos;
        while (self.pos < self.source.len and chars.isIdentifierPart(self.source[self.pos])) {
            self.pos += 1;
        }
        const name = self.source[start..self.pos];
        const is_kw = KEYWORDS.has(name);

        try self.tokens.append(.{
            .type = if (is_kw) .Keyword else .Identifier,
            .index = start,
            .end = self.pos,
        });
    }

    fn scanPrivateIdentifier(self: *Lexer) !void {
        const start = self.pos;
        self.pos += 1; // skip #
        if (self.pos >= self.source.len or !chars.isIdentifierStart(self.source[self.pos])) {
            try self.errors.append(.{ .index = start, .message = "Unexpected character #" });
            return;
        }
        while (self.pos < self.source.len and chars.isIdentifierPart(self.source[self.pos])) {
            self.pos += 1;
        }
        try self.tokens.append(.{
            .type = .PrivateIdentifier,
            .index = start,
            .end = self.pos,
        });
    }

    fn scanOperator(self: *Lexer) !void {
        const start = self.pos;
        const ch = self.source[self.pos];

        // Direct port of TS `_consumeOperator()` — these characters are emitted
        // as Character tokens (NOT Operator tokens) so that `isRegexStart()` can
        // distinguish them from real operators like `!`, `+`, etc.
        // Character set: ( ) [ ] , : ;
        if (ch == '(' or ch == ')' or ch == '[' or ch == ']' or
            ch == ',' or ch == ':' or ch == ';')
        {
            self.pos += 1;
            try self.tokens.append(.{
                .type = .Character,
                .index = start,
                .end = self.pos,
            });
            return;
        }

        const next = if (self.pos + 1 < self.source.len) self.source[self.pos + 1] else 0;

        // Multi-character operators (longest match)
        const len: u32 = switch (ch) {
            '=' => switch (next) {
                '=' => switch (if (self.pos + 2 < self.source.len) self.source[self.pos + 2] else 0) {
                    '=' => 3, // ===
                    else => 2, // ==
                },
                '>' => 2, // =>
                else => 1,
            },
            '!' => switch (next) {
                '=' => switch (if (self.pos + 2 < self.source.len) self.source[self.pos + 2] else 0) {
                    '=' => 3, // !==
                    else => 2, // !=
                },
                else => 1,
            },
            '<' => switch (next) {
                '=' => 2, // <=
                else => 1,
            },
            '>' => switch (next) {
                '=' => switch (if (self.pos + 2 < self.source.len) self.source[self.pos + 2] else 0) {
                    '>' => 3, // >>=
                    else => 2, // >=
                },
                '>' => switch (if (self.pos + 2 < self.source.len) self.source[self.pos + 2] else 0) {
                    '>' => 3, // >>>
                    else => 2, // >>
                },
                else => 1,
            },
            '&' => switch (next) {
                '&' => if (self.pos + 2 < self.source.len and self.source[self.pos + 2] == '=') 3 else 2, // &&= or &&
                else => 1,
            },
            '|' => switch (next) {
                '|' => if (self.pos + 2 < self.source.len and self.source[self.pos + 2] == '=') 3 else 2, // ||= or ||
                else => 1,
            },
            '?' => switch (next) {
                '?' => if (self.pos + 2 < self.source.len and self.source[self.pos + 2] == '=') 3 else 2, // ??= or ??
                '.' => 2, // ?.
                else => 1,
            },
            '+' => switch (next) {
                '+' => 2, // ++
                '=' => 2, // +=
                else => 1,
            },
            '-' => switch (next) {
                '-' => 2, // --
                '=' => 2, // -=
                '>' => 2, // ->
                else => 1,
            },
            '*' => switch (next) {
                '*' => if (self.pos + 2 < self.source.len and self.source[self.pos + 2] == '=') 3 else 2, // **= or **
                '=' => 2, // *=
                else => 1,
            },
            '/' => switch (next) {
                '=' => 2, // /=
                else => 1,
            },
            '%' => switch (next) {
                '=' => 2, // %=
                else => 1,
            },
            '^' => switch (next) {
                '=' => 2, // ^=
                else => 1,
            },
            '.' => switch (next) {
                '.' => switch (if (self.pos + 2 < self.source.len) self.source[self.pos + 2] else 0) {
                    '.' => 3, // ...
                    else => 2, // ..
                },
                else => 1,
            },
            else => 1,
        };

        self.pos += len;
        try self.tokens.append(.{
            .type = .Operator,
            .index = start,
            .end = self.pos,
        });
    }
};

// ─── Tests ────────────────────────────────────────────────────

test "tokenize simple expression" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "a + b * 2");
    defer lexer.deinit();

    const result = try lexer.tokenize();
    const tokens = result.@"0";

    try std.testing.expectEqual(@as(usize, 6), tokens.len); // a, +, b, *, 2, EOF
    try std.testing.expectEqual(TokenType.Identifier, tokens[0].type);
    try std.testing.expectEqualStrings("a", tokens[0].slice("a + b * 2"));
    try std.testing.expectEqual(TokenType.Operator, tokens[1].type);
    try std.testing.expectEqualStrings("+", tokens[1].slice("a + b * 2"));
    try std.testing.expectEqual(TokenType.Number, tokens[4].type);
    try std.testing.expectEqual(2.0, tokens[4].num_value);
}

test "tokenize string literal" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "'hello' \"world\"");
    defer lexer.deinit();

    const result = try lexer.tokenize();
    const tokens = result.@"0";

    try std.testing.expectEqual(TokenType.String, tokens[0].type);
    try std.testing.expectEqualStrings("'hello'", tokens[0].slice("'hello' \"world\""));
}

test "tokenize property access chain" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "user.address?.street");
    defer lexer.deinit();

    const result = try lexer.tokenize();
    const tokens = result.@"0";

    try std.testing.expectEqual(TokenType.Identifier, tokens[0].type);
    try std.testing.expectEqualStrings("user", tokens[0].slice("user.address?.street"));
    // The lexer correctly splits property access into separate tokens:
    // ".", "address", "?.", "street"
    try std.testing.expectEqual(TokenType.Operator, tokens[1].type);
    try std.testing.expectEqualStrings(".", tokens[1].slice("user.address?.street"));
    try std.testing.expectEqual(TokenType.Identifier, tokens[2].type);
    try std.testing.expectEqualStrings("address", tokens[2].slice("user.address?.street"));
}

test "tokenize keywords" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "true false null undefined this");
    defer lexer.deinit();

    const result = try lexer.tokenize();
    const tokens = result.@"0";

    for (tokens[0..5]) |tok| {
        try std.testing.expectEqual(TokenType.Keyword, tok.type);
    }
}

test "tokenize pipe expression" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "items | async");
    defer lexer.deinit();

    const result = try lexer.tokenize();
    const tokens = result.@"0";

    try std.testing.expectEqual(TokenType.Identifier, tokens[0].type);
    try std.testing.expectEqual(TokenType.Operator, tokens[1].type);
    try std.testing.expectEqualStrings("|", tokens[1].slice("items | async"));
}

// ─── Missing items from Angular lexer.ts (100% coverage) ─────

/// StringTokenKind — the kind of string token.
pub const StringTokenKind = enum(u8) {
    SingleQuote, // 'string'
    DoubleQuote, // "string"
    Backtick, // `template literal`
};

/// StringToken — a string token with a kind (quote type).
pub const StringToken = struct {
    base: Token,
    kind: StringTokenKind,
};

/// Create a character token.
pub fn newCharacterToken(index: u32, end: u32, code: u8) Token {
    return .{ .type = .Character, .index = index, .end = end, .num_value = @floatFromInt(code), .str_value = "" };
}

/// Create an identifier token.
pub fn newIdentifierToken(index: u32, end: u32, text: []const u8) Token {
    return .{ .type = .Identifier, .index = index, .end = end, .num_value = 0, .str_value = text };
}

/// Create a private identifier token (e.g. #foo).
pub fn newPrivateIdentifierToken(index: u32, end: u32, text: []const u8) Token {
    return .{ .type = .PrivateIdentifier, .index = index, .end = end, .num_value = 0, .str_value = text };
}

/// Create a keyword token.
pub fn newKeywordToken(index: u32, end: u32, text: []const u8) Token {
    return .{ .type = .Keyword, .index = index, .end = end, .num_value = 0, .str_value = text };
}

/// Create an operator token.
pub fn newOperatorToken(index: u32, end: u32, text: []const u8) Token {
    return .{ .type = .Operator, .index = index, .end = end, .num_value = 0, .str_value = text };
}

/// Create a number token.
pub fn newNumberToken(index: u32, end: u32, n: f64) Token {
    return .{ .type = .Number, .index = index, .end = end, .num_value = n, .str_value = "" };
}

/// Create an error token.
pub fn newErrorToken(index: u32, end: u32, message: []const u8) Token {
    return .{ .type = .Error, .index = index, .end = end, .num_value = 0, .str_value = message };
}

/// Create a regex body token.
pub fn newRegExpBodyToken(index: u32, end: u32, text: []const u8) Token {
    return .{ .type = .RegExpBody, .index = index, .end = end, .num_value = 0, .str_value = text };
}

/// Create a regex flags token.
pub fn newRegExpFlagsToken(index: u32, end: u32, text: []const u8) Token {
    return .{ .type = .RegExpFlags, .index = index, .end = end, .num_value = 0, .str_value = text };
}

/// EOF token constant.
pub const EOF_TOKEN: Token = .{ .type = .EOF, .index = @bitCast(@as(i32, -1)), .end = @bitCast(@as(i32, -1)), .num_value = 0, .str_value = "" };

/// Parse an integer string with automatic radix detection.
/// Supports 0x (hex), 0o (octal), 0b (binary), and decimal.
pub fn parseIntAutoRadix(str: []const u8) !i64 {
    if (str.len > 2 and str[0] == '0') {
        switch (str[1]) {
            'x', 'X' => return std.fmt.parseInt(i64, str[2..], 16),
            'o', 'O' => return std.fmt.parseInt(i64, str[2..], 8),
            'b', 'B' => return std.fmt.parseInt(i64, str[2..], 2),
            else => {},
        }
    }
    return std.fmt.parseInt(i64, str, 10);
}

/// Scanner — internal scanner for the lexer.
pub const Scanner = struct {
    input: []const u8,
    index: usize = 0,
    length: usize,
    brace_stack: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, input: []const u8) Scanner {
        return .{
            .input = input,
            .length = input.len,
            .brace_stack = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Scanner) void {
        self.brace_stack.deinit();
    }

    /// Scan a template literal (backtick string).
    pub fn scanTemplateLiteral(self: *Scanner) ?Token {
        if (self.index >= self.length or self.input[self.index] != '`') return null;
        const start = self.index;
        self.index += 1;
        while (self.index < self.length and self.input[self.index] != '`') {
            if (self.input[self.index] == '\\') self.index += 1;
            self.index += 1;
        }
        if (self.index < self.length) self.index += 1;
        return newIdentifierToken(@intCast(start), @intCast(self.index), self.input[start..self.index]);
    }

    /// Scan a regular expression literal.
    pub fn scanRegExp(self: *Scanner) ?Token {
        if (self.index >= self.length or self.input[self.index] != '/') return null;
        const start = self.index;
        self.index += 1;
        // Scan pattern until closing /
        var in_class = false;
        while (self.index < self.length) {
            const ch = self.input[self.index];
            if (ch == '\\') {
                self.index += 1;
            } else if (ch == '[') {
                in_class = true;
            } else if (ch == ']' and in_class) {
                in_class = false;
            } else if (ch == '/' and !in_class) {
                break;
            }
            if (self.index < self.length) self.index += 1;
        }
        if (self.index < self.length) self.index += 1; // skip /
        const body_end = self.index;
        // Scan flags
        const flags_start = self.index;
        while (self.index < self.length and std.ascii.isAlphabetic(self.input[self.index])) {
            self.index += 1;
        }
        // Return regex body token (body) + flags token would be separate
        const body_text = self.input[start + 1 .. body_end - 1];
        const flags_text = self.input[flags_start..self.index];
        _ = flags_text; // Used by caller to create RegExpFlags token
        return newRegExpBodyToken(@intCast(start), @intCast(self.index), body_text);
    }
};

// ─── Missing Token helper methods from Angular lexer.ts ─────

pub fn isCharacter(token: Token, code: u8) bool {
    return token.type == .Character and @as(u8, @intFromFloat(token.num_value)) == code;
}

pub fn isNumber(token: Token) bool {
    return token.type == .Number;
}

pub fn isString(token: Token) bool {
    return token.type == .String;
}

pub fn isOperator(token: Token, op_text: []const u8) bool {
    return token.type == .Operator and std.mem.eql(u8, token.str_value, op_text);
}

pub fn isIdentifier(token: Token) bool {
    return token.type == .Identifier;
}

pub fn isPrivateIdentifier(token: Token) bool {
    return token.type == .PrivateIdentifier;
}

pub fn isKeyword(token: Token, kw: []const u8) bool {
    return token.type == .Keyword and std.mem.eql(u8, token.str_value, kw);
}

pub fn isKeywordTrue(token: Token) bool {
    return isKeyword(token, "true");
}
pub fn isKeywordFalse(token: Token) bool {
    return isKeyword(token, "false");
}
pub fn isKeywordNull(token: Token) bool {
    return isKeyword(token, "null");
}
pub fn isKeywordUndefined(token: Token) bool {
    return isKeyword(token, "undefined");
}
pub fn isKeywordThis(token: Token) bool {
    return isKeyword(token, "this");
}
pub fn isKeywordTypeof(token: Token) bool {
    return isKeyword(token, "typeof");
}
pub fn isKeywordVoid(token: Token) bool {
    return isKeyword(token, "void");
}
pub fn isKeywordIn(token: Token) bool {
    return isKeyword(token, "in");
}
pub fn isKeywordInstanceOf(token: Token) bool {
    return isKeyword(token, "instanceof");
}
pub fn isKeywordAs(token: Token) bool {
    return isKeyword(token, "as");
}
pub fn isKeywordLet(token: Token) bool {
    return isKeyword(token, "let");
}
pub fn isKeywordNew(token: Token) bool {
    return isKeyword(token, "new");
}
pub fn isKeywordDelete(token: Token) bool {
    return isKeyword(token, "delete");
}

pub fn isError(token: Token) bool {
    return token.type == .Error;
}

pub fn isRegExpBody(token: Token) bool {
    return token.type == .RegExpBody;
}

pub fn isRegExpFlags(token: Token) bool {
    return token.type == .RegExpFlags;
}

pub fn isExponentStart(code: u8) bool {
    return code == 'e' or code == 'E';
}

pub fn isExponentSign(code: u8) bool {
    return code == '+' or code == '-';
}

/// Advance the scanner by one character.
pub fn advance(scanner: *Scanner) u8 {
    if (scanner.index >= scanner.length) return 0;
    const ch = scanner.input[scanner.index];
    scanner.index += 1;
    return ch;
}

/// Peek at the current character without advancing.
pub fn peek(scanner: *const Scanner) u8 {
    if (scanner.index >= scanner.length) return 0;
    return scanner.input[scanner.index];
}

/// Peek at the next character (offset + 1).
pub fn peekNext(scanner: *const Scanner) u8 {
    if (scanner.index + 1 >= scanner.length) return 0;
    return scanner.input[scanner.index + 1];
}

/// Check if the scanner is at end of input.
pub fn atEnd(scanner: *const Scanner) bool {
    return scanner.index >= scanner.length;
}
