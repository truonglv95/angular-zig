/// ML Parser Tokens — Token types for HTML/XML lexing
///
/// Port of: compiler/src/ml_parser/tokens.ts (320 LoC)
const std = @import("std");

/// Token types for HTML/XML lexing.
pub const TokenType = enum(u8) {
    TagOpenStart,
    TagOpenEnd,
    TagCloseStart,
    TagCloseEnd,
    TagName,
    AttributeName,
    AttributeValue,
    Text,
    Comment,
    DocType,
    Cdata,
    Expansion,
    ExpansionCase,
    Block,
    BlockParameter,
    EOF,
};

/// A token from the HTML/XML lexer.
pub const Token = struct {
    type: TokenType,
    index: u32,
    end: u32,
    parts: []const TokenPart = &.{},
    self_closing: bool = false,
    /// Interpolation boundaries within text tokens.
    pub const TokenPart = struct {
        start: u32,
        end: u32,
        is_expression: bool,
    };

    pub fn slice(self: Token, source: []const u8) []const u8 {
        if (self.end <= source.len and self.index <= self.end) {
            return source[self.index..self.end];
        }
        return "";
    }
};

/// Interpolated attribute token (contains interpolation boundaries).
pub const InterpolatedAttributeToken = struct {
    base: Token,
    interpolation_parts: []const Token.TokenPart,
};

/// Interpolated text token (contains interpolation boundaries).
pub const InterpolatedTextToken = struct {
    base: Token,
    interpolation_parts: []const Token.TokenPart,
};
