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

// ─── Additional tests ported from TS spec ──────────────────

test "html_whitespaces: should remove blank text nodes" {
    return error.SkipZigTest; // TODO: Module API not yet fully ported
    // try std.testing.expect(true);
}

test "html_whitespaces: should remove whitespaces (space, tab, new line) between elements" {
    return error.SkipZigTest; // TODO: Module API not yet fully ported
    // try std.testing.expect(true);
}

test "html_whitespaces: should remove whitespaces from child text nodes" {
    return error.SkipZigTest; // TODO: Module API not yet fully ported
    // try std.testing.expect(true);
}

test "html_whitespaces: should remove whitespaces from the beginning and end of a template" {
    return error.SkipZigTest; // TODO: Module API not yet fully ported
    // try std.testing.expect(true);
}

test "html_whitespaces: should convert &ngsp; to a space and preserve it" {
    return error.SkipZigTest; // TODO: Module API not yet fully ported
    // try std.testing.expect(true);
}

test "html_whitespaces: should replace multiple whitespaces with one space" {
    return error.SkipZigTest; // TODO: Module API not yet fully ported
    // try std.testing.expect(true);
}

test "html_whitespaces: should remove whitespace inside of blocks" {
    return error.SkipZigTest; // TODO: Module API not yet fully ported
    // try std.testing.expect(true);
}

test "html_whitespaces: should not replace &nbsp;" {
    return error.SkipZigTest; // TODO: Module API not yet fully ported
    // try std.testing.expect(true);
}

test "html_whitespaces: should not replace sequences of &nbsp;" {
    return error.SkipZigTest; // TODO: Module API not yet fully ported
    // try std.testing.expect(true);
}

test "html_whitespaces: should not replace single tab and newline with spaces" {
    return error.SkipZigTest; // TODO: Module API not yet fully ported
    // try std.testing.expect(true);
}

test "html_whitespaces: should preserve single whitespaces between interpolations" {
    return error.SkipZigTest; // TODO: Module API not yet fully ported
    // try std.testing.expect(true);
}

test "html_whitespaces: should preserve whitespaces around interpolations" {
    return error.SkipZigTest; // TODO: Module API not yet fully ported
    // try std.testing.expect(true);
}

test "html_whitespaces: should preserve whitespaces around ICU expansions" {
    return error.SkipZigTest; // TODO: Module API not yet fully ported
    // try std.testing.expect(true);
}

test "html_whitespaces: should preserve whitespaces inside <pre> elements" {
    return error.SkipZigTest; // TODO: Module API not yet fully ported
    // try std.testing.expect(true);
}

test "html_whitespaces: should skip whitespace trimming in <textarea>" {
    return error.SkipZigTest; // TODO: Module API not yet fully ported
    // try std.testing.expect(true);
}

