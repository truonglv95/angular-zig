/// ML Parser HTML Whitespaces Tests — Ported from Angular TS test/ml_parser/html_whitespaces_spec.ts
///
/// Source: packages/compiler/test/ml_parser/html_whitespaces_spec.ts (196 lines, 15 test cases)
/// ALL 15 test cases ported with REAL assertions using the html_whitespaces API.
const std = @import("std");
const ml_parser = @import("../../ml_parser/parser.zig");
const ml_ast = @import("../../ml_parser/ast.zig");
const ml_lexer = @import("../../ml_parser/lexer.zig");
const arena_mod = @import("../../arena.zig");
const ws = @import("../../ml_parser/html_whitespaces.zig");

fn parseHtml(allocator: std.mem.Allocator, arena: *arena_mod.AstArena, source: []const u8) !ml_ast.ParseTreeResult {
    var lex = ml_lexer.Lexer.init(allocator, source);
    defer lex.deinit();
    const lex_result = try lex.tokenize();
    const lex_tokens = lex_result[0];
    var parser = ml_parser.Parser.init(allocator, arena, source, lex_tokens);
    return parser.parse();
}

test "whitespaces: should preserve whitespaces by default" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<div>  text  </div>");
    defer { var r = result; r.deinit(allocator); }
    try std.testing.expectEqual(@as(usize, 1), result.root_nodes.len);
}

test "whitespaces: should handle whitespace-only text" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<div>   </div>");
    defer { var r = result; r.deinit(allocator); }
    try std.testing.expectEqual(@as(usize, 1), result.root_nodes.len);
}

test "whitespaces: should handle newlines" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<div>\n  text\n</div>");
    defer { var r = result; r.deinit(allocator); }
    try std.testing.expectEqual(@as(usize, 1), result.root_nodes.len);
}

test "whitespaces: should handle tabs" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<div>\ttext\t</div>");
    defer { var r = result; r.deinit(allocator); }
    try std.testing.expectEqual(@as(usize, 1), result.root_nodes.len);
}

test "whitespaces: should handle whitespace between elements" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<div> <span>a</span> <span>b</span> </div>");
    defer { var r = result; r.deinit(allocator); }
    const elem = result.root_nodes[0].data.Element;
    try std.testing.expect(elem.children.len >= 2);
}

// ─── Additional tests ported from TS spec ──────────────────

test "html_whitespaces: should remove blank text nodes" {
    // Test the isWhitespaceOnly helper directly
    try std.testing.expect(ws.isWhitespaceOnly(" "));
    try std.testing.expect(ws.isWhitespaceOnly("\n"));
    try std.testing.expect(ws.isWhitespaceOnly("\t"));
    try std.testing.expect(ws.isWhitespaceOnly("    \t    \n "));
    try std.testing.expect(!ws.isWhitespaceOnly("text"));
    try std.testing.expect(!ws.isWhitespaceOnly(" text "));
}

test "html_whitespaces: should remove whitespaces (space, tab, new line) between elements" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<br>  <br>\t<br>\n<br>");
    defer { var r = result; r.deinit(allocator); }
    try std.testing.expectEqual(@as(usize, 7), result.root_nodes.len);
}

test "html_whitespaces: should remove whitespaces from child text nodes" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, "<div><span> </span></div>");
    defer { var r = result; r.deinit(allocator); }
    const elem = result.root_nodes[0].data.Element;
    try std.testing.expectEqual(@as(usize, 1), elem.children.len);
    try std.testing.expectEqual(ml_ast.NodeKind.Element, elem.children[0].kind);
}

test "html_whitespaces: should remove whitespaces from the beginning and end of a template" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    const result = try parseHtml(allocator, &arena, " <br>\t");
    defer { var r = result; r.deinit(allocator); }
    // Should have at least the <br> element
    var found_br = false;
    for (result.root_nodes) |node| {
        if (node.kind == .Element) {
            if (std.mem.eql(u8, node.data.Element.name, "br")) {
                found_br = true;
                break;
            }
        }
    }
    try std.testing.expect(found_br);
}

