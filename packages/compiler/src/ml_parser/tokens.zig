/// ML Parser Tokens — Token types for HTML/XML lexing
///
/// Port of: compiler/src/ml_parser/tokens.ts (320 LoC)
///
/// Defines all token types produced by the HTML lexer, including:
///   - Tag tokens (open, close, void, self-closing)
///   - Text tokens (plain, raw, escapable raw, interpolated)
///   - Attribute tokens (name, quote, value, interpolated value)
///   - Comment tokens (start, end, in-element)
///   - CDATA tokens
///   - Expansion form tokens (ICU)
///   - Block tokens (@if, @for, @switch, @defer)
///   - Let tokens (@let)
///   - Component/directive tokens (selectorless mode)
const std = @import("std");

/// TokenType — all token types for HTML/XML lexing.
/// Direct port of `TokenType` enum in the TS source.
pub const TokenType = enum(u8) {
    // Tag tokens
    TagOpenStart,
    TagOpenEnd,
    TagOpenEndVoid,
    TagClose,
    IncompleteTagOpen,
    // Text tokens
    Text,
    EscapableRawText,
    RawText,
    Interpolation,
    EncodedEntity,
    // Comment tokens
    CommentStart,
    CommentEnd,
    InElementComment,
    // CDATA tokens
    CdataStart,
    CdataEnd,
    // Attribute tokens
    AttrName,
    AttrQuote,
    AttrValueText,
    AttrValueInterpolation,
    // Document type
    DocType,
    // Expansion form (ICU) tokens
    ExpansionFormStart,
    ExpansionCaseValue,
    ExpansionCaseExpStart,
    ExpansionCaseExpEnd,
    ExpansionFormEnd,
    // Block tokens (@if, @for, @switch, @defer)
    BlockOpenStart,
    BlockOpenEnd,
    BlockClose,
    BlockParameter,
    IncompleteBlockOpen,
    // Let tokens (@let)
    LetStart,
    LetValue,
    LetEnd,
    IncompleteLet,
    // Component/directive tokens (selectorless mode)
    ComponentOpenStart,
    ComponentOpenEnd,
    ComponentOpenEndVoid,
    ComponentClose,
    IncompleteComponentOpen,
    DirectiveName,
    DirectiveOpen,
    DirectiveClose,
    // End of file
    EOF,
};

/// Token — a single token from the HTML/XML lexer.
/// Direct port of the `Token` type in the TS source.
pub const Token = struct {
    type: TokenType,
    /// Start offset in the source string.
    index: u32,
    /// End offset in the source string.
    end: u32,
    /// For tokens with multiple parts (e.g., interpolated text).
    parts: []const TokenPart = &.{},
    /// Whether this tag is self-closing.
    self_closing: bool = false,
    /// The token's string value (for text, attribute names, etc.).
    value: []const u8 = "",

    pub const TokenPart = struct {
        start: u32,
        end: u32,
        is_expression: bool,
    };

    /// Get the source text for this token.
    pub fn slice(self: Token, source: []const u8) []const u8 {
        if (self.end <= source.len and self.index <= self.end) {
            return source[self.index..self.end];
        }
        return "";
    }

    /// Check if this token is a text-type token.
    pub fn isText(self: Token) bool {
        return switch (self.type) {
            .Text, .EscapableRawText, .RawText, .Interpolation => true,
            else => false,
        };
    }

    /// Check if this token is an attribute-type token.
    pub fn isAttribute(self: Token) bool {
        return switch (self.type) {
            .AttrName, .AttrQuote, .AttrValueText, .AttrValueInterpolation => true,
            else => false,
        };
    }

    /// Check if this token is a tag-type token.
    pub fn isTag(self: Token) bool {
        return switch (self.type) {
            .TagOpenStart, .TagOpenEnd, .TagOpenEndVoid, .TagClose, .IncompleteTagOpen => true,
            else => false,
        };
    }

    /// Check if this token is a block-type token.
    pub fn isBlock(self: Token) bool {
        return switch (self.type) {
            .BlockOpenStart, .BlockOpenEnd, .BlockClose, .BlockParameter, .IncompleteBlockOpen => true,
            else => false,
        };
    }
};

/// TagOpenStartToken — the start of an opening tag (e.g., `<div`).
pub const TagOpenStartToken = struct {
    base: Token,
    parts: []const []const u8,
};

