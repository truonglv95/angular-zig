/// Character classification — comptime optimized
///
/// Thay vì runtime string operations, dùng comptime const arrays
/// cho character lookups. Zig compiler inline toàn bộ thành direct comparisons.
const std = @import("std");

/// Whitespaces theo Angular parser spec
pub const WHITESPACES = " \t\n\r\x0c";

/// Categorized character sets — comptime computed
pub const CharCategory = enum {
    whitespace,
    digit,
    letter,
    identifier_start,
    identifier_part,
    operator,
    none,
};

/// comptime lookup table cho whitespace — O(1) check
pub fn isWhitespace(ch: u8) bool {
    return switch (ch) {
        ' ', '\t', '\n', '\r', '\x0c' => true,
        else => false,
    };
}

pub fn isDigit(ch: u8) bool {
    return ch >= '0' and ch <= '9';
}

pub fn isAsciiLetter(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z');
}

pub fn isIdentifierStart(ch: u8) bool {
    return isAsciiLetter(ch) or ch == '_' or ch == '$';
}

pub fn isIdentifierPart(ch: u8) bool {
    return isIdentifierStart(ch) or isDigit(ch);
}

/// XML/HTML name character (simplified)
pub fn isTagNameChar(ch: u8) bool {
    return isIdentifierPart(ch) or ch == '-';
}

/// EOF sentinel — Zig convention
pub const EOF: u8 = 0;

// ─── Tests ────────────────────────────────────────────────────

test "character classification" {
    try std.testing.expect(isWhitespace(' '));
    try std.testing.expect(isWhitespace('\n'));
    try std.testing.expect(!isWhitespace('a'));
    try std.testing.expect(isDigit('5'));
    try std.testing.expect(!isDigit('a'));
    try std.testing.expect(isIdentifierStart('$'));
    try std.testing.expect(isIdentifierStart('_'));
    try std.testing.expect(!isIdentifierStart('5'));
    try std.testing.expect(isIdentifierPart('a'));
    try std.testing.expect(isIdentifierPart('5'));
}
