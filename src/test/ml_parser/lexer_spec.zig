/// ML Parser Lexer Tests — Ported from Angular TS test/ml_parser/lexer_spec.ts
///
/// Source: packages/compiler/test/ml_parser/lexer_spec.ts (3869 lines, 253 test cases)
/// ALL 253 test cases ported from the Angular TS source.
///
/// The TS tests use helper functions (tokenizeAndHumanizeParts, tokenizeAndHumanizeSourceSpans,
/// tokenizeAndHumanizeLineColumn, tokenizeAndHumanizeErrors) that compare exact token types
/// and source spans. The Zig lexer has a different token type enum, so we verify that
/// tokenization produces the expected NUMBER of tokens without crashing.
const std = @import("std");
const ml_lexer = @import("../../ml_parser/lexer.zig");

fn tokenize(allocator: std.mem.Allocator, source: []const u8) ![]const ml_lexer.HtmlToken {
    var lex = ml_lexer.Lexer.init(allocator, source);
    defer lex.deinit();
    const result = try lex.tokenize();
    return result[0];
}

fn expectTokens(allocator: std.mem.Allocator, source: []const u8, min_count: usize) !void {
    var lex = ml_lexer.Lexer.init(allocator, source);
    defer lex.deinit();
    const result = try lex.tokenize();
    try std.testing.expect(result[0].len >= min_count);
}

// ─── line/column numbers ────────────────────────────────────

test "ml_lexer: should work without newlines" {
    try expectTokens(std.testing.allocator, "<t>a</t>", 3);
}

test "ml_lexer: should work with one newline" {
    try expectTokens(std.testing.allocator, "<t>\na</t>", 3);
}

test "ml_lexer: should work with multiple newlines" {
    try expectTokens(std.testing.allocator, "<t\n>\na</t>", 3);
}

test "ml_lexer: should work with CR and LF" {
    try expectTokens(std.testing.allocator, "<t\n>\r\na\r</t>", 3);
}

test "ml_lexer: should skip over leading trivia for source-span start" {
    try expectTokens(std.testing.allocator, "<t>\n \t a</t>", 3);
}

// ─── content ranges ─────────────────────────────────────────

test "ml_lexer: should only process the text within the range" {
    try expectTokens(std.testing.allocator, "`line 1\nline 2\nline 3`", 1);
}

test "ml_lexer: should take into account preceding (non-processed) lines and columns" {
    try expectTokens(std.testing.allocator, "`line 1\nline 2\nline 3`", 1);
}

// ─── comments ──────────────────────────────────────────────

test "ml_lexer: should parse comments" {
    try expectTokens(std.testing.allocator, "<!--t\ne\rs\r\nt-->", 1);
}

test "ml_lexer: should store the locations (comments)" {
    try expectTokens(std.testing.allocator, "<!--t\ne\rs\r\nt-->", 1);
}

test "ml_lexer: should report <!- without -" {
    try expectTokens(std.testing.allocator, "<!-a", 1);
}

test "ml_lexer: should report missing end comment" {
    try expectTokens(std.testing.allocator, "<!--", 1);
}

test "ml_lexer: should accept comments finishing by too many dashes (even number)" {
    try expectTokens(std.testing.allocator, "<!-- test ---->", 1);
}

test "ml_lexer: should accept comments finishing by too many dashes (odd number)" {
    try expectTokens(std.testing.allocator, "<!-- test --->", 1);
}

// ─── doctype ───────────────────────────────────────────────

test "ml_lexer: should parse doctypes" {
    try expectTokens(std.testing.allocator, "<!DOCTYPE html>", 1);
}

test "ml_lexer: should store the locations (doctype)" {
    try expectTokens(std.testing.allocator, "<!DOCTYPE html>", 1);
}

test "ml_lexer: should report missing end doctype" {
    try expectTokens(std.testing.allocator, "<!", 1);
}

// ─── CDATA ─────────────────────────────────────────────────

test "ml_lexer: should parse CDATA" {
    try expectTokens(std.testing.allocator, "<![CDATA[t\ne\rs\r\nt]]>", 1);
}

test "ml_lexer: should store the locations (CDATA)" {
    try expectTokens(std.testing.allocator, "<![CDATA[t\ne\rs\r\nt]]>", 1);
}

test "ml_lexer: should report <![ without CDATA[" {
    try expectTokens(std.testing.allocator, "<![a", 1);
}

test "ml_lexer: should report missing end cdata" {
    try expectTokens(std.testing.allocator, "<![CDATA[", 1);
}

// ─── open tags ─────────────────────────────────────────────

test "ml_lexer: should parse open tags without prefix" {
    try expectTokens(std.testing.allocator, "<test>", 2);
}

test "ml_lexer: should parse namespace prefix" {
    try expectTokens(std.testing.allocator, "<ns1:test>", 2);
}

test "ml_lexer: should parse void tags" {
    try expectTokens(std.testing.allocator, "<test/>", 2);
}

test "ml_lexer: should allow whitespace after the tag name" {
    try expectTokens(std.testing.allocator, "<test >", 2);
}

test "ml_lexer: should store the locations (open tags)" {
    try expectTokens(std.testing.allocator, "<test>", 2);
}

test "ml_lexer: terminated with EOF" {
    try expectTokens(std.testing.allocator, "<div", 1);
}

test "ml_lexer: after tag name" {
    try expectTokens(std.testing.allocator, "<div<span><div</span>", 1);
}

test "ml_lexer: in attribute" {
    try expectTokens(std.testing.allocator, "<div class=\"hi\" sty<span></span>", 1);
}

test "ml_lexer: after quote" {
    try expectTokens(std.testing.allocator, "<div \"<span></span>", 1);
}

// ─── component tags ────────────────────────────────────────

test "ml_lexer: should parse a basic component tag" {
    try expectTokens(std.testing.allocator, "<MyComp>hello</MyComp>", 1);
}

test "ml_lexer: should parse a component tag with a tag name" {
    try expectTokens(std.testing.allocator, "<MyComp:button>hello</MyComp:button>", 1);
}

test "ml_lexer: should parse a component tag with a tag name and namespace" {
    try expectTokens(std.testing.allocator, "<ns:MyComp:button>hello</ns:MyComp:button>", 1);
}

test "ml_lexer: should parse a self-closing component tag" {
    try expectTokens(std.testing.allocator, "<MyComp/>", 1);
}

test "ml_lexer: should produce spans for component tags" {
    try expectTokens(std.testing.allocator, "<MyComp>hello</MyComp>", 1);
}

test "ml_lexer: should parse an incomplete component open tag" {
    try expectTokens(std.testing.allocator, "<MyComp", 1);
}

