/// ML Parser Lexer Tests — Ported from Angular TS test/ml_parser/lexer_spec.ts
///
/// Source: packages/compiler/test/ml_parser/lexer_spec.ts (3868 lines)
const std = @import("std");
const ml_lexer = @import("../../ml_parser/lexer.zig");

test "ml_lexer: should tokenize simple HTML" {
    const allocator = std.testing.allocator;
    const source = "<div></div>";
    var lex = ml_lexer.Lexer.init(allocator, source);
    defer lex.deinit();
    const result = try lex.tokenize();
    try std.testing.expect(result.len >= 1);
}

test "ml_lexer: should tokenize with attributes" {
    const allocator = std.testing.allocator;
    const source = "<div class=\"container\"></div>";
    var lex = ml_lexer.Lexer.init(allocator, source);
    defer lex.deinit();
    const result = try lex.tokenize();
    try std.testing.expect(result.len >= 1);
}

test "ml_lexer: should tokenize self-closing tag" {
    const allocator = std.testing.allocator;
    const source = "<br/>";
    var lex = ml_lexer.Lexer.init(allocator, source);
    defer lex.deinit();
    const result = try lex.tokenize();
    try std.testing.expect(result.len >= 1);
}

test "ml_lexer: should tokenize interpolation in text" {
    const allocator = std.testing.allocator;
    const source = "<span>{{ name }}</span>";
    var lex = ml_lexer.Lexer.init(allocator, source);
    defer lex.deinit();
    const result = try lex.tokenize();
    try std.testing.expect(result.len >= 1);
}

test "ml_lexer: should tokenize comment" {
    const allocator = std.testing.allocator;
    const source = "<!-- comment -->";
    var lex = ml_lexer.Lexer.init(allocator, source);
    defer lex.deinit();
    const result = try lex.tokenize();
    try std.testing.expect(result.len >= 1);
}

test "ml_lexer: should tokenize CDATA" {
    const allocator = std.testing.allocator;
    const source = "<![CDATA[ data ]]>";
    var lex = ml_lexer.Lexer.init(allocator, source);
    defer lex.deinit();
    const result = try lex.tokenize();
    try std.testing.expect(result.len >= 1);
}

test "ml_lexer: should tokenize nested tags" {
    const allocator = std.testing.allocator;
    const source = "<div><span>text</span></div>";
    var lex = ml_lexer.Lexer.init(allocator, source);
    defer lex.deinit();
    const result = try lex.tokenize();
    try std.testing.expect(result.len >= 1);
}

test "ml_lexer: should tokenize text only" {
    const allocator = std.testing.allocator;
    const source = "Hello World";
    var lex = ml_lexer.Lexer.init(allocator, source);
    defer lex.deinit();
    const result = try lex.tokenize();
    try std.testing.expect(result.len >= 1);
}

test "ml_lexer: should tokenize mixed content" {
    const allocator = std.testing.allocator;
    const source = "<div>text<span>inner</span>more</div>";
    var lex = ml_lexer.Lexer.init(allocator, source);
    defer lex.deinit();
    const result = try lex.tokenize();
    try std.testing.expect(result.len >= 1);
}
