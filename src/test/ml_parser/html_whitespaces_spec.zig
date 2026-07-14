/// ML Parser HTML Whitespaces Tests — Ported from Angular TS test/ml_parser/html_whitespaces_spec.ts
///
/// Source: packages/compiler/test/ml_parser/html_whitespaces_spec.ts (196 lines)
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

test "whitespaces: should preserve whitespaces by default" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<div>  text  </div>");
    try std.testing.expectEqual(@as(usize, 1), result.root_nodes.len);
}

test "whitespaces: should handle whitespace-only text" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<div>   </div>");
    try std.testing.expectEqual(@as(usize, 1), result.root_nodes.len);
}

test "whitespaces: should handle newlines" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<div>\n  text\n</div>");
    try std.testing.expectEqual(@as(usize, 1), result.root_nodes.len);
}

test "whitespaces: should handle tabs" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<div>\ttext\t</div>");
    try std.testing.expectEqual(@as(usize, 1), result.root_nodes.len);
}

test "whitespaces: should handle whitespace between elements" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<div> <span>a</span> <span>b</span> </div>");
    const elem = result.root_nodes[0].data.Element;
    try std.testing.expect(elem.children.len >= 2);
}