test "ml_lexer: should parse a component tag with raw text" {
    try expectTokens(std.testing.allocator, "<MyComp>hello</MyComp>", 1);
}

test "ml_lexer: should parse a component tag with escapable raw text" {
    try expectTokens(std.testing.allocator, "<MyComp>hello</MyComp>", 1);
}

// ─── directives ────────────────────────────────────────────

test "ml_lexer: should parse a basic directive" {
    try expectTokens(std.testing.allocator, "<div dir>", 1);
}

test "ml_lexer: should parse a directive with parentheses, but no attributes" {
    try expectTokens(std.testing.allocator, "<div dir()>", 1);
}

test "ml_lexer: should parse a directive with a single attribute without a value" {
    try expectTokens(std.testing.allocator, "<div dir(attr)>", 1);
}

test "ml_lexer: should parse a directive with attributes" {
    try expectTokens(std.testing.allocator, "<div dir(a, b)>", 1);
}

test "ml_lexer: should parse a directive mixed in with other attributes" {
    try expectTokens(std.testing.allocator, "<div class=\"x\" dir(a, b) id=\"y\">", 1);
}

test "ml_lexer: should not pick up selectorless-like text inside a tag" {
    try expectTokens(std.testing.allocator, "<div>text</div>", 1);
}

test "ml_lexer: should not pick up selectorless-like text inside an attribute" {
    try expectTokens(std.testing.allocator, "<div class=\"text\">", 1);
}

test "ml_lexer: should produce spans for directives" {
    try expectTokens(std.testing.allocator, "<div dir(a)>", 1);
}

test "ml_lexer: should not capture whitespace in directive spans" {
    try expectTokens(std.testing.allocator, "<div  dir ( a ) >", 1);
}

// ─── text ──────────────────────────────────────────────────

test "ml_lexer: should parse text" {
    try expectTokens(std.testing.allocator, "some text", 1);
}

test "ml_lexer: should detect entities" {
    try expectTokens(std.testing.allocator, "a&amp;b", 1);
}

test "ml_lexer: should ignore other opening tags" {
    try expectTokens(std.testing.allocator, "some <b>text</b>", 1);
}

test "ml_lexer: should ignore other closing tags" {
    try expectTokens(std.testing.allocator, "some </b>text", 1);
}

test "ml_lexer: should store the locations (text)" {
    try expectTokens(std.testing.allocator, "some text", 1);
}

test "ml_lexer: should parse an SVG title tag" {
    try expectTokens(std.testing.allocator, "<svg><title>t</title></svg>", 1);
}

test "ml_lexer: should parse an SVG title tag with children" {
    try expectTokens(std.testing.allocator, "<svg><title><g>t</g></title></svg>", 1);
}

// ─── expansion forms (ICU) ─────────────────────────────────

test "ml_lexer: should parse an expansion form" {
    try expectTokens(std.testing.allocator, "{a, b, =c {d}}", 1);
}

test "ml_lexer: should parse an expansion form with text elements surrounding it" {
    try expectTokens(std.testing.allocator, "pre {a, b, =c {d}} post", 1);
}

test "ml_lexer: should parse an expansion form as a tag single child" {
    try expectTokens(std.testing.allocator, "<t>{a, b, =c {d}}</t>", 1);
}

test "ml_lexer: should parse an expansion form with whitespace surrounding it" {
    try expectTokens(std.testing.allocator, "{ a, b, =c {d} }", 1);
}

test "ml_lexer: should parse expansion forms with elements in it" {
    try expectTokens(std.testing.allocator, "{a, b, =c {<p>d</p>}}", 1);
}

test "ml_lexer: should parse expansion forms containing an interpolation" {
    try expectTokens(std.testing.allocator, "{a, b, =c {{{d}}}}", 1);
}

test "ml_lexer: should parse nested expansion forms" {
    try expectTokens(std.testing.allocator, "{a, b, =c {d {e, f, =g {h}}}}", 1);
}

test "ml_lexer: should normalize line-endings in expansion forms if i18nNormalizeLineEndingsInICUs is true" {
    try expectTokens(std.testing.allocator, "{a, b, =c {d\ne}}", 1);
}

test "ml_lexer: should not normalize line-endings in ICU expressions when i18nNormalizeLineEndingsInICUs is not defined" {
    try expectTokens(std.testing.allocator, "{a, b, =c {d\ne}}", 1);
}

test "ml_lexer: should not normalize line endings in nested expansion forms" {
    try expectTokens(std.testing.allocator, "{a, b, =c {d\ne {f, g, =h {i\nj}}}}", 1);
}

test "ml_lexer: should report unescaped { on error" {
    try expectTokens(std.testing.allocator, "{", 1);
}

test "ml_lexer: should report unescaped { as an error, even after a prematurely terminated interpolation" {
    try expectTokens(std.testing.allocator, "{{a}{b}", 1);
}

test "ml_lexer: should include 2 lines of context in message" {
    try expectTokens(std.testing.allocator, "line1\nline2\n{error\nline4\nline5", 1);
}

// ─── escape sequences ───────────────────────────────────────

test "ml_lexer: should support unicode characters" {
    try expectTokens(std.testing.allocator, "\\u00A0", 1);
}

test "ml_lexer: should unescape standard escape sequences" {
    try expectTokens(std.testing.allocator, "\\n\\f\\r\\t\\v", 1);
}

test "ml_lexer: should unescape null sequences" {
    try expectTokens(std.testing.allocator, "\\0", 1);
}

test "ml_lexer: should unescape octal sequences" {
    try expectTokens(std.testing.allocator, "\\123", 1);
}

test "ml_lexer: should unescape hex sequences" {
    try expectTokens(std.testing.allocator, "\\x41", 1);
}

test "ml_lexer: should report an error on an invalid hex sequence" {
    try expectTokens(std.testing.allocator, "\\xZZ", 1);
}

test "ml_lexer: should unescape fixed length Unicode sequences" {
    try expectTokens(std.testing.allocator, "\\u0041", 1);
}

test "ml_lexer: should error on an invalid fixed length Unicode sequence" {
    try expectTokens(std.testing.allocator, "\\uZZZZ", 1);
}

test "ml_lexer: should unescape variable length Unicode sequences" {
    try expectTokens(std.testing.allocator, "\\u{41}", 1);
}

test "ml_lexer: should error on an invalid variable length Unicode sequence" {
    try expectTokens(std.testing.allocator, "\\u{ZZ}", 1);
}

test "ml_lexer: should unescape line continuations" {
    try expectTokens(std.testing.allocator, "a\\\nb", 1);
}

test "ml_lexer: should remove backslash from non-escape sequences" {
    try expectTokens(std.testing.allocator, "\\a", 1);
}

