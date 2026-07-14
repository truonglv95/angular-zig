/// ML Parser HTML Parser Tests — Ported from Angular TS test/ml_parser/html_parser_spec.ts
///
/// Source: packages/compiler/test/ml_parser/html_parser_spec.ts (2106 lines)
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
    // Note: parser.deinit() is NOT called here because it frees owned_root_nodes.
    // The parser memory is leaked for the test, which is acceptable.
    return parser.parse();
}

test "html_parser: should parse empty document" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "");
    try std.testing.expectEqual(@as(usize, 0), result.root_nodes.len);
}

test "html_parser: should parse simple element" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<div></div>");
    try std.testing.expectEqual(@as(usize, 1), result.root_nodes.len);
    try std.testing.expectEqual(ml_ast.NodeKind.Element, result.root_nodes[0].kind);
}

test "html_parser: should parse element with text" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<div>Hello</div>");
    const elem = result.root_nodes[0].data.Element;
    try std.testing.expectEqual(@as(usize, 1), elem.children.len);
    try std.testing.expectEqual(ml_ast.NodeKind.Text, elem.children[0].kind);
}

test "html_parser: should parse nested elements" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<div><span>text</span></div>");
    const elem = result.root_nodes[0].data.Element;
    try std.testing.expectEqual(@as(usize, 1), elem.children.len);
    try std.testing.expectEqual(ml_ast.NodeKind.Element, elem.children[0].kind);
    try std.testing.expectEqualStrings("span", elem.children[0].data.Element.name);
}

test "html_parser: should parse self-closing element" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<br/>");
    try std.testing.expectEqual(@as(usize, 1), result.root_nodes.len);
    try std.testing.expect(result.root_nodes[0].data.Element.is_self_closing);
}

test "html_parser: should parse void element" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<br>");
    try std.testing.expectEqual(@as(usize, 1), result.root_nodes.len);
    try std.testing.expect(result.root_nodes[0].data.Element.is_void);
}

test "html_parser: should parse attributes" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<div class=\"container\" id=\"main\"></div>");
    const elem = result.root_nodes[0].data.Element;
    try std.testing.expectEqual(@as(usize, 2), elem.attrs.len);
    try std.testing.expectEqualStrings("class", elem.attrs[0].name);
    try std.testing.expectEqualStrings("container", elem.attrs[0].value);
}

test "html_parser: should parse comment" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<!-- comment -->");
    try std.testing.expectEqual(@as(usize, 1), result.root_nodes.len);
    try std.testing.expectEqual(ml_ast.NodeKind.Comment, result.root_nodes[0].kind);
}

test "html_parser: should parse multiple root elements" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<div></div><span></span>");
    try std.testing.expectEqual(@as(usize, 2), result.root_nodes.len);
}

test "html_parser: should parse deeply nested elements" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<div><span><p><b>deep</b></p></span></div>");
    const div = result.root_nodes[0].data.Element;
    const span = div.children[0].data.Element;
    const p = span.children[0].data.Element;
    const b = p.children[0].data.Element;
    try std.testing.expectEqualStrings("b", b.name);
}

test "html_parser: should parse attribute without value" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<input disabled>");
    const elem = result.root_nodes[0].data.Element;
    try std.testing.expectEqual(@as(usize, 1), elem.attrs.len);
    try std.testing.expectEqualStrings("disabled", elem.attrs[0].name);
}

test "html_parser: should parse mixed content" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<div>text<span>inner</span>more</div>");
    const elem = result.root_nodes[0].data.Element;
    try std.testing.expectEqual(@as(usize, 3), elem.children.len);
}

test "html_parser: should parse siblings" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<div>text1</div><div>text2</div>");
    try std.testing.expectEqual(@as(usize, 2), result.root_nodes.len);
}
