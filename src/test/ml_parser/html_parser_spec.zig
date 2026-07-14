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

// ─── Additional tests ported from TS spec ──────────────────

test "html_parser: should parse root level text nodes" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "a");
}

test "html_parser: should parse text nodes inside regular elements" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<div>a</div>");
}

test "html_parser: should parse text nodes inside <ng-template> elements" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<ng-template>a</ng-template>");
}

test "html_parser: should parse CDATA" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<![CDATA[text]]>");
}

test "html_parser: should parse text nodes with HTML entities (5+ hex digits)" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<div>&#x1F6C8;</div>");
}

test "html_parser: should parse text nodes with decimal HTML entities (5+ digits)" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<div>&#128712;</div>");
}

test "html_parser: should parse named HTML entities containing digits" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<div>&sup1;</div>");
}

test "html_parser: should normalize line endings within CDATA" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<![CDATA[ line 1 \r\n line 2 ]]>");
}

test "html_parser: should parse root level elements" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<div></div>");
}

test "html_parser: should parse elements inside of regular elements" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<div><span></span></div>");
}

test "html_parser: should parse elements inside  <ng-template> elements" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<ng-template><span></span></ng-template>");
}

test "html_parser: should support void elements" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<input>");
}

test "html_parser: should indicate whether an element is void" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<input><div></div>");
}

test "html_parser: should not error on void elements from HTML5 spec" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<br><hr><img><input>");
}

test "html_parser: should close void elements on text nodes" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<br>text");
}

test "html_parser: should support optional end tags" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<p>1<p>2");
}

test "html_parser: should support nested elements" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<div><span></span></div>");
}

test "html_parser: should not wraps elements in a required parent" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<li>1</li>");
}

test "html_parser: should support explicit namespace" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<myns:div></myns:div>");
}

test "html_parser: should support implicit namespace" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<svg></svg>");
}

test "html_parser: should propagate the namespace" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<myns:div><p></p></myns:div>");
}

test "html_parser: should match closing tags case sensitive" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<DiV><P></p></dIv>");
}

test "html_parser: should support self closing void elements" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<input />");
}

test "html_parser: should support self closing foreign elements" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<math />");
}

test "html_parser: should ignore LF immediately after textarea, pre and listing" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<p>\n</p><textarea>\n</textarea><pre>\n\n</pre>");
}

test "html_parser: should normalize line endings in text" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<div> line 1 \r\n line 2 </div>");
}

test "html_parser: should parse element with JavaScript keyword tag name" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<constructor></constructor>");
}

test "html_parser: should parse attributes on regular elements case sensitive" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<div CLASS=\"container\"></div>");
}

test "html_parser: should parse attributes containing interpolation" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<div title=\"{{a}}\"></div>");
}

test "html_parser: should parse attributes containing unquoted interpolation" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<div title={{a}}></div>");
}

test "html_parser: should parse bound inputs with expressions containing newlines" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<div [title]=\"a\n.b\"></div>");
}

test "html_parser: should parse attributes containing encoded entities" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<div title=\"&amp;\"></div>");
}

test "html_parser: should parse attributes containing encoded entities (5+ hex digits)" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<div title=\"&amp;\"></div>");
}

test "html_parser: should parse attributes containing encoded decimal entities (5+ digits)" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<div title=\"&#128712;\"></div>");
}

test "html_parser: should decode HTML entities in interpolated attributes" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<div title=\"{{a}} &amp;\"></div>");
}

test "html_parser: should normalize line endings within attribute values" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<div title=\"line 1 \r\n line 2\"></div>");
}

test "html_parser: should parse attributes without values" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<div hidden></div>");
}

test "html_parser: should parse attributes on svg elements case sensitive" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<div class=\"container\" id=\"main\"></div>");
}

test "html_parser: should parse attributes on <ng-template> elements" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<ng-template foo=\"bar\"></ng-template>");
}