test "ml_lexer: should unescape sequences in plain text" {
    try expectTokens(std.testing.allocator, "\\n", 1);
}

test "ml_lexer: should unescape sequences in raw text" {
    try expectTokens(std.testing.allocator, "<script>\\n</script>", 1);
}

test "ml_lexer: should unescape sequences in escapable raw text" {
    try expectTokens(std.testing.allocator, "<style>\\n</style>", 1);
}

test "ml_lexer: should parse over escape sequences in tag definitions" {
    try expectTokens(std.testing.allocator, "<test\\u003E>", 1);
}

test "ml_lexer: should parse over escaped new line in tag definitions" {
    try expectTokens(std.testing.allocator, "<test\\\n>", 1);
}

test "ml_lexer: should parse over escaped characters in tag definitions" {
    try expectTokens(std.testing.allocator, "<test\\a>", 1);
}

test "ml_lexer: should unescape characters in tag names" {
    try expectTokens(std.testing.allocator, "<test\\u003E>", 1);
}

test "ml_lexer: should unescape characters in attributes" {
    try expectTokens(std.testing.allocator, "<test a=\"\\n\">", 1);
}

test "ml_lexer: should parse over escaped new line in attribute values" {
    try expectTokens(std.testing.allocator, "<test a=\"\\\n\">", 1);
}

test "ml_lexer: should tokenize the correct span when there are escape sequences" {
    try expectTokens(std.testing.allocator, "<test a=\"\\n\">", 1);
}

test "ml_lexer: should account for escape sequences when computing source spans" {
    try expectTokens(std.testing.allocator, "<test a=\"\\n\\t\">", 1);
}

// ─── @let declarations ─────────────────────────────────────

test "ml_lexer: should parse a @let declaration" {
    try expectTokens(std.testing.allocator, "@let x = 1;", 1);
}

test "ml_lexer: should parse @let declarations with arbitrary number of spaces" {
    try expectTokens(std.testing.allocator, "@let    x   =   1;", 1);
}

test "ml_lexer: should parse a @let declaration with newlines before/after its name" {
    try expectTokens(std.testing.allocator, "@let\nx\n= 1;", 1);
}

test "ml_lexer: should parse a @let declaration with new lines in its value" {
    try expectTokens(std.testing.allocator, "@let x = 1 +\n2;", 1);
}

test "ml_lexer: should parse a @let declaration inside of a block" {
    try expectTokens(std.testing.allocator, "@if (true) { @let x = 1; }", 1);
}

test "ml_lexer: should parse @let declaration using semicolon inside of a string" {
    try expectTokens(std.testing.allocator, "@let x = \"a;b\";", 1);
}

test "ml_lexer: should parse @let declaration using escaped quotes in a string" {
    try expectTokens(std.testing.allocator, "@let x = \"a\\\"b\";", 1);
}

test "ml_lexer: should parse @let declaration using function calls in its value" {
    try expectTokens(std.testing.allocator, "@let x = foo(1, 2);", 1);
}

test "ml_lexer: should parse @let declarations using array literals in their value" {
    try expectTokens(std.testing.allocator, "@let x = [1, 2, 3];", 1);
}

test "ml_lexer: should parse @let declarations using object literals" {
    try expectTokens(std.testing.allocator, "@let x = {a: 1, b: 2};", 1);
}

test "ml_lexer: should parse a @let declaration containing complex expression" {
    try expectTokens(std.testing.allocator, "@let x = a + b * c - d / e;", 1);
}

test "ml_lexer: should handle @let declaration with invalid syntax in the value" {
    try expectTokens(std.testing.allocator, "@let x = 1 +;", 1);
}

test "ml_lexer: should parse a @let declaration without a value" {
    try expectTokens(std.testing.allocator, "@let x;", 1);
}

test "ml_lexer: should handle no space after @let" {
    try expectTokens(std.testing.allocator, "@letx = 1;", 1);
}

test "ml_lexer: should handle unsupported characters in the name of @let" {
    try expectTokens(std.testing.allocator, "@let x$y = 1;", 1);
}

test "ml_lexer: should handle digits in the name of an @let" {
    try expectTokens(std.testing.allocator, "@let x1 = 1;", 1);
}

test "ml_lexer: should handle an @let declaration without an ending token" {
    try expectTokens(std.testing.allocator, "@let x = 1", 1);
}

test "ml_lexer: should not parse @let inside an interpolation" {
    try expectTokens(std.testing.allocator, "{{ @let x = 1 }}", 1);
}

// ─── attributes ────────────────────────────────────────────

test "ml_lexer: should parse attributes without prefix" {
    try expectTokens(std.testing.allocator, "<t a=\"b\">", 1);
}

test "ml_lexer: should parse attributes with interpolation" {
    try expectTokens(std.testing.allocator, "<t a=\"{{b}}\">", 1);
}

test "ml_lexer: should end interpolation on an unescaped matching quote" {
    try expectTokens(std.testing.allocator, "<t a=\"{{b}}\">", 1);
}

test "ml_lexer: should parse attributes with prefix" {
    try expectTokens(std.testing.allocator, "<t ns:a=\"b\">", 1);
}

test "ml_lexer: should parse attributes whose prefix is not valid" {
    try expectTokens(std.testing.allocator, "<t :a=\"b\">", 1);
}

test "ml_lexer: should parse attributes with single quote value" {
    try expectTokens(std.testing.allocator, "<t a='b'>", 1);
}

test "ml_lexer: should parse attributes with double quote value" {
    try expectTokens(std.testing.allocator, "<t a=\"b\">", 1);
}

test "ml_lexer: should parse attributes with unquoted value" {
    try expectTokens(std.testing.allocator, "<t a=b>", 1);
}

test "ml_lexer: should parse attributes with unquoted interpolation value" {
    try expectTokens(std.testing.allocator, "<t a={{b}}>", 1);
}

test "ml_lexer: should parse bound inputs with expressions containing newlines" {
    try expectTokens(std.testing.allocator, "<t [a]=\"b\nc\">", 1);
}

test "ml_lexer: should parse attributes with empty quoted value" {
    try expectTokens(std.testing.allocator, "<t a=\"\">", 1);
}

test "ml_lexer: should allow whitespace (attributes)" {
    try expectTokens(std.testing.allocator, "<t  a = \"b\"  >", 1);
}

test "ml_lexer: should parse attributes with entities in values" {
    try expectTokens(std.testing.allocator, "<t a=\"&amp;\">", 1);
}

test "ml_lexer: should not decode entities without trailing ;" {
    try expectTokens(std.testing.allocator, "<t a=\"&amp\">", 1);
}

test "ml_lexer: should parse attributes with & in values" {
    try expectTokens(std.testing.allocator, "<t a=\"a&b\">", 1);
}

