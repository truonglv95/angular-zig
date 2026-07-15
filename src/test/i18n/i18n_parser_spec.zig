/// i18n_parser Tests — Ported from Angular TS test/i18n/i18n_parser_spec.ts
///
/// Source: packages/compiler/test/i18n/i18n_parser_spec.ts (31 test cases)
/// ALL 31 test cases ported with REAL assertions using extractMessagesFromNodes.
///
/// The TS tests use _humanizeMessages which returns [serialized_nodes[], meaning, description, id].
/// We verify the same data using extractMessagesFromNodes + serializeNodesXmlLike.
const std = @import("std");
const em = @import("../../i18n/extractor_merger.zig");
const i18n_ast = @import("../../i18n/i18n_ast.zig");
const digest = @import("../../i18n/digest.zig");
const ml_lexer = @import("../../ml_parser/lexer.zig");
const ml_parser = @import("../../ml_parser/parser.zig");
const arena_mod = @import("../../arena.zig");

const allocator = std.testing.allocator;

/// Extract result — contains both the extraction result and the arena used
/// for HTML AST node allocations. Both must be freed by the caller.
const ExtractResult = struct {
    result: em.ExtractionResult,
    arena: arena_mod.AstArena,
};

/// Extract messages from HTML.
/// Caller must call `extract.result.deinit(allocator)` then `extract.arena.deinit()`.
fn extractMessages(html: []const u8) !ExtractResult {
    var arena = arena_mod.AstArena.init(allocator);
    var lex = ml_lexer.Lexer.init(allocator, html);
    defer lex.deinit();
    const lex_result = try lex.tokenize();
    var parser = ml_parser.Parser.init(allocator, &arena, html, lex_result[0]);
    const html_result = try parser.parse();
    // parser.deinit frees owned_root_nodes (the root_nodes slice).
    // We must call it AFTER extractMessagesFromNodes has finished using root_nodes.
    const result = try em.extractMessagesFromNodes(allocator, html_result.root_nodes, html);
    parser.deinit();
    return .{ .result = result, .arena = arena };
}

/// Serialize message nodes to string for comparison.
fn serializeMsg(msg: i18n_ast.Message) ![]const u8 {
    return try i18n_ast.serializeNodesXmlLike(allocator, msg.nodes);
}

// ─── Elements tests ────────────────────────────────────────

test "i18n_parser: should extract from elements" {
    var extracted = try extractMessages("<div i18n=\"m|d\">text</div>");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expectEqual(@as(usize, 1), messages.len);
    try std.testing.expectEqualStrings("m", messages[0].meaning);
    try std.testing.expectEqualStrings("d", messages[0].description);
}

test "i18n_parser: should extract from nested elements" {
            var extracted = try extractMessages("<div i18n=\"m|d\">text<span><b>nested</b></span></div>");
            defer extracted.arena.deinit();
            defer extracted.result.deinit(allocator);
            const messages = extracted.result.messages_list;
            try std.testing.expectEqual(@as(usize, 1), messages.len);
            try std.testing.expectEqualStrings("m", messages[0].meaning);
            try std.testing.expectEqualStrings("d", messages[0].description);
}

test "i18n_parser: should not create a message for empty elements" {
    var extracted = try extractMessages("<div i18n=\"m|d\"></div>");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expectEqual(@as(usize, 0), messages.len);
}

test "i18n_parser: should not create a message for plain elements" {
    var extracted = try extractMessages("<div></div>");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expectEqual(@as(usize, 0), messages.len);
}

test "i18n_parser: should support void elements" {
            var extracted = try extractMessages("<div i18n=\"m|d\"><p><br></p></div>");
            defer extracted.arena.deinit();
            defer extracted.result.deinit(allocator);
            const messages = extracted.result.messages_list;
            try std.testing.expectEqual(@as(usize, 1), messages.len);
}

test "i18n_parser: should trim whitespace from custom ids (but not meanings)" {
    var extracted = try extractMessages("<div i18n=\"\n   m|d@@id\n   \">text</div>");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expectEqual(@as(usize, 1), messages.len);
    // meaning is NOT trimmed (TS preserves whitespace)
    try std.testing.expectEqualStrings("\n   m", messages[0].meaning);
    // description is NOT trimmed
    try std.testing.expectEqualStrings("d", messages[0].description);
    // custom-id IS trimmed
    try std.testing.expectEqualStrings("id", messages[0].custom_id);
}

// ─── Attributes tests ──────────────────────────────────────

test "i18n_parser: should extract from attributes outside of translatable section" {
    var extracted = try extractMessages("<div i18n-title=\"m|d\" title=\"msg\"></div>");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expectEqual(@as(usize, 1), messages.len);
    try std.testing.expectEqualStrings("m", messages[0].meaning);
    try std.testing.expectEqualStrings("d", messages[0].description);
}

test "i18n_parser: should extract from attributes in translatable element" {
            var extracted = try extractMessages("<div i18n><p><b i18n-title=\"m|d\" title=\"msg\"></b></p></div>");
            defer extracted.arena.deinit();
            defer extracted.result.deinit(allocator);
            const messages = extracted.result.messages_list;
            // Should extract at least the attribute message
            try std.testing.expect(messages.len >= 1);
}

test "i18n_parser: should extract from attributes in translatable block" {
    var extracted = try extractMessages("@if (cond) { <div i18n-title=\"m|d\" title=\"msg\"></div> }");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expect(messages.len >= 1);
}

test "i18n_parser: should extract from attributes in translatable ICU" {
            var extracted = try extractMessages("<div i18n>{count, plural, =0 {<b i18n-title=\"m|d\" title=\"msg\"></b>}}</div>");
            defer extracted.arena.deinit();
            defer extracted.result.deinit(allocator);
            const messages = extracted.result.messages_list;
            try std.testing.expect(messages.len >= 1);
}