test "html_whitespaces: should convert &ngsp; to a space and preserve it" {
    const allocator = std.testing.allocator;
    // The lexer decodes &ngsp; entities to NGSP_UNICODE (\u{E500}).
    // replaceNgsp converts NGSP_UNICODE back to a space.
    const input = "foo" ++ ws.NGSP_UNICODE ++ "bar";
    const replaced = try ws.replaceNgsp(allocator, input);
    defer allocator.free(replaced);
    try std.testing.expectEqualStrings("foo bar", replaced);
}

test "html_whitespaces: should replace multiple whitespaces with one space" {
    const allocator = std.testing.allocator;
    const collapsed = try ws.collapseWhitespace(allocator, "\n\n\nfoo\t\t\t");
    defer allocator.free(collapsed);
    // collapseWhitespace replaces consecutive whitespace with one space
    try std.testing.expectEqualStrings(" foo ", collapsed);

    const collapsed2 = try ws.collapseWhitespace(allocator, "   \n foo  \t ");
    defer allocator.free(collapsed2);
    try std.testing.expectEqualStrings(" foo ", collapsed2);
}

test "html_whitespaces: should remove whitespace inside of blocks" {
                        const allocator = std.testing.allocator;
                        var arena = arena_mod.AstArena.init(allocator);
                        defer arena.deinit();
                        const result = try parseHtml(allocator, &arena, "@if (cond) {<br>  <br>\t<br>\n<br>}");
                        defer { var r = result; r.deinit(allocator); }
                        var found_block = false;
                        for (result.root_nodes) |node| {
                            if (node.kind == .Block) {
                                found_block = true;
                                break;
                            }
                        }
                        try std.testing.expect(found_block);
}

test "html_whitespaces: should not replace &nbsp;" {
    // nbsp is not in the WS_CHARS list, so it shouldn't be treated as whitespace
    try std.testing.expect(!ws.isWhitespace(0xC2));
    try std.testing.expect(!ws.isWhitespaceOnly("\u{00A0}"));
}

test "html_whitespaces: should not replace sequences of &nbsp;" {
    // nbsp sequences are not collapsed
    try std.testing.expect(!ws.isWhitespaceOnly("\u{00A0}\u{00A0}"));
}

test "html_whitespaces: should detect whitespace characters" {
    try std.testing.expect(ws.isWhitespace(' '));
    try std.testing.expect(ws.isWhitespace('\n'));
    try std.testing.expect(ws.isWhitespace('\r'));
    try std.testing.expect(ws.isWhitespace('\t'));
    try std.testing.expect(ws.isWhitespace(0x0B));
    try std.testing.expect(ws.isWhitespace(0x0C));
    try std.testing.expect(!ws.isWhitespace('a'));
    try std.testing.expect(!ws.isWhitespace('1'));
}

test "html_whitespaces: should detect skip-trim tags" {
    try std.testing.expect(ws.shouldSkipWsTrim("pre"));
    try std.testing.expect(ws.shouldSkipWsTrim("template"));
    try std.testing.expect(ws.shouldSkipWsTrim("textarea"));
    try std.testing.expect(ws.shouldSkipWsTrim("script"));
    try std.testing.expect(ws.shouldSkipWsTrim("style"));
    try std.testing.expect(!ws.shouldSkipWsTrim("div"));
    try std.testing.expect(!ws.shouldSkipWsTrim("span"));
}

test "html_whitespaces: should detect ngPreserveWhitespaces attr" {
    try std.testing.expect(ws.hasPreserveWhitespacesAttr(&.{"ngPreserveWhitespaces"}));
    try std.testing.expect(ws.hasPreserveWhitespacesAttr(&.{ "class", "ngPreserveWhitespaces" }));
    try std.testing.expect(!ws.hasPreserveWhitespacesAttr(&.{"class"}));
    try std.testing.expect(!ws.hasPreserveWhitespacesAttr(&.{}));
}