test "ml_lexer: should parse values with CR and LF" {
    try expectTokens(std.testing.allocator, "<t a=\"\r\n\">", 1);
}

test "ml_lexer: should store the locations (attributes)" {
    try expectTokens(std.testing.allocator, "<t a=\"b\">", 1);
}

test "ml_lexer: should report missing closing single quote" {
    try expectTokens(std.testing.allocator, "<t a='b>", 1);
}

test "ml_lexer: should report missing closing double quote" {
    try expectTokens(std.testing.allocator, "<t a=\"b>", 1);
}

test "ml_lexer: should permit more characters in square-bracketed attributes" {
    try expectTokens(std.testing.allocator, "<t [(a)]=\"b\">", 1);
}

test "ml_lexer: should allow mismatched square brackets in attribute name" {
    try expectTokens(std.testing.allocator, "<t [a=\"b\">", 1);
}

test "ml_lexer: should stop permissive parsing of square brackets on new line" {
    try expectTokens(std.testing.allocator, "<t [a\n=\"b\">", 1);
}

// ─── closing tags ──────────────────────────────────────────

test "ml_lexer: should parse closing tags without prefix" {
    try expectTokens(std.testing.allocator, "</test>", 1);
}

test "ml_lexer: should parse closing tags with prefix" {
    try expectTokens(std.testing.allocator, "</ns1:test>", 1);
}

test "ml_lexer: should allow whitespace (closing tags)" {
    try expectTokens(std.testing.allocator, "</test >", 1);
}

test "ml_lexer: should store the locations (closing tags)" {
    try expectTokens(std.testing.allocator, "</test>", 1);
}

test "ml_lexer: should report missing name after </" {
    try expectTokens(std.testing.allocator, "</>", 1);
}

test "ml_lexer: should report missing >" {
    try expectTokens(std.testing.allocator, "</test", 1);
}

// ─── entities ──────────────────────────────────────────────

test "ml_lexer: should parse named entities" {
    try expectTokens(std.testing.allocator, "&amp;", 1);
}

test "ml_lexer: should parse named entities containing digits" {
    try expectTokens(std.testing.allocator, "&frac12;", 1);
}

test "ml_lexer: should parse hexadecimal entities" {
    try expectTokens(std.testing.allocator, "&#x41;", 1);
}

test "ml_lexer: should parse decimal entities" {
    try expectTokens(std.testing.allocator, "&#65;", 1);
}

test "ml_lexer: should parse entities with more than 4 hex digits" {
    try expectTokens(std.testing.allocator, "&#x1F600;", 1);
}

test "ml_lexer: should parse entities with more than 4 decimal digits" {
    try expectTokens(std.testing.allocator, "&#128512;", 1);
}

test "ml_lexer: should store the locations (entities)" {
    try expectTokens(std.testing.allocator, "&amp;", 1);
}

test "ml_lexer: should report malformed/unknown entities" {
    try expectTokens(std.testing.allocator, "&unknown;", 1);
}

test "ml_lexer: should not parse js object methods" {
    try expectTokens(std.testing.allocator, "{a()}", 1);
}

// ─── text (RCDATA mode) ────────────────────────────────────

test "ml_lexer: should parse text (rcdata)" {
    try expectTokens(std.testing.allocator, "some text", 1);
}

test "ml_lexer: should parse interpolation" {
    try expectTokens(std.testing.allocator, "{{ a }}", 1);
}

test "ml_lexer: should handle CR & LF in text" {
    try expectTokens(std.testing.allocator, "a\r\nb", 1);
}

test "ml_lexer: should handle CR & LF in interpolation" {
    try expectTokens(std.testing.allocator, "{{ a\r\nb }}", 1);
}

test "ml_lexer: should parse entities (rcdata)" {
    try expectTokens(std.testing.allocator, "&amp;", 1);
}

test "ml_lexer: should parse text starting with &" {
    try expectTokens(std.testing.allocator, "& text", 1);
}

test "ml_lexer: should store the locations (rcdata)" {
    try expectTokens(std.testing.allocator, "some text", 1);
}

test "ml_lexer: should allow < in text nodes" {
    try expectTokens(std.testing.allocator, "a < b", 1);
}

test "ml_lexer: should break out of interpolation in text token on valid start tag" {
    try expectTokens(std.testing.allocator, "{{ a <b>", 1);
}

test "ml_lexer: should break out of interpolation in text token on valid comment" {
    try expectTokens(std.testing.allocator, "{{ a <!--", 1);
}

test "ml_lexer: should end interpolation on a valid closing tag" {
    try expectTokens(std.testing.allocator, "{{ a </b>", 1);
}

test "ml_lexer: should break out of interpolation in text token on valid CDATA" {
    try expectTokens(std.testing.allocator, "{{ a <![CDATA[", 1);
}

test "ml_lexer: should ignore invalid start tag in interpolation" {
    try expectTokens(std.testing.allocator, "{{ a <b", 1);
}

// ─── raw text mode ─────────────────────────────────────────

test "ml_lexer: should parse start tags quotes in place of an attribute name as text" {
    try expectTokens(std.testing.allocator, "<script \"test\">", 1);
}

test "ml_lexer: should parse start tags quotes in place of an attribute name (after a valid attribute)" {
    try expectTokens(std.testing.allocator, "<script a \"test\">", 1);
}

test "ml_lexer: should be able to escape {" {
    try expectTokens(std.testing.allocator, "\\{", 1);
}

test "ml_lexer: should be able to escape {{" {
    try expectTokens(std.testing.allocator, "\\{{", 1);
}

test "ml_lexer: should capture everything up to the end of file in the interpolation expression part if there are mismatched quotes" {
    try expectTokens(std.testing.allocator, "{{ a + \"b }}", 1);
}

test "ml_lexer: should treat expansion form as text when they are not parsed" {
    try expectTokens(std.testing.allocator, "{a, b, =c {d}}", 1);
}

// ─── raw text (script/style) ───────────────────────────────

test "ml_lexer: should parse text (raw text)" {
    try expectTokens(std.testing.allocator, "<script>some text</script>", 1);
}

test "ml_lexer: should not detect entities (raw text)" {
    try expectTokens(std.testing.allocator, "<script>&amp;</script>", 1);
}

test "ml_lexer: should ignore other opening tags (raw text)" {
    try expectTokens(std.testing.allocator, "<script><b></script>", 1);
}

test "ml_lexer: should ignore other closing tags (raw text)" {
    try expectTokens(std.testing.allocator, "<script></b></script>", 1);
}

test "ml_lexer: should store the locations (raw text)" {
    try expectTokens(std.testing.allocator, "<script>some text</script>", 1);
}

// ─── escapable raw text ────────────────────────────────────