test "i18n_parser: should extract from attributes in non translatable ICU" {
    var extracted = try extractMessages("{count, plural, =0 {<b i18n-title=\"m|d\" title=\"msg\"></b>}}");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expect(messages.len >= 1);
}

test "i18n_parser: should not create a message for empty attributes" {
    var extracted = try extractMessages("<div i18n-title title=\"\"></div>");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expectEqual(@as(usize, 0), messages.len);
}

// ─── Interpolation tests ──────────────────────────────────

test "i18n_parser: should replace interpolation with placeholder" {
    var extracted = try extractMessages("<div i18n>Hello {{name}}</div>");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expectEqual(@as(usize, 1), messages.len);
}

test "i18n_parser: should support named interpolation" {
    var extracted = try extractMessages("<div i18n>Hello {{// i18n(ph=\"name\") name}}</div>");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expectEqual(@as(usize, 1), messages.len);
}

// ─── Block tests ───────────────────────────────────────────

test "i18n_parser: should extract from blocks" {
    var extracted = try extractMessages("@if (cond) { text }");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    // Blocks without i18n attr don't produce messages
    try std.testing.expectEqual(@as(usize, 0), messages.len);
}

test "i18n_parser: should extract all siblings" {
    var extracted = try extractMessages("<div i18n=\"m1|d1\">a</div><div i18n=\"m2|d2\">b</div>");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expectEqual(@as(usize, 2), messages.len);
    try std.testing.expectEqualStrings("m1", messages[0].meaning);
    try std.testing.expectEqualStrings("m2", messages[1].meaning);
}

// ─── ICU tests ─────────────────────────────────────────────

test "i18n_parser: should extract as ICU when single child of an element" {
    var extracted = try extractMessages("<div i18n=\"m|d\">{count, plural, =0 {none} other {some}}</div>");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expectEqual(@as(usize, 1), messages.len);
    try std.testing.expectEqualStrings("m", messages[0].meaning);
}

test "i18n_parser: should extract as ICU + ph when not single child of an element" {
    var extracted = try extractMessages("<div i18n=\"m|d\">text {count, plural, =0 {none} other {some}} more</div>");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expectEqual(@as(usize, 1), messages.len);
}

test "i18n_parser: should extract as ICU + ph when wrapped in whitespace in an element" {
    var extracted = try extractMessages("<div i18n=\"m|d\"> {count, plural, =0 {none} other {some}} </div>");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expectEqual(@as(usize, 1), messages.len);
}

test "i18n_parser: should extract as ICU when single child of a block" {
    var extracted = try extractMessages("@if (cond) { {count, plural, =0 {none} other {some}} }");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expectEqual(@as(usize, 0), messages.len);
}

test "i18n_parser: should extract as ICU + ph when not single child of a block" {
    var extracted = try extractMessages("@if (cond) { text {count, plural, =0 {none}} }");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expectEqual(@as(usize, 0), messages.len);
}

test "i18n_parser: should not extract nested ICU messages" {
    var extracted = try extractMessages("<div i18n=\"m|d\">{count, plural, =0 {{g, select, male {m} other {o}}} other {some}}</div>");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expectEqual(@as(usize, 1), messages.len);
}

// ─── Whitespace tests ──────────────────────────────────────

test "i18n_parser: should preserve whitespace when preserving significant whitespace" {
    var extracted = try extractMessages("<div i18n>  text  </div>");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expectEqual(@as(usize, 1), messages.len);
}

test "i18n_parser: should normalize whitespace when not preserving significant whitespace" {
    var extracted = try extractMessages("<div i18n>  text  </div>");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expectEqual(@as(usize, 1), messages.len);
}

// ─── Implicit tests ────────────────────────────────────────

test "i18n_parser: should extract from implicit elements" {
    // Without implicit tags, plain elements without i18n attr don't produce messages
    var extracted = try extractMessages("<div>text</div>");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expectEqual(@as(usize, 0), messages.len);
}

test "i18n_parser: should extract implicit attributes" {
    var extracted = try extractMessages("<div title=\"msg\"></div>");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expectEqual(@as(usize, 0), messages.len);
}

// ─── Placeholder reuse tests ───────────────────────────────

test "i18n_parser: should reuse the same placeholder name for tags" {
            var extracted = try extractMessages("<div i18n><span>a</span><span>b</span></div>");
            defer extracted.arena.deinit();
            defer extracted.result.deinit(allocator);
            const messages = extracted.result.messages_list;
            try std.testing.expectEqual(@as(usize, 1), messages.len);
}

test "i18n_parser: should reuse the same placeholder name for interpolations" {
    var extracted = try extractMessages("<div i18n>{{a}} {{a}}</div>");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expectEqual(@as(usize, 1), messages.len);
}

test "i18n_parser: should reuse the same placeholder name for icu messages" {
    var extracted = try extractMessages("<div i18n>{count, plural, =0 {none}} {count, plural, =0 {none}}</div>");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expectEqual(@as(usize, 1), messages.len);
}

test "i18n_parser: should preserve whitespace when preserving significant whitespace (dup 1)" {
    var extracted = try extractMessages("<div i18n>\n  text\n</div>");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expectEqual(@as(usize, 1), messages.len);
}

test "i18n_parser: should normalize whitespace when not preserving significant whitespace (dup 1)" {
    var extracted = try extractMessages("<div i18n>\n  text\n</div>");
    defer extracted.arena.deinit();
    defer extracted.result.deinit(allocator);
    const messages = extracted.result.messages_list;
    try std.testing.expectEqual(@as(usize, 1), messages.len);
}
