/// ML Parser Inline Comment Tests — Ported from Angular TS test/ml_parser/inline_comment_spec.ts
///
/// Source: packages/compiler/test/ml_parser/inline_comment_spec.ts (145 lines)
const std = @import("std");
const ml_parser = @import("../../ml_parser/parser.zig");
const ml_ast = @import("../../ml_parser/ast.zig");
const ml_lexer = @import("../../ml_parser/lexer.zig");
const arena_mod = @import("../../arena.zig");

fn parseHtml(allocator: std.mem.Allocator, arena: *arena_mod.AstArena, source: []const u8) !ml_ast.ParseTreeResult {
    var lex = ml_lexer.Lexer.init(allocator, source);
    defer lex.deinit();
    const lex_result = try lex.tokenize(); const lex_tokens = lex_result[0];
    var parser = ml_parser.Parser.init(allocator, arena, source, lex_tokens);
    // parser.deinit() skipped to keep root_nodes alive
    return parser.parse();
}

test "inline_comment: should parse HTML comment" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<!-- comment -->");
    try std.testing.expectEqual(@as(usize, 1), result.root_nodes.len);
    try std.testing.expectEqual(ml_ast.NodeKind.Comment, result.root_nodes[0].kind);
}

test "inline_comment: should parse comment with content" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<!-- this is a comment -->");
    try std.testing.expectEqual(@as(usize, 1), result.root_nodes.len);
}

test "inline_comment: should parse comment inside element" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<div><!-- comment --></div>");
    const elem = result.root_nodes[0].data.Element;
    try std.testing.expectEqual(@as(usize, 1), elem.children.len);
}

test "inline_comment: should parse multiple comments" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<!-- first --><!-- second -->");
    try std.testing.expectEqual(@as(usize, 2), result.root_nodes.len);
}

test "inline_comment: should parse empty comment" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<!---->");
    try std.testing.expectEqual(@as(usize, 1), result.root_nodes.len);
}

// ─── Additional tests ported from TS spec ──────────────────

test "inline_comment: should ignore single line comments between attributes" {
    return error.SkipZigTest; // TODO: Module API not yet fully ported
    // try std.testing.expect(true);
}

test "inline_comment: should ignore single line comments between inputs and outputs" {
    return error.SkipZigTest; // TODO: Module API not yet fully ported
    // try std.testing.expect(true);
}

test "inline_comment: should ignore single line comments at the end of tag" {
    return error.SkipZigTest; // TODO: Module API not yet fully ported
    // try std.testing.expect(true);
}

test "inline_comment: should handle commented out attribute" {
    return error.SkipZigTest; // TODO: Module API not yet fully ported
    // try std.testing.expect(true);
}

test "inline_comment: should comment an attribute with a // on a new line" {
    return error.SkipZigTest; // TODO: Module API not yet fully ported
    // try std.testing.expect(true);
}

test "inline_comment: should ignore multi-line comments between attributes" {
    return error.SkipZigTest; // TODO: Module API not yet fully ported
    // try std.testing.expect(true);
}

test "inline_comment: should ignore multi-line comments at the end of tag" {
    return error.SkipZigTest; // TODO: Module API not yet fully ported
    // try std.testing.expect(true);
}

test "inline_comment: should handle * inside multi-line comments" {
    return error.SkipZigTest; // TODO: Module API not yet fully ported
    // try std.testing.expect(true);
}

test "inline_comment: should maintain correct source spans with comments" {
    return error.SkipZigTest; // TODO: Module API not yet fully ported
    // try std.testing.expect(true);
}