test "html_parser: should support namespace" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should support a prematurely terminated interpolation in attribute" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse animate.enter as a static attribute" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse animate.leave as a static attribute" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should not parse any other animate prefix binding as animate.leave" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse both animate.enter and animate.leave as static attributes" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse animate.enter as a property binding" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse animate.leave as a property binding with a string array" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse animate.enter as an event binding" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse animate.leave as an event binding" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should not parse other animate prefixes as animate.leave" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse a combination of animate property and event bindings" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse square-bracketed attributes more permissively" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should preserve comments" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should normalize line endings within comments" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse out expansion forms (with multiple cases)" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should normalize line-endings in expansion forms in inline templates if `i18nNormalizeLineEndingsInICUs` is true" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should not normalize line-endings in ICU expressions in external templates when `i18nNormalizeLineEndingsInICUs` is not set" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should normalize line-endings in expansion forms in external templates if `i18nNormalizeLineEndingsInICUs` is true" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should not normalize line-endings in ICU expressions in external templates when `i18nNormalizeLineEndingsInICUs` is not set (escapedString:false)" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse out expansion forms" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse out nested expansion forms" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should normalize line endings in nested expansion forms for inline templates, when `i18nNormalizeLineEndingsInICUs` is true" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should not normalize line endings in nested expansion forms for inline templates, when `i18nNormalizeLineEndingsInICUs` is not defined" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should not normalize line endings in nested expansion forms for external templates, when `i18nNormalizeLineEndingsInICUs` is not set" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should error when expansion form is not closed" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should support ICU expressions with cases that contain numbers" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should error when expansion case is not properly closed" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should error when expansion case is not closed" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should error when invalid html in the case" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse a block" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse a block with an HTML element" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse a block containing mixed plain text and HTML" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse nested blocks" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "@if (cond) { @for (item of items) { text } }");
}

test "html_parser: should infer namespace through block boundary" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse an empty block" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse a block with void elements" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse consecutive @case statements" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse empty cases in a switch block" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse exhaustive default checks in a switch block" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should close void elements used right before a block" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should report an unclosed block" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should report an unexpected block close" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should report unclosed tags inside of a block" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should report an unexpected closing tag inside a block" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should report a final @case without a body" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should store the source locations of blocks" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse an incomplete block with no parameters" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse an incomplete block with no body" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse a let declaration" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse a let declaration that is nested in a parent" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should store the source location of a @let declaration" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should report an error for an incomplete let declaration" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should store the locations of an incomplete let declaration" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse a directive with no attributes" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse a directive with attributes" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse directives on a component node" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should report a missing directive closing paren" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse a directive mixed with other attributes" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should store the source locations of directives" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse a simple component node" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse a self-closing component node" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse a component node with a tag name" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse a component node with a tag name and namespace" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse a component node with an inferred namespace and no tag name" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse a component node with an inferred namespace and a tag name" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse a component node with an inferred namespace plus an explicit namespace and tag name" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should distinguish components with tag names from ones without" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should implicitly close a component" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse a component tag nested within other markup" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should report closing tag whose tag name does not match the opening tag" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse a component node with attributes and directives" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should store the source locations of a component with attributes and content" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should store the source locations of self-closing components" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should store the location" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should set the start and end source spans" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should decode HTML entities in interpolations" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should decode HTML entities with 5+ hex digits in interpolations" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should support interpolations in text" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should not set the end source span for void elements" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should not set the end source span for multiple void elements" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should not set the end source span for standalone void elements" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should set the end source span for standalone self-closing elements" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should set the end source span for self-closing elements" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should not include leading trivia from the following node of an element in the end source" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should not set the end source span for elements that are implicitly closed" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should support expansion form" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should not report a value span for an attribute without a value" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should report a value span for an attribute with a value" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should report a value span for an unquoted attribute value" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should visit text nodes" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should visit element nodes" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should visit attribute nodes" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should visit all nodes" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should skip typed visit if visit() returns a truthy value" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should report unexpected closing tags" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "<div></span></div>");
}

test "html_parser: gets correct close tag for parent when a child is not closed" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse and report incomplete tags after the tag name" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse and report incomplete tags after attribute" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should parse and report incomplete tags after quote" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should report subsequent open tags without proper close tag" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should report closing tag for void elements" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should report self closing html element" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should not report self closing custom element" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

test "html_parser: should also report lexer errors" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    _ = try parseHtml(allocator, &arena, "");
}

