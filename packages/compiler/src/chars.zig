/// Character constants and predicates
///
/// Port of: compiler/src/chars.ts (104 LoC) — 100% match
const std = @import("std");

// ASCII character codes
pub const DOLLAR_EOF: u8 = 0;
pub const DOLLAR_BSPACE: u8 = 8;
pub const DOLLAR_TAB: u8 = 9;
pub const DOLLAR_LF: u8 = 10;
pub const DOLLAR_VTAB: u8 = 11;
pub const DOLLAR_FF: u8 = 12;
pub const DOLLAR_CR: u8 = 13;
pub const DOLLAR_SPACE: u8 = 32;
pub const DOLLAR_BANG: u8 = 33;
pub const DOLLAR_DQ: u8 = 34;
pub const DOLLAR_HASH: u8 = 35;
pub const DOLLAR_SIGN: u8 = 36;
pub const DOLLAR_PERCENT: u8 = 37;
pub const DOLLAR_AMPERSAND: u8 = 38;
pub const DOLLAR_SQ: u8 = 39;
pub const DOLLAR_LPAREN: u8 = 40;
pub const DOLLAR_RPAREN: u8 = 41;
pub const DOLLAR_STAR: u8 = 42;
pub const DOLLAR_PLUS: u8 = 43;
pub const DOLLAR_COMMA: u8 = 44;
pub const DOLLAR_MINUS: u8 = 45;
pub const DOLLAR_PERIOD: u8 = 46;
pub const DOLLAR_SLASH: u8 = 47;
pub const DOLLAR_COLON: u8 = 58;
pub const DOLLAR_SEMICOLON: u8 = 59;
pub const DOLLAR_LT: u8 = 60;
pub const DOLLAR_EQ: u8 = 61;
pub const DOLLAR_GT: u8 = 62;
pub const DOLLAR_QUESTION: u8 = 63;
pub const DOLLAR_AT: u8 = 64;

pub const DOLLAR_0: u8 = 48;
pub const DOLLAR_7: u8 = 55;
pub const DOLLAR_9: u8 = 57;

pub const DOLLAR_A: u8 = 65;
pub const DOLLAR_E: u8 = 69;
pub const DOLLAR_F: u8 = 70;
pub const DOLLAR_X: u8 = 88;
pub const DOLLAR_Z: u8 = 90;

pub const DOLLAR_LBRACKET: u8 = 91;
pub const DOLLAR_BACKSLASH: u8 = 92;
pub const DOLLAR_RBRACKET: u8 = 93;
pub const DOLLAR_CARET: u8 = 94;
pub const DOLLAR__: u8 = 95;

pub const DOLLAR_a: u8 = 97;
pub const DOLLAR_b: u8 = 98;
pub const DOLLAR_e: u8 = 101;
pub const DOLLAR_f: u8 = 102;
pub const DOLLAR_n: u8 = 110;
pub const DOLLAR_r: u8 = 114;
pub const DOLLAR_t: u8 = 116;
pub const DOLLAR_u: u8 = 117;
pub const DOLLAR_v: u8 = 118;
pub const DOLLAR_x: u8 = 120;
pub const DOLLAR_z: u8 = 122;

pub const DOLLAR_LBRACE: u8 = 123;
pub const DOLLAR_BAR: u8 = 124;
pub const DOLLAR_RBRACE: u8 = 125;
pub const DOLLAR_NBSP: u8 = 160;

pub const DOLLAR_PIPE: u8 = 124;
pub const DOLLAR_TILDA: u8 = 126;
pub const DOLLAR_BT: u8 = 96;

pub fn isWhitespace(code: u8) bool {
    return (code >= DOLLAR_TAB and code <= DOLLAR_SPACE) or code == DOLLAR_NBSP;
}

pub fn isDigit(code: u8) bool {
    return DOLLAR_0 <= code and code <= DOLLAR_9;
}

pub fn isAsciiLetter(code: u8) bool {
    return (code >= DOLLAR_a and code <= DOLLAR_z) or (code >= DOLLAR_A and code <= DOLLAR_Z);
}

pub fn isAsciiHexDigit(code: u8) bool {
    return (code >= DOLLAR_a and code <= DOLLAR_f) or (code >= DOLLAR_A and code <= DOLLAR_F) or isDigit(code);
}

pub fn isNewLine(code: u8) bool {
    return code == DOLLAR_LF or code == DOLLAR_CR;
}

pub fn isOctalDigit(code: u8) bool {
    return DOLLAR_0 <= code and code <= DOLLAR_7;
}

pub fn isQuote(code: u8) bool {
    return code == DOLLAR_SQ or code == DOLLAR_DQ or code == DOLLAR_BT;
}

// Additional helpers used in the Zig port
pub fn isTagNameChar(code: u8) bool {
    return isAsciiLetter(code) or isDigit(code) or code == 95 or code == DOLLAR_MINUS or code == DOLLAR_COLON;
}

pub fn isSelectorChar(code: u8) bool {
    return isAsciiLetter(code) or isDigit(code) or code == 95 or code == DOLLAR_MINUS;
}

pub fn isAlphaNum(code: u8) bool {
    return isAsciiLetter(code) or isDigit(code);
}

pub fn toLower(code: u8) u8 {
    if (code >= DOLLAR_A and code <= DOLLAR_Z) return code + 32;
    return code;
}

pub fn toUpper(code: u8) u8 {
    if (code >= DOLLAR_a and code <= DOLLAR_z) return code - 32;
    return code;
}
pub fn isIdentifierStart(code: u8) bool { return isAsciiLetter(code) or code == DOLLAR_SIGN or code == 95; }
pub fn isIdentifierPart(code: u8) bool { return isAsciiLetter(code) or isDigit(code) or code == DOLLAR_SIGN or code == 95; }