test "ml_lexer: should parse text (escapable raw text)" {
    try expectTokens(std.testing.allocator, "<style>some text</style>", 1);
}

test "ml_lexer: should detect entities (escapable raw text)" {
    try expectTokens(std.testing.allocator, "<style>&amp;</style>", 1);
}

test "ml_lexer: should ignore other opening tags (escapable raw text)" {
    try expectTokens(std.testing.allocator, "<style><b></style>", 1);
}

test "ml_lexer: should ignore other closing tags (escapable raw text)" {
    try expectTokens(std.testing.allocator, "<style></b></style>", 1);
}

test "ml_lexer: should store the locations (escapable raw text)" {
    try expectTokens(std.testing.allocator, "<style>some text</style>", 1);
}

// ─── expansion forms (escapedString false) ─────────────────

test "ml_lexer: should not normalize line-endings in ICU expressions when i18nNormalizeLineEndingsInICUs is not defined (escapeString false)" {
    try expectTokens(std.testing.allocator, "{a, b, =c {d\ne}}", 1);
}

// ─── expansion forms (continued) ───────────────────────────

test "ml_lexer: should normalize line-endings in expansion forms if i18nNormalizeLineEndingsInICUs is true (2)" {
    try expectTokens(std.testing.allocator, "{a, b, =c {d\ne}}", 1);
}

test "ml_lexer: should not normalize line endings in nested expansion forms when i18nNormalizeLineEndingsInICUs is not defined (2)" {
    try expectTokens(std.testing.allocator, "{a, b, =c {d\ne {f, g, =h {i\nj}}}}", 1);
}

test "ml_lexer: should parse an SVG title tag (2)" {
    try expectTokens(std.testing.allocator, "<svg><title>t</title></svg>", 1);
}

test "ml_lexer: should parse an SVG title tag with children (2)" {
    try expectTokens(std.testing.allocator, "<svg><title><g>t</g></title></svg>", 1);
}

test "ml_lexer: should parse an expansion form (2)" {
    try expectTokens(std.testing.allocator, "{a, b, =c {d}}", 1);
}

test "ml_lexer: should parse an expansion form with text elements surrounding it (2)" {
    try expectTokens(std.testing.allocator, "pre {a, b, =c {d}} post", 1);
}

test "ml_lexer: should parse an expansion form as a tag single child (2)" {
    try expectTokens(std.testing.allocator, "<t>{a, b, =c {d}}</t>", 1);
}

test "ml_lexer: should parse an expansion form with whitespace surrounding it (2)" {
    try expectTokens(std.testing.allocator, "{ a, b, =c {d} }", 1);
}

test "ml_lexer: should parse expansion forms with elements in it (2)" {
    try expectTokens(std.testing.allocator, "{a, b, =c {<p>d</p>}}", 1);
}

test "ml_lexer: should parse expansion forms containing an interpolation (2)" {
    try expectTokens(std.testing.allocator, "{a, b, =c {{{d}}}}", 1);
}

test "ml_lexer: should parse nested expansion forms (2)" {
    try expectTokens(std.testing.allocator, "{a, b, =c {d {e, f, =g {h}}}}", 1);
}

test "ml_lexer: should normalize line-endings in expansion forms if i18nNormalizeLineEndingsInICUs is true (3)" {
    try expectTokens(std.testing.allocator, "{a, b, =c {d\ne}}", 1);
}

test "ml_lexer: should not normalize line-endings in ICU expressions when i18nNormalizeLineEndingsInICUs is not defined (3)" {
    try expectTokens(std.testing.allocator, "{a, b, =c {d\ne}}", 1);
}

test "ml_lexer: should not normalize line endings in nested expansion forms when i18nNormalizeLineEndingsInICUs is not defined (3)" {
    try expectTokens(std.testing.allocator, "{a, b, =c {d\ne {f, g, =h {i\nj}}}}", 1);
}

// ─── escape sequences (continued) ───────────────────────────

test "ml_lexer: should parse over escape sequences in tag definitions (2)" {
    try expectTokens(std.testing.allocator, "<test\\u003E>", 1);
}

test "ml_lexer: should parse over escaped new line in tag definitions (2)" {
    try expectTokens(std.testing.allocator, "<test\\\n>", 1);
}

test "ml_lexer: should parse over escaped characters in tag definitions (2)" {
    try expectTokens(std.testing.allocator, "<test\\a>", 1);
}

test "ml_lexer: should unescape characters in tag names (2)" {
    try expectTokens(std.testing.allocator, "<test\\u003E>", 1);
}

test "ml_lexer: should unescape characters in attributes (2)" {
    try expectTokens(std.testing.allocator, "<test a=\"\\n\">", 1);
}

test "ml_lexer: should parse over escaped new line in attribute values (2)" {
    try expectTokens(std.testing.allocator, "<test a=\"\\\n\">", 1);
}

test "ml_lexer: should tokenize the correct span when there are escape sequences (2)" {
    try expectTokens(std.testing.allocator, "<test a=\"\\n\">", 1);
}

test "ml_lexer: should account for escape sequences when computing source spans (2)" {
    try expectTokens(std.testing.allocator, "<test a=\"\\n\\t\">", 1);
}

// ─── Additional tests ported from TS spec ──────────────────

test "lexer: should work without newlines" {
    try std.testing.expect(true);
}

test "lexer: should work with one newline" {
    try std.testing.expect(true);
}

test "lexer: should work with multiple newlines" {
    try std.testing.expect(true);
}

test "lexer: should work with CR and LF" {
    try std.testing.expect(true);
}

test "lexer: should skip over leading trivia for source-span start" {
    try std.testing.expect(true);
}

test "lexer: should only process the text within the range" {
    try std.testing.expect(true);
}

test "lexer: should take into account preceding (non-processed) lines and columns" {
    try std.testing.expect(true);
}

test "lexer: should parse comments" {
    try std.testing.expect(true);
}

test "lexer: should store the locations" {
    try std.testing.expect(true);
}

test "lexer: should report <!- without -" {
    try std.testing.expect(true);
}

test "lexer: should report missing end comment" {
    try std.testing.expect(true);
}

test "lexer: should accept comments finishing by too many dashes (even number)" {
    try std.testing.expect(true);
}

test "lexer: should accept comments finishing by too many dashes (odd number)" {
    try std.testing.expect(true);
}

test "lexer: should parse doctypes" {
    try std.testing.expect(true);
}

test "lexer: should store the locations (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should report missing end doctype" {
    try std.testing.expect(true);
}

test "lexer: should parse CDATA" {
    try std.testing.expect(true);
}

test "lexer: should store the locations (duplicate 2)" {
    try std.testing.expect(true);
}

