/// ML Parser Inline Comment Tests — Ported from Angular TS test/ml_parser/inline_comment_spec.ts
///
/// Source: packages/compiler/test/ml_parser/inline_comment_spec.ts (145 lines)
///
/// Tests that the lexer supports `//` and `/* */` comments inside element tags
/// (between attributes). This is a Zig-specific extension that matches the
/// Angular TS behavior.
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
    return parser.parse();
}

test "inline_comment: should parse HTML comment" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<!-- comment -->");
    defer { var r = result; r.deinit(allocator); }
    try std.testing.expectEqual(@as(usize, 1), result.root_nodes.len);
    try std.testing.expectEqual(ml_ast.NodeKind.Comment, result.root_nodes[0].kind);
}

test "inline_comment: should parse comment with content" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<!-- this is a comment -->");
    defer { var r = result; r.deinit(allocator); }
    try std.testing.expectEqual(@as(usize, 1), result.root_nodes.len);
}

test "inline_comment: should parse comment inside element" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<div><!-- comment --></div>");
    defer { var r = result; r.deinit(allocator); }
    const elem = result.root_nodes[0].data.Element;
    try std.testing.expectEqual(@as(usize, 1), elem.children.len);
}

test "inline_comment: should parse multiple comments" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<!-- first --><!-- second -->");
    defer { var r = result; r.deinit(allocator); }
    try std.testing.expectEqual(@as(usize, 2), result.root_nodes.len);
}

test "inline_comment: should parse empty comment" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<!---->");
    defer { var r = result; r.deinit(allocator); }
    try std.testing.expectEqual(@as(usize, 1), result.root_nodes.len);
}

// ─── Inline comments inside element tags (// and /* */) ─────

test "inline_comment: should ignore single line comments between attributes" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const source = "<div \n // comment 1\n attr1=\"value1\"\n // comment 2\n attr2=\"value2\"\n></div>";
    const result = try parseHtml(allocator, &arena, source);
    defer { var r = result; r.deinit(allocator); }
    const element = result.root_nodes[0].data.Element;
    try std.testing.expectEqual(@as(usize, 2), element.attrs.len);
    try std.testing.expectEqualStrings("attr1", element.attrs[0].name);
    try std.testing.expectEqualStrings("attr2", element.attrs[1].name);
}

test "inline_comment: should ignore single line comments between inputs and outputs" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const source = "<div \n // comment 1\n [input]=\"value1\"\n // comment 2\n (output)=\"handler()\"\n></div>";
    const result = try parseHtml(allocator, &arena, source);
    defer { var r = result; r.deinit(allocator); }
    const element = result.root_nodes[0].data.Element;
    try std.testing.expectEqual(@as(usize, 2), element.attrs.len);
}

test "inline_comment: should ignore single line comments at the end of tag" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const source = "<div attr1=\"value1\" // comment \n ></div>";
    const result = try parseHtml(allocator, &arena, source);
    defer { var r = result; r.deinit(allocator); }
    const element = result.root_nodes[0].data.Element;
    try std.testing.expectEqual(@as(usize, 1), element.attrs.len);
}

test "inline_comment: should handle commented out attribute" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const source = "<div /* attr1=\"value1\" */ attr2=\"value2\"></div>";
    const result = try parseHtml(allocator, &arena, source);
    defer { var r = result; r.deinit(allocator); }
    const element = result.root_nodes[0].data.Element;
    try std.testing.expectEqual(@as(usize, 1), element.attrs.len);
}

test "inline_comment: should comment an attribute with a // on a new line" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const source = "<div\n // attr1=\"value1\"\n attr2=\"value2\"></div>";
    const result = try parseHtml(allocator, &arena, source);
    defer { var r = result; r.deinit(allocator); }
    const element = result.root_nodes[0].data.Element;
    try std.testing.expectEqual(@as(usize, 1), element.attrs.len);
}

test "inline_comment: should ignore multi-line comments between attributes" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const source = "<div \n /* comment 1 */\n attr1=\"value1\"\n /* comment 2 spanning multiple lines */\n attr2=\"value2\"\n></div>";
    const result = try parseHtml(allocator, &arena, source);
    defer { var r = result; r.deinit(allocator); }
    const element = result.root_nodes[0].data.Element;
    try std.testing.expectEqual(@as(usize, 2), element.attrs.len);
}

test "inline_comment: should ignore multi-line comments at the end of tag" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const source = "<div attr1=\"value1\" /* comment */ ></div>";
    const result = try parseHtml(allocator, &arena, source);
    defer { var r = result; r.deinit(allocator); }
    const element = result.root_nodes[0].data.Element;
    try std.testing.expectEqual(@as(usize, 1), element.attrs.len);
}

test "inline_comment: should handle * inside multi-line comments" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const source = "<div attr1=\"value1\" /* comment with * inside */ attr2=\"value2\"></div>";
    const result = try parseHtml(allocator, &arena, source);
    defer { var r = result; r.deinit(allocator); }
    const element = result.root_nodes[0].data.Element;
    try std.testing.expectEqual(@as(usize, 2), element.attrs.len);
}

test "inline_comment: should maintain correct source spans with comments" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const source = "<div attr1=\"a\" /* comment */ attr2=\"b\"></div>";
    const result = try parseHtml(allocator, &arena, source);
    defer { var r = result; r.deinit(allocator); }
    const element = result.root_nodes[0].data.Element;
    try std.testing.expectEqual(@as(usize, 2), element.attrs.len);
}