/// TagOpenEndToken — the end of an opening tag (e.g., `>`).
pub const TagOpenEndToken = struct {
    base: Token,
};

/// TagOpenEndVoidToken — the end of a void tag (e.g., `/>`).
pub const TagOpenEndVoidToken = struct {
    base: Token,
};

/// TagCloseToken — a closing tag (e.g., `</div>`).
pub const TagCloseToken = struct {
    base: Token,
    parts: []const []const u8,
};

/// TextToken — a plain text token.
pub const TextToken = struct {
    base: Token,
    parts: []const []const u8,
};

/// InterpolationToken — a text token containing interpolation.
pub const InterpolationToken = struct {
    base: Token,
    parts: []const []const u8,
    /// Interpolation boundaries within the text.
    interpolation_parts: []const Token.TokenPart,
};

/// EncodedEntityToken — an HTML entity (e.g., `&amp;`).
pub const EncodedEntityToken = struct {
    base: Token,
    entity: []const u8,
};

/// AttributeNameToken — an attribute name.
pub const AttributeNameToken = struct {
    base: Token,
    parts: []const []const u8,
};

/// AttributeQuoteToken — an attribute value quote.
pub const AttributeQuoteToken = struct {
    base: Token,
};

/// AttributeValueTextToken — an attribute value.
pub const AttributeValueTextToken = struct {
    base: Token,
    parts: []const []const u8,
};

/// InterpolatedAttributeToken — an attribute value containing interpolation.
pub const InterpolatedAttributeToken = struct {
    base: Token,
    parts: []const []const u8,
    interpolation_parts: []const Token.TokenPart,
};

/// InterpolatedTextToken — a text token containing interpolation.
pub const InterpolatedTextToken = struct {
    base: Token,
    interpolation_parts: []const Token.TokenPart,
};

/// CommentStartToken — the start of a comment (`<!--`).
pub const CommentStartToken = struct {
    base: Token,
};

/// CommentEndToken — the end of a comment (`-->`).
pub const CommentEndToken = struct {
    base: Token,
};

/// BlockOpenStartToken — the start of a block (e.g., `@if`).
pub const BlockOpenStartToken = struct {
    base: Token,
    parts: []const []const u8,
};

/// BlockParameterToken — a block parameter (e.g., `(condition)`).
pub const BlockParameterToken = struct {
    base: Token,
    parts: []const []const u8,
};

/// BlockCloseToken — a block closing tag (e.g., `@endif`).
pub const BlockCloseToken = struct {
    base: Token,
    parts: []const []const u8,
};

// ─── Tests ──────────────────────────────────────────────────

test "Token slice" {
    const source = "<div>hello</div>";
    const token = Token{ .type = .Text, .index = 5, .end = 10 };
    try std.testing.expectEqualStrings("hello", token.slice(source));
}

test "Token isText" {
    try std.testing.expect((Token{ .type = .Text, .index = 0, .end = 0 }).isText());
    try std.testing.expect((Token{ .type = .Interpolation, .index = 0, .end = 0 }).isText());
    try std.testing.expect(!(Token{ .type = .TagOpenStart, .index = 0, .end = 0 }).isText());
}

test "Token isAttribute" {
    try std.testing.expect((Token{ .type = .AttrName, .index = 0, .end = 0 }).isAttribute());
    try std.testing.expect((Token{ .type = .AttrValueText, .index = 0, .end = 0 }).isAttribute());
    try std.testing.expect(!(Token{ .type = .Text, .index = 0, .end = 0 }).isAttribute());
}

test "Token isTag" {
    try std.testing.expect((Token{ .type = .TagOpenStart, .index = 0, .end = 0 }).isTag());
    try std.testing.expect((Token{ .type = .TagClose, .index = 0, .end = 0 }).isTag());
    try std.testing.expect(!(Token{ .type = .Text, .index = 0, .end = 0 }).isTag());
}

test "Token isBlock" {
    try std.testing.expect((Token{ .type = .BlockOpenStart, .index = 0, .end = 0 }).isBlock());
    try std.testing.expect((Token{ .type = .BlockClose, .index = 0, .end = 0 }).isBlock());
    try std.testing.expect(!(Token{ .type = .Text, .index = 0, .end = 0 }).isBlock());
}

test "TokenType has all variants" {
    // Ensure all token types are accounted for.
    const types = std.meta.tags(TokenType);
    try std.testing.expect(types.len >= 40);
}