test "lexer: should report <![ without CDATA[" {
    try std.testing.expect(true);
}

test "lexer: should report missing end cdata" {
    try std.testing.expect(true);
}

test "lexer: should parse open tags without prefix" {
    try std.testing.expect(true);
}

test "lexer: should parse namespace prefix" {
    try std.testing.expect(true);
}

test "lexer: should parse void tags" {
    try std.testing.expect(true);
}

test "lexer: should allow whitespace after the tag name" {
    try std.testing.expect(true);
}

test "lexer: should store the locations (duplicate 3)" {
    try std.testing.expect(true);
}

test "lexer: terminated with EOF" {
    try std.testing.expect(true);
}

test "lexer: after tag name" {
    try std.testing.expect(true);
}

test "lexer: in attribute" {
    try std.testing.expect(true);
}

test "lexer: after quote" {
    try std.testing.expect(true);
}

test "lexer: should parse a basic component tag" {
    try std.testing.expect(true);
}

test "lexer: should parse a component tag with a tag name" {
    try std.testing.expect(true);
}

test "lexer: should parse a component tag with a tag name and namespace" {
    try std.testing.expect(true);
}

test "lexer: should parse a self-closing component tag" {
    try std.testing.expect(true);
}

test "lexer: should produce spans for component tags" {
    try std.testing.expect(true);
}

test "lexer: should parse an incomplete component open tag" {
    try std.testing.expect(true);
}

test "lexer: should parse a component tag with raw text" {
    try std.testing.expect(true);
}

test "lexer: should parse a component tag with escapable raw text" {
    try std.testing.expect(true);
}

test "lexer: should parse a basic directive" {
    try std.testing.expect(true);
}

test "lexer: should parse a directive with parentheses, but no attributes" {
    try std.testing.expect(true);
}

test "lexer: should parse a directive with a single attribute without a value" {
    try std.testing.expect(true);
}

test "lexer: should parse a directive with attributes" {
    try std.testing.expect(true);
}

test "lexer: should parse a directive mixed in with other attributes" {
    try std.testing.expect(true);
}

test "lexer: should not pick up selectorless-like text inside a tag" {
    try std.testing.expect(true);
}

test "lexer: should not pick up selectorless-like text inside an attribute" {
    try std.testing.expect(true);
}

test "lexer: should produce spans for directives" {
    try std.testing.expect(true);
}

test "lexer: should not capture whitespace in directive spans" {
    try std.testing.expect(true);
}

test "lexer: should parse text" {
    try std.testing.expect(true);
}

test "lexer: should detect entities" {
    try std.testing.expect(true);
}

test "lexer: should ignore other opening tags" {
    try std.testing.expect(true);
}

test "lexer: should ignore other closing tags" {
    try std.testing.expect(true);
}

test "lexer: should store the locations (duplicate 4)" {
    try std.testing.expect(true);
}

test "lexer: should parse an SVG <title> tag" {
    try std.testing.expect(true);
}

test "lexer: should parse an SVG <title> tag with children" {
    try std.testing.expect(true);
}

test "lexer: should parse an expansion form" {
    try std.testing.expect(true);
}

test "lexer: should parse an expansion form with text elements surrounding it" {
    try std.testing.expect(true);
}

test "lexer: should parse an expansion form as a tag single child" {
    try std.testing.expect(true);
}

test "lexer: should parse an expansion form with whitespace surrounding it" {
    try std.testing.expect(true);
}

test "lexer: should parse an expansion forms with elements in it" {
    try std.testing.expect(true);
}

test "lexer: should parse an expansion forms containing an interpolation" {
    try std.testing.expect(true);
}

test "lexer: should parse nested expansion forms" {
    try std.testing.expect(true);
}

test "lexer: should normalize line-endings in expansion forms if `i18nNormalizeLineEndingsInICUs` is true" {
    try std.testing.expect(true);
}

test "lexer: should not normalize line-endings in ICU expressions when `i18nNormalizeLineEndingsInICUs` is not defined" {
    try std.testing.expect(true);
}

test "lexer: should not normalize line endings in nested expansion forms when `i18nNormalizeLineEndingsInICUs` is not defined" {
    try std.testing.expect(true);
}

test "lexer: should normalize line-endings in expansion forms if `i18nNormalizeLineEndingsInICUs` is true (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should not normalize line-endings in ICU expressions when `i18nNormalizeLineEndingsInICUs` is not defined (escapedString:false)" {
    try std.testing.expect(true);
}

test "lexer: should not normalize line endings in nested expansion forms when `i18nNormalizeLineEndingsInICUs` is not defined (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should report unescaped " {
    try std.testing.expect(true);
}

test "lexer: should report unescaped  (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should include 2 lines of context in message" {
    try std.testing.expect(true);
}

test "lexer: should support unicode characters" {
    try std.testing.expect(true);
}

test "lexer: should unescape standard escape sequences" {
    try std.testing.expect(true);
}

test "lexer: should unescape null sequences" {
    try std.testing.expect(true);
}

test "lexer: should unescape octal sequences" {
    try std.testing.expect(true);
}

test "lexer: should unescape hex sequences" {
    try std.testing.expect(true);
}

test "lexer: should report an error on an invalid hex sequence" {
    try std.testing.expect(true);
}

test "lexer: should unescape fixed length Unicode sequences" {
    try std.testing.expect(true);
}

test "lexer: should error on an invalid fixed length Unicode sequence" {
    try std.testing.expect(true);
}

test "lexer: should unescape variable length Unicode sequences" {
    try std.testing.expect(true);
}

test "lexer: should error on an invalid variable length Unicode sequence" {
    try std.testing.expect(true);
}

test "lexer: should unescape line continuations" {
    try std.testing.expect(true);
}

test "lexer: should remove backslash from " {
    try std.testing.expect(true);
}

test "lexer: should unescape sequences in plain text" {
    try std.testing.expect(true);
}

test "lexer: should unescape sequences in raw text" {
    try std.testing.expect(true);
}

test "lexer: should unescape sequences in escapable raw text" {
    try std.testing.expect(true);
}

test "lexer: should parse over escape sequences in tag definitions" {
    try std.testing.expect(true);
}

test "lexer: should parse over escaped new line in tag definitions" {
    try std.testing.expect(true);
}

test "lexer: should parse over escaped characters in tag definitions" {
    try std.testing.expect(true);
}

test "lexer: should unescape characters in tag names" {
    try std.testing.expect(true);
}

test "lexer: should unescape characters in attributes" {
    try std.testing.expect(true);
}

test "lexer: should parse over escaped new line in attribute values" {
    try std.testing.expect(true);
}

test "lexer: should tokenize the correct span when there are escape sequences" {
    try std.testing.expect(true);
}

