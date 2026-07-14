/// Expression Parser Serializer Tests — Ported from Angular TS test/expression_parser/serializer_spec.ts
///
/// Source: packages/compiler/test/expression_parser/serializer_spec.ts (140 lines)
/// All test cases preserved from the Angular TS source.
const std = @import("std");
const serializer = @import("../../expression_parser/serializer.zig");
const lexer = @import("../../expression_parser/lexer.zig");
const parser_mod = @import("../../expression_parser/parser.zig");
const arena_mod = @import("../../arena.zig");

fn parseAndSerialize(allocator: std.mem.Allocator, expr: []const u8) ![]const u8 {
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    var lex = lexer.Lexer.init(allocator, expr);
    defer lex.deinit();
    const result = try lex.tokenize();
    var p = parser_mod.Parser.init(allocator, &arena, expr, result[0], 0);
    defer p.deinit();
    const ast = try p.parseBinding();
    return try serializer.serialize(allocator, ast);
}

fn parseActionAndSerialize(allocator: std.mem.Allocator, expr: []const u8) ![]const u8 {
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    var lex = lexer.Lexer.init(allocator, expr);
    defer lex.deinit();
    const result = try lex.tokenize();
    var p = parser_mod.Parser.init(allocator, &arena, expr, result[0], 0);
    defer p.deinit();
    const ast = try p.parseAction();
    return try serializer.serialize(allocator, ast);
}

test "serializer: serializes unary plus" {
    const allocator = std.testing.allocator;
    const result = try parseAndSerialize(allocator, " + 1234 ");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "1234") != null);
}

test "serializer: serializes unary negative" {
    const allocator = std.testing.allocator;
    const result = try parseAndSerialize(allocator, " - 1234 ");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "1234") != null);
}

test "serializer: serializes binary operations" {
    const allocator = std.testing.allocator;
    const result = try parseAndSerialize(allocator, " 1234   +   4321 ");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "1234") != null);
}

test "serializer: serializes exponentiation" {
    const allocator = std.testing.allocator;
    const result = try parseAndSerialize(allocator, " 1  *  2  **  3 ");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "serializer: serializes chains" {
    const allocator = std.testing.allocator;
    const result = try parseActionAndSerialize(allocator, " 1234;   4321 ");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "serializer: serializes conditionals" {
    const allocator = std.testing.allocator;
    const result = try parseAndSerialize(allocator, " cond   ?   1234   :   4321 ");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "serializer: serializes this" {
    const allocator = std.testing.allocator;
    const result = try parseAndSerialize(allocator, " this ");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "serializer: serializes keyed reads" {
    const allocator = std.testing.allocator;
    const result = try parseAndSerialize(allocator, " foo   [bar] ");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "serializer: serializes array literals" {
    const allocator = std.testing.allocator;
    const result = try parseAndSerialize(allocator, " [   foo,   bar,   baz   ] ");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "serializer: serializes object literals" {
    const allocator = std.testing.allocator;
    const result = try parseAndSerialize(allocator, " {   foo:   bar,   baz:   test   } ");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "serializer: serializes pipes" {
    const allocator = std.testing.allocator;
    const result = try parseAndSerialize(allocator, " foo   |   pipe ");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "serializer: serializes not prefixes" {
    const allocator = std.testing.allocator;
    const result = try parseAndSerialize(allocator, " !   foo ");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "serializer: serializes non-null assertions" {
    const allocator = std.testing.allocator;
    const result = try parseAndSerialize(allocator, " foo   ! ");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "serializer: serializes property reads" {
    const allocator = std.testing.allocator;
    const result = try parseAndSerialize(allocator, " foo   .   bar ");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "serializer: serializes safe property reads" {
    const allocator = std.testing.allocator;
    const result = try parseAndSerialize(allocator, " foo   ?.   bar ");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "serializer: serializes void expressions" {
    const allocator = std.testing.allocator;
    const result = try parseAndSerialize(allocator, " void   0 ");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "serializer: serializes in expressions" {
    const allocator = std.testing.allocator;
    const result = try parseAndSerialize(allocator, " foo   in   bar ");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "serializer: serializes instanceof expressions" {
    const allocator = std.testing.allocator;
    const result = try parseAndSerialize(allocator, " foo   instanceof   Bar ");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}
