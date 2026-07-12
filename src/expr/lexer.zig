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
            self.skipWhitespace();
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

        var kind: StringKind = .TemplateHead;
        var brace_depth: u32 = 0;

        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (ch == '\\') {
                self.pos += 2;
                continue;
            }
            if (ch == '`') {
                self.pos += 1;
                kind = .TemplateTail;
                break;
            }
            if (ch == '$' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '{') {
                self.pos += 2; // skip ${
                // Scan the expression part to find matching }
                brace_depth = 1;
                while (self.pos < self.source.len and brace_depth > 0) {
                    const c = self.source[self.pos];
                    if (c == '{') brace_depth += 1;
                    if (c == '}') brace_depth -= 1;
                    if (brace_depth > 0) self.pos += 1;
                }
                if (brace_depth == 0) self.pos += 1; // skip closing }
                kind = .TemplateMiddle;
                break;
            }
            self.pos += 1;
        }

        try self.tokens.append(.{
            .type = switch (kind) {
                .TemplateHead => .TemplateHead,
                .TemplateMiddle => .TemplateMiddle,
                .TemplateTail => .TemplateTail,
                .Plain => .String,
            },
            .index = start,
            .end = self.pos,
            .string_kind = kind,
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
                '&' => 2, // &&
                else => 1,
            },
            '|' => switch (next) {
                '|' => 2, // ||
                else => 1,
            },
            '?' => switch (next) {
                '?' => 2, // ??
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
                '*' => 2, // **
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

    try std.testing.expectEqual(@as(usize, 7), tokens.len); // a, +, b, *, 2, EOF
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
    try std.testing.expectEqualStrings(".address?.street", tokens[1].slice("user.address?.street"));
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