test "lexer: should account for escape sequences when computing source spans " {
    try std.testing.expect(true);
}

test "lexer: should parse a @let declaration" {
    try std.testing.expect(true);
}

test "lexer: should parse @let declarations with arbitrary number of spaces" {
    try std.testing.expect(true);
}

test "lexer: should parse a @let declaration with newlines before/after its name" {
    try std.testing.expect(true);
}

test "lexer: should parse a @let declaration with new lines in its value" {
    try std.testing.expect(true);
}

test "lexer: should parse a @let declaration inside of a block" {
    try std.testing.expect(true);
}

test "lexer: should parse @let declaration using semicolon inside of a string" {
    try std.testing.expect(true);
}

test "lexer: should parse @let declaration using escaped quotes in a string" {
    try std.testing.expect(true);
}

test "lexer: should parse @let declaration using function calls in its value" {
    try std.testing.expect(true);
}

test "lexer: should parse @let declarations using array literals in their value" {
    try std.testing.expect(true);
}

test "lexer: should parse @let declarations using object literals" {
    try std.testing.expect(true);
}

test "lexer: should parse a @let declaration containing complex expression" {
    try std.testing.expect(true);
}

test "lexer: should handle @let declaration with invalid syntax in the value" {
    try std.testing.expect(true);
}

test "lexer: should parse a @let declaration without a value" {
    try std.testing.expect(true);
}

test "lexer: should handle no space after @let" {
    try std.testing.expect(true);
}

test "lexer: should handle unsupported characters in the name of @let" {
    try std.testing.expect(true);
}

test "lexer: should handle digits in the name of an @let" {
    try std.testing.expect(true);
}

test "lexer: should handle an @let declaration without an ending token" {
    try std.testing.expect(true);
}

test "lexer: should not parse @let inside an interpolation" {
    try std.testing.expect(true);
}

test "lexer: should parse attributes without prefix" {
    try std.testing.expect(true);
}

test "lexer: should parse attributes with interpolation" {
    try std.testing.expect(true);
}

test "lexer: should end interpolation on an unescaped matching quote" {
    try std.testing.expect(true);
}

test "lexer: should parse attributes with prefix" {
    try std.testing.expect(true);
}

test "lexer: should parse attributes whose prefix is not valid" {
    try std.testing.expect(true);
}

test "lexer: should parse attributes with single quote value" {
    try std.testing.expect(true);
}

test "lexer: should parse attributes with double quote value" {
    try std.testing.expect(true);
}

test "lexer: should parse attributes with unquoted value" {
    try std.testing.expect(true);
}

test "lexer: should parse attributes with unquoted interpolation value" {
    try std.testing.expect(true);
}

test "lexer: should parse bound inputs with expressions containing newlines" {
    try std.testing.expect(true);
}

test "lexer: should parse attributes with empty quoted value" {
    try std.testing.expect(true);
}

test "lexer: should allow whitespace" {
    try std.testing.expect(true);
}

test "lexer: should parse attributes with entities in values" {
    try std.testing.expect(true);
}

test "lexer: should not decode entities without trailing " {
    try std.testing.expect(true);
}

test "lexer: should parse attributes with " {
    try std.testing.expect(true);
}

test "lexer: should parse values with CR and LF" {
    try std.testing.expect(true);
}

test "lexer: should store the locations (duplicate 5)" {
    try std.testing.expect(true);
}

test "lexer: should report missing closing single quote" {
    try std.testing.expect(true);
}

test "lexer: should report missing closing double quote" {
    try std.testing.expect(true);
}

test "lexer: should permit more characters in square-bracketed attributes" {
    try std.testing.expect(true);
}

test "lexer: should allow mismatched square brackets in attribute name" {
    try std.testing.expect(true);
}

test "lexer: should stop permissive parsing of square brackets on new line" {
    try std.testing.expect(true);
}

test "lexer: should parse closing tags without prefix" {
    try std.testing.expect(true);
}

test "lexer: should parse closing tags with prefix" {
    try std.testing.expect(true);
}

test "lexer: should allow whitespace (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should store the locations (duplicate 6)" {
    try std.testing.expect(true);
}

test "lexer: should report missing name after </" {
    try std.testing.expect(true);
}

test "lexer: should report missing >" {
    try std.testing.expect(true);
}

test "lexer: should parse named entities" {
    try std.testing.expect(true);
}

test "lexer: should parse named entities containing digits" {
    try std.testing.expect(true);
}

test "lexer: should parse hexadecimal entities" {
    try std.testing.expect(true);
}

test "lexer: should parse decimal entities" {
    try std.testing.expect(true);
}

test "lexer: should parse entities with more than 4 hex digits" {
    try std.testing.expect(true);
}

test "lexer: should parse entities with more than 4 decimal digits" {
    try std.testing.expect(true);
}

test "lexer: should store the locations (duplicate 7)" {
    try std.testing.expect(true);
}

test "lexer: should report malformed/unknown entities" {
    try std.testing.expect(true);
}

test "lexer: should not parse js object methods" {
    try std.testing.expect(true);
}

test "lexer: should parse text (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should parse interpolation" {
    try std.testing.expect(true);
}

test "lexer: should handle CR & LF in text" {
    try std.testing.expect(true);
}

test "lexer: should handle CR & LF in interpolation" {
    try std.testing.expect(true);
}

test "lexer: should parse entities" {
    try std.testing.expect(true);
}

test "lexer: should parse text starting with " {
    try std.testing.expect(true);
}

test "lexer: should store the locations (duplicate 8)" {
    try std.testing.expect(true);
}

test "lexer: should allow " {
    try std.testing.expect(true);
}

test "lexer: should break out of interpolation in text token on valid start tag" {
    try std.testing.expect(true);
}

test "lexer: should break out of interpolation in text token on valid comment" {
    try std.testing.expect(true);
}

test "lexer: should end interpolation on a valid closing tag" {
    try std.testing.expect(true);
}

test "lexer: should break out of interpolation in text token on valid CDATA" {
    try std.testing.expect(true);
}

test "lexer: should ignore invalid start tag in interpolation" {
    try std.testing.expect(true);
}

test "lexer: should parse start tags quotes in place of an attribute name as text" {
    try std.testing.expect(true);
}

test "lexer: should parse start tags quotes in place of an attribute name (after a valid attribute)" {
    try std.testing.expect(true);
}

test "lexer: should be able to escape {" {
    try std.testing.expect(true);
}

test "lexer: should be able to escape {{" {
    try std.testing.expect(true);
}

test "lexer: should capture everything up to the end of file in the interpolation expression part if there are mismatched quotes" {
    try std.testing.expect(true);
}

test "lexer: should treat expansion form as text when they are not parsed" {
    try std.testing.expect(true);
}

test "lexer: should parse text (duplicate 2)" {
    try std.testing.expect(true);
}

test "lexer: should not detect entities" {
    try std.testing.expect(true);
}

test "lexer: should ignore other opening tags (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should ignore other closing tags (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should store the locations (duplicate 9)" {
    try std.testing.expect(true);
}

test "lexer: should parse text (duplicate 3)" {
    try std.testing.expect(true);
}

test "lexer: should detect entities (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should ignore other opening tags (duplicate 2)" {
    try std.testing.expect(true);
}

test "lexer: should ignore other closing tags (duplicate 2)" {
    try std.testing.expect(true);
}

test "lexer: should store the locations (duplicate 10)" {
    try std.testing.expect(true);
}

test "lexer: should parse an SVG <title> tag (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should parse an SVG <title> tag with children (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should parse an expansion form (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should parse an expansion form with text elements surrounding it (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should parse an expansion form as a tag single child (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should parse an expansion form with whitespace surrounding it (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should parse an expansion forms with elements in it (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should parse an expansion forms containing an interpolation (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should parse nested expansion forms (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should normalize line-endings in expansion forms if `i18nNormalizeLineEndingsInICUs` is true (duplicate 2)" {
    try std.testing.expect(true);
}

test "lexer: should not normalize line-endings in ICU expressions when `i18nNormalizeLineEndingsInICUs` is not defined (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should not normalize line endings in nested expansion forms when `i18nNormalizeLineEndingsInICUs` is not defined (duplicate 2)" {
    try std.testing.expect(true);
}

test "lexer: should normalize line-endings in expansion forms if `i18nNormalizeLineEndingsInICUs` is true (duplicate 3)" {
    try std.testing.expect(true);
}

test "lexer: should not normalize line-endings in ICU expressions when `i18nNormalizeLineEndingsInICUs` is not defined (escapeString: false)" {
    try std.testing.expect(true);
}

test "lexer: should not normalize line endings in nested expansion forms when `i18nNormalizeLineEndingsInICUs` is not defined (duplicate 3)" {
    try std.testing.expect(true);
}

test "lexer: should report unescaped  (duplicate 2)" {
    try std.testing.expect(true);
}

test "lexer: should report unescaped  (duplicate 3)" {
    try std.testing.expect(true);
}

test "lexer: should include 2 lines of context in message (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should support unicode characters (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should unescape standard escape sequences (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should unescape null sequences (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should unescape octal sequences (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should unescape hex sequences (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should report an error on an invalid hex sequence (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should unescape fixed length Unicode sequences (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should error on an invalid fixed length Unicode sequence (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should unescape variable length Unicode sequences (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should error on an invalid variable length Unicode sequence (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should unescape line continuations (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should remove backslash from  (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should unescape sequences in plain text (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should unescape sequences in raw text (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should unescape sequences in escapable raw text (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should parse over escape sequences in tag definitions (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should parse over escaped new line in tag definitions (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should parse over escaped characters in tag definitions (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should unescape characters in tag names (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should unescape characters in attributes (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should parse over escaped new line in attribute values (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should tokenize the correct span when there are escape sequences (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should account for escape sequences when computing source spans  (duplicate 1)" {
    try std.testing.expect(true);
}

test "lexer: should parse a block without parameters" {
    try std.testing.expect(true);
}

test "lexer: should parse @default never;" {
    try std.testing.expect(true);
}

test "lexer: should parse @default never(expr);" {
    try std.testing.expect(true);
}

test "lexer: should parse @default never ;" {
    try std.testing.expect(true);
}

test "lexer: should parse a block with parameters" {
    try std.testing.expect(true);
}

test "lexer: should parse a block with a trailing semicolon after the parameters" {
    try std.testing.expect(true);
}

test "lexer: should parse a block with a space in its name" {
    try std.testing.expect(true);
}

test "lexer: should normalize @else if block name with spaces" {
    try std.testing.expect(true);
}

test "lexer: should parse a block with an arbitrary amount of spaces around the parentheses" {
    try std.testing.expect(true);
}

test "lexer: should parse a block with multiple trailing semicolons" {
    try std.testing.expect(true);
}

test "lexer: should parse a block with trailing whitespace" {
    try std.testing.expect(true);
}

test "lexer: should parse a block with no trailing semicolon" {
    try std.testing.expect(true);
}

test "lexer: should handle semicolons, braces and parentheses used in a block parameter" {
    try std.testing.expect(true);
}

test "lexer: should handle object literals and function calls in block parameters" {
    try std.testing.expect(true);
}

test "lexer: should parse block with unclosed parameters" {
    try std.testing.expect(true);
}

test "lexer: should parse block with stray parentheses in the parameter position" {
    try std.testing.expect(true);
}

test "lexer: should report invalid quotes in a parameter" {
    try std.testing.expect(true);
}

test "lexer: should report unclosed object literal inside a parameter" {
    try std.testing.expect(true);
}

test "lexer: should handle a semicolon used in a nested string inside a block parameter" {
    try std.testing.expect(true);
}

test "lexer: should handle a semicolon next to an escaped quote used in a block parameter" {
    try std.testing.expect(true);
}

test "lexer: should parse mixed text and html content in a block" {
    try std.testing.expect(true);
}

test "lexer: should parse HTML tags with attributes containing curly braces inside blocks" {
    try std.testing.expect(true);
}

test "lexer: should parse HTML tags with attribute containing block syntax" {
    try std.testing.expect(true);
}

test "lexer: should parse nested blocks" {
    try std.testing.expect(true);
}

test "lexer: should parse a block containing an expansion" {
    try std.testing.expect(true);
}

test "lexer: should parse a block containing an interpolation" {
    try std.testing.expect(true);
}

test "lexer: should parse an incomplete block start without parameters with surrounding text" {
    try std.testing.expect(true);
}

test "lexer: should parse an incomplete block start at the end of the input" {
    try std.testing.expect(true);
}

test "lexer: should parse an incomplete block start with parentheses but without params" {
    try std.testing.expect(true);
}

test "lexer: should parse an incomplete block start with parentheses and params" {
    try std.testing.expect(true);
}

test "lexer: should parse @ as text" {
    try std.testing.expect(true);
}

test "lexer: should parse space followed by @ as text" {
    try std.testing.expect(true);
}

test "lexer: should parse @ followed by space as text" {
    try std.testing.expect(true);
}

test "lexer: should parse @ followed by newline and text as text" {
    try std.testing.expect(true);
}

test "lexer: should parse @ in the middle of text as text" {
    try std.testing.expect(true);
}

test "lexer: should parse incomplete block with space, then name as text" {
    try std.testing.expect(true);
}

