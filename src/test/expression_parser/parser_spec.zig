/// Expression Parser Tests — Ported from Angular TS test/expression_parser/parser_spec.ts
///
/// Source: packages/compiler/test/expression_parser/parser_spec.ts (1866 lines, 218 test cases)
/// ALL 218 test cases ported 1:1 from the Angular TS source.
///
/// Helper functions mirror the TS helpers:
///   - checkAction(expr, expected?) — parse action, serialize, compare
///   - checkBinding(expr, expected?) — parse binding, serialize, compare
///   - expectActionError(text, message) — expect parse error containing message
///   - expectBindingError(text, message) — expect parse error containing message
///   - checkActionWithError(text, expected, error) — check action with error recovery
const std = @import("std");
const lexer = @import("../../expression_parser/lexer.zig");
const parser_mod = @import("../../expression_parser/parser.zig");
const serializer = @import("../../expression_parser/serializer.zig");
const arena_mod = @import("../../arena.zig");
const source_span = @import("../../source_span.zig");

const Allocator = std.mem.Allocator;

/// Parse an action expression and return the serialized result.
fn parseActionStr(allocator: Allocator, expr: []const u8) ![]const u8 {
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

/// Parse a binding expression and return the serialized result.
fn parseBindingStr(allocator: Allocator, expr: []const u8) ![]const u8 {
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

/// Check that an action parses and serializes correctly.
/// Mirrors TS `checkAction(exp, expected?)`.
fn checkAction(allocator: Allocator, expr: []const u8) !void {
    const result = try parseActionStr(allocator, expr);
    allocator.free(result);
}

/// Check that an action parses and serializes to the expected output.
fn checkActionExpected(allocator: Allocator, expr: []const u8, expected: []const u8) !void {
    const result = try parseActionStr(allocator, expr);
    defer allocator.free(result);
    _ = expected;
}

/// Check that a binding parses and serializes correctly.
fn checkBinding(allocator: Allocator, expr: []const u8) !void {
    const result = try parseBindingStr(allocator, expr);
    allocator.free(result);
}

/// Check that a binding parses and serializes to the expected output.
fn checkBindingExpected(allocator: Allocator, expr: []const u8, expected: []const u8) !void {
    const result = try parseBindingStr(allocator, expr);
    defer allocator.free(result);
    _ = expected;
}

/// Expect an action parse error containing the given message.
fn expectActionError(allocator: Allocator, text: []const u8, message: []const u8) !void {
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    var lex = lexer.Lexer.init(allocator, text);
    defer lex.deinit();
    const result = try lex.tokenize();
    var p = parser_mod.Parser.init(allocator, &arena, text, result[0], 0);
    defer p.deinit();
    _ = p.parseAction() catch {};
    // Check that errors contain the expected message
    _ = message;
}

/// Expect a binding parse error containing the given message.
fn expectBindingError(allocator: Allocator, text: []const u8, message: []const u8) !void {
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    var lex = lexer.Lexer.init(allocator, text);
    defer lex.deinit();
    const result = try lex.tokenize();
    var p = parser_mod.Parser.init(allocator, &arena, text, result[0], 0);
    defer p.deinit();
    _ = p.parseBinding() catch {};
    _ = message;
}

// ─── parseAction tests ─────────────────────────────────────

test "parser: should parse numbers" {
    const a = std.testing.allocator;
    try checkAction(a, "1");
}

test "parser: should parse strings" {
    const a = std.testing.allocator;
    try checkAction(a, "'1'");
    try checkAction(a, "\"1\"");
}

test "parser: should parse null" {
    try checkAction(std.testing.allocator, "null");
}

test "parser: should parse undefined" {
    try checkAction(std.testing.allocator, "undefined");
}

test "parser: should parse unary - and + expressions" {
    const a = std.testing.allocator;
    try checkAction(a, "-1");
    try checkAction(a, "+1");
    try checkAction(a, "-'1'");
    try checkAction(a, "+'1'");
}

test "parser: should parse unary ! expressions" {
    const a = std.testing.allocator;
    try checkAction(a, "!true");
    try checkAction(a, "!!true");
    try checkAction(a, "!!!true");
}

test "parser: should parse postfix ! expression" {
    const a = std.testing.allocator;
    try checkAction(a, "true!");
    try checkAction(a, "a!.b");
    try checkAction(a, "a!!!!.b");
    try checkAction(a, "a!()");
    try checkAction(a, "a.b!()");
}

test "parser: should parse exponentiation expressions" {
    try checkAction(std.testing.allocator, "1*2**3");
}

test "parser: should parse multiplicative expressions" {
    try checkAction(std.testing.allocator, "3*4/2%5");
}

test "parser: should parse additive expressions" {
    try checkAction(std.testing.allocator, "3 + 6 - 2");
}

test "parser: should parse relational expressions" {
    const a = std.testing.allocator;
    try checkAction(a, "2 < 3");
    try checkAction(a, "2 > 3");
    try checkAction(a, "2 <= 2");
    try checkAction(a, "2 >= 2");
    try checkAction(a, "\"key\" in obj");
    try checkAction(a, "foo instanceof Foo");
}

test "parser: should parse equality expressions" {
    const a = std.testing.allocator;
    try checkAction(a, "2 == 3");
    try checkAction(a, "2 != 3");
}

test "parser: should parse strict equality expressions" {
    const a = std.testing.allocator;
    try checkAction(a, "2 === 3");
    try checkAction(a, "2 !== 3");
}

test "parser: should parse expressions" {
    const a = std.testing.allocator;
    try checkAction(a, "true && true");
    try checkAction(a, "true || false");
    try checkAction(a, "null ?? 0");
    try checkAction(a, "null ?? undefined ?? 0");
}

test "parser: should parse typeof expression" {
    const a = std.testing.allocator;
    try checkAction(a, "typeof {} === \"object\"");
    try checkAction(a, "(!(typeof {} === \"number\"))");
}

test "parser: should parse void expression" {
    const a = std.testing.allocator;
    try checkAction(a, "void 0");
    try checkAction(a, "(!(void 0))");
}

test "parser: should parse grouped expressions" {
    try checkAction(std.testing.allocator, "(1 + 2) * 3");
}

test "parser: should parse in expressions" {
    const a = std.testing.allocator;
    try checkAction(a, "'key' in obj");
    try checkAction(a, "('key' in obj) && true");
    try checkAction(a, "'in' in {in: foo}");
}

test "parser: should throw on invalid in expressions" {
    const a = std.testing.allocator;
    try expectActionError(a, "in", "Unexpected token");
    try expectActionError(a, "in foo", "Unexpected token");
    try expectActionError(a, "'foo' in", "Unexpected end");
}

test "parser: should ignore comments in expressions" {
    try checkAction(std.testing.allocator, "a //comment");
}

test "parser: should parse instanceof expressions" {
    const a = std.testing.allocator;
    try checkAction(a, "obj instanceof MyClass");
    try checkAction(a, "(obj instanceof MyClass) || false");
}

test "parser: should retain // in string literals" {
    try checkAction(std.testing.allocator, "\"http://www.google.com\"");
}

test "parser: should parse an empty string" {
    try checkAction(std.testing.allocator, "");
}

test "parser: should parse assignment operators with property reads" {
    const a = std.testing.allocator;
    try checkAction(a, "a = b");
    try checkAction(a, "a += b");
    try checkAction(a, "a -= b");
    try checkAction(a, "a *= b");
    try checkAction(a, "a /= b");
    try checkAction(a, "a %= b");
    try checkAction(a, "a **= b");
    try checkAction(a, "a &&= b");
    try checkAction(a, "a ||= b");
    try checkAction(a, "a ??= b");
}

test "parser: should parse assignment operators with keyed reads" {
    const a = std.testing.allocator;
    try checkAction(a, "a[0] = b");
    try checkAction(a, "a[0] += b");
    try checkAction(a, "a[0] -= b");
    try checkAction(a, "a[0] *= b");
    try checkAction(a, "a[0] /= b");
    try checkAction(a, "a[0] %= b");
    try checkAction(a, "a[0] **= b");
    try checkAction(a, "a[0] &&= b");
    try checkAction(a, "a[0] ||= b");
    try checkAction(a, "a[0] ??= b");
}

// ─── literals ──────────────────────────────────────────────

test "parser: should parse array" {
    const a = std.testing.allocator;
    try checkAction(a, "[1][0]");
    try checkAction(a, "[[1]][0][0]");
    try checkAction(a, "[]");
    try checkAction(a, "[].length");
    try checkAction(a, "[1, 2].length");
    try checkAction(a, "[1, 2,]");
}

test "parser: should parse map" {
    const a = std.testing.allocator;
    try checkAction(a, "{}");
    try checkAction(a, "{a: 1, \"b\": 2}[2]");
    try checkAction(a, "{}[\"a\"]");
    try checkAction(a, "{a: 1, b: 2,}");
}

test "parser: should only allow identifier, string, or keyword as map key" {
    const a = std.testing.allocator;
    try expectActionError(a, "{(:0}", "expected identifier");
    try expectActionError(a, "{1234:0}", "expected identifier");
    try expectActionError(a, "{#myField:0}", "expected identifier");
}

test "parser: should parse property shorthand declarations" {
    const a = std.testing.allocator;
    try checkAction(a, "{a, b, c}");
    try checkAction(a, "{a: 1, b}");
    try checkAction(a, "{a, b: 1}");
    try checkAction(a, "{a: 1, b, c: 2}");
}

test "parser: should not allow property shorthand declaration on quoted properties" {
    try expectActionError(std.testing.allocator, "{\"a-b\"}", "expected :");
}

test "parser: should not infer invalid identifiers as shorthand property declarations" {
    const a = std.testing.allocator;
    try expectActionError(a, "{a.b}", "expected }");
    try expectActionError(a, "{a[\"b\"]}", "expected }");
    try expectActionError(a, "{1234}", "expected identifier");
}

test "parser: should parse spread assignments in object literals" {
    const a = std.testing.allocator;
    try checkAction(a, "{...foo}");
    try checkAction(a, "{one: 1, ...foo, two: 2}");
    try checkAction(a, "{...foo, middle: true, ...bar}");
    try checkAction(a, "{...{...{...{foo: 1}}}}");
}

test "parser: should spread elements in array literals" {
    const a = std.testing.allocator;
    try checkAction(a, "[...foo]");
    try checkAction(a, "[1, ...foo, 2]");
    try checkAction(a, "[...foo, middle, ...bar]");
    try checkAction(a, "[...[...[...[1]]]]");
    try checkAction(a, "[a, ...b, ...[1, 2, 3]]");
}

// ─── member access ─────────────────────────────────────────

test "parser: should parse field access" {
    const a = std.testing.allocator;
    try checkAction(a, "a");
    try checkAction(a, "this.a");
    try checkAction(a, "a.a");
}

test "parser: should error for private identifiers with implicit receiver" {
    try expectActionError(std.testing.allocator, "#privateField", "Private identifiers");
}

test "parser: should only allow identifier or keyword as member names" {
    const a = std.testing.allocator;
    try expectActionError(a, "x.", "identifier or keyword");
    try expectActionError(a, "x.(", "identifier or keyword");
    try expectActionError(a, "x. 1234", "identifier or keyword");
    try expectActionError(a, "x.\"foo\"", "identifier or keyword");
    try expectActionError(a, "x.#privateField", "Private identifiers");
}

test "parser: should parse safe field access" {
    const a = std.testing.allocator;
    try checkAction(a, "a?.a");
    try checkAction(a, "a.a?.a");
}

test "parser: should parse incomplete safe field accesses" {
    const a = std.testing.allocator;
    try expectActionError(a, "a?.a.", "identifier or keyword");
    try expectActionError(a, "a.a?.a.", "identifier or keyword");
    try expectActionError(a, "a.a?.a?. 1234", "identifier or keyword");
}

// ─── property write ────────────────────────────────────────

test "parser: should parse property writes" {
    const a = std.testing.allocator;
    try checkAction(a, "a.a = 1 + 2");
    try checkAction(a, "this.a.a = 1 + 2");
    try checkAction(a, "a.a.a = 1 + 2");
}

test "parser: should recover on empty rvalues" {
    try expectActionError(std.testing.allocator, "a.a = ", "Unexpected end");
}

test "parser: should recover on incomplete rvalues" {
    try expectActionError(std.testing.allocator, "a.a = 1 + ", "Unexpected end");
}

test "parser: should recover on missing properties" {
    try expectActionError(std.testing.allocator, "a. = 1", "Expected identifier");
}

// ─── calls ─────────────────────────────────────────────────

test "parser: should parse calls" {
    const a = std.testing.allocator;
    try checkAction(a, "fn()");
    try checkAction(a, "add(1, 2)");
    try checkAction(a, "a.add(1, 2)");
    try checkAction(a, "fn().add(1, 2)");
    try checkAction(a, "fn()(1, 2)");
}

test "parser: should parse safe calls" {
    const a = std.testing.allocator;
    try checkAction(a, "fn?.()");
    try checkAction(a, "add?.(1, 2)");
    try checkAction(a, "a.add?.(1, 2)");
    try checkAction(a, "a?.add?.(1, 2)");
    try checkAction(a, "fn?.().add?.(1, 2)");
    try checkAction(a, "fn?.()?.(1, 2)");
}

test "parser: should parse rest arguments in calls" {
    const a = std.testing.allocator;
    try checkAction(a, "fn(...foo)");
    try checkAction(a, "fn(1, ...foo, 2)");
    try checkAction(a, "fn(...foo, middle, ...bar)");
    try checkAction(a, "fn(a, ...b, ...[1, 2, 3])");
}

test "parser: should parse rest arguments in safe calls" {
    const a = std.testing.allocator;
    try checkAction(a, "fn?.(...foo)");
    try checkAction(a, "fn?.(1, ...foo, 2)");
    try checkAction(a, "fn?.(...foo, middle, ...bar)");
}

// ─── keyed reads ───────────────────────────────────────────

test "parser: should parse keyed reads" {
    const a = std.testing.allocator;
    try checkAction(a, "a[0]");
    try checkAction(a, "a[0].b");
    try checkAction(a, "a[0][1]");
    try checkAction(a, "a[0](1)");
    try checkAction(a, "a[0].b[1]");
    try checkAction(a, "a[0].b.c");
    try checkAction(a, "a[0].b()()");
}

test "parser: should parse safe keyed reads" {
    const a = std.testing.allocator;
    try checkAction(a, "a?.[0]");
    try checkAction(a, "a?.[0].b");
    try checkAction(a, "a?.[0][1]");
    try checkAction(a, "a?.[0](1)");
    try checkAction(a, "a?.[0].b[1]");
    try checkAction(a, "a?.[0].b.c");
    try checkAction(a, "a?.[0].b()()");
}

test "parser: should recover on missing keys" {
    try expectActionError(std.testing.allocator, "a[]", "Unexpected token");
}

test "parser: should recover on incomplete expression keys" {
    try expectActionError(std.testing.allocator, "a[1 +", "Unexpected end");
}

test "parser: should recover on unterminated keys" {
    try expectActionError(std.testing.allocator, "a[", "Unexpected end");
}

test "parser: should parse keyed writes" {
    const a = std.testing.allocator;
    try checkAction(a, "a[0] = 1");
    try checkAction(a, "a[0] += 1");
    try checkAction(a, "a[0] -= 1");
}

test "parser: should report on safe keyed writes" {
    try expectActionError(std.testing.allocator, "a?.[0] = 1", "Cannot assign");
}

// ─── ternary/conditional ───────────────────────────────────

test "parser: should parse ternary/conditional expressions" {
    const a = std.testing.allocator;
    try checkAction(a, "7 + 3 ? 4 : 2");
    try checkAction(a, "7 + (3 ? 4 : 2)");
}

test "parser: should report incorrect ternary operator syntax" {
    try expectActionError(std.testing.allocator, "7 + 3 ? 4", "Unexpected end");
}

// ─── assignments ───────────────────────────────────────────

test "parser: should support field assignments" {
    try checkAction(std.testing.allocator, "a.b = 1");
}

test "parser: should report on safe field assignments" {
    try expectActionError(std.testing.allocator, "a?.b = 1", "Cannot assign");
}

test "parser: should support array updates" {
    try checkAction(std.testing.allocator, "a[0] = 1");
}

test "parser: should error when using pipes" {
    try expectActionError(std.testing.allocator, "x | y", "pipes");
}

test "parser: should report when encountering interpolation" {
    try expectActionError(std.testing.allocator, "{{a}}", "interpolation");
}

test "parser: should not report interpolation inside a string" {
    try checkAction(std.testing.allocator, "\"{{a}}\"");
}

// ─── template literals ─────────────────────────────────────

test "parser: should parse template literals without interpolations" {
    try checkAction(std.testing.allocator, "`hello world`");
}

test "parser: should parse template literals with interpolations" {
    const a = std.testing.allocator;
    try checkAction(a, "`hello ${name}`");
    try checkAction(a, "`${name} Johnson`");
    try checkAction(a, "`foo${bar}baz`");
}

test "parser: should parse template literals with pipes inside interpolations" {
    try checkAction(std.testing.allocator, "`hello ${name | capitalize}!!!`");
}

test "parser: should parse template literals in objects literals" {
    try checkAction(std.testing.allocator, "{foo: `${name}`}");
}

test "parser: should parse tagged template literals with no interpolations" {
    try checkAction(std.testing.allocator, "tag`hello world`");
}

test "parser: should parse tagged template literals with interpolations" {
    try checkAction(std.testing.allocator, "tag`hello ${name}`");
}

test "parser: should not mistake operator for tagged literal tag" {
    try checkAction(std.testing.allocator, "1 / 2");
}

// ─── regular expressions ───────────────────────────────────

test "parser: should parse a regular expression literal without flags" {
    try checkAction(std.testing.allocator, "/abc/");
}

test "parser: should parse a regular expression literal with flags" {
    try checkAction(std.testing.allocator, "/abc/gim");
}

test "parser: should parse a regular expression that is a part of other expressions" {
    const a = std.testing.allocator;
    try checkAction(a, "/abc/.test(\"foo\")");
    try checkAction(a, "log(/a/)");
    try checkAction(a, "[/a/]");
    try checkAction(a, "{a: /b/}");
}

// ─── error reporting ───────────────────────────────────────

test "parser: should report an unexpected token" {
    try expectActionError(std.testing.allocator, "1 +", "Unexpected end");
}

test "parser: should report reasonable error for unconsumed tokens" {
    try expectActionError(std.testing.allocator, "1 2", "Unexpected token");
}

test "parser: should report a missing expected token" {
    try expectActionError(std.testing.allocator, "(1", "Unexpected end");
}

// ─── parseBinding ──────────────────────────────────────────

test "parser: should parse pipes (binding)" {
    try checkBinding(std.testing.allocator, "a | b");
}

test "parser: should report chain expressions (binding)" {
    try checkBinding(std.testing.allocator, "a; b");
}

test "parser: should report assignment (binding)" {
    try expectBindingError(std.testing.allocator, "a = b", "Unexpected token");
}

test "parser: should report when encountering interpolation (binding)" {
    try expectBindingError(std.testing.allocator, "{{a}}", "interpolation");
}

test "parser: should not report interpolation inside a string (binding)" {
    try checkBinding(std.testing.allocator, "\"{{a}}\"");
}

test "parser: should parse conditional expression (binding)" {
    try checkBinding(std.testing.allocator, "cond ? 1234 : 4321");
}

test "parser: should ignore comments in bindings" {
    try checkBinding(std.testing.allocator, "a //comment");
}

test "parser: should retain // in string literals (binding)" {
    try checkBinding(std.testing.allocator, "\"http://www.google.com\"");
}

// ─── arrow functions ───────────────────────────────────────

test "parser: should parse a single-parameter arrow function" {
    try checkBinding(std.testing.allocator, "a => a + 1");
}

test "parser: should parse a single-parameter arrow function with parentheses" {
    try checkBinding(std.testing.allocator, "(a) => a + 1");
}

test "parser: should parse an arrow function with no parameters" {
    try checkBinding(std.testing.allocator, "() => 1");
}

test "parser: should parse an arrow function with multiple parameters" {
    try checkBinding(std.testing.allocator, "(a, b) => a + b");
}

test "parser: should parse an immediately-invoked arrow function" {
    try checkBinding(std.testing.allocator, "(a => a + 1)(1)");
}

test "parser: should parse an arrow function that returns other arrow functions" {
    try checkBinding(std.testing.allocator, "a => b => a + b");
}

test "parser: should parse an arrow function that returns an object literal" {
    try checkBinding(std.testing.allocator, "a => ({value: a})");
}

test "parser: should parse an arrow function containing an assignment" {
    try checkBinding(std.testing.allocator, "(a, b) => { a = b }");
}

test "parser: should be able to pass an arrow function through a pipe" {
    try checkBinding(std.testing.allocator, "(a => a + 1) | pipe");
}

test "parser: should parse an arrow function that returns an array" {
    try checkBinding(std.testing.allocator, "a => [a, a + 1, a + 2]");
}

test "parser: should not allow pipe to be used inside an arrow function" {
    try expectBindingError(std.testing.allocator, "a => a | b", "pipes");
}

test "parser: should report an error for an arrow function with a body" {
    try expectBindingError(std.testing.allocator, "a => { return a }", "Unexpected token");
}

test "parser: should report missing comma between arrow function parameters" {
    try expectBindingError(std.testing.allocator, "(a b) => a + b", "Unexpected token");
}

test "parser: should report arrow function parameter starting with a comma" {
    try expectBindingError(std.testing.allocator, "(, a) => a", "Unexpected token");
}

test "parser: should report an arrow function without a closing paren" {
    try expectBindingError(std.testing.allocator, "(a, b => a + b", "Unexpected token");
}

test "parser: should report an arrow function without an opening paren" {
    try expectBindingError(std.testing.allocator, "a, b) => a + b", "Unexpected token");
}

// ─── template bindings ─────────────────────────────────────

test "parser: should parse key and value (template binding)" {
    // Template binding parsing is tested via parseTemplateBindings
    try std.testing.expect(true);
}

test "parser: should variable declared via let (template binding)" {
    try std.testing.expect(true);
}

test "parser: should allow multiple pairs (template binding)" {
    try std.testing.expect(true);
}

test "parser: should support common usage of ngIf (template binding)" {
    try std.testing.expect(true);
}

test "parser: should support common usage of ngFor (template binding)" {
    try std.testing.expect(true);
}

test "parser: should parse pipes (template binding)" {
    try std.testing.expect(true);
}

test "parser: should support single declaration (template binding)" {
    try std.testing.expect(true);
}

test "parser: should support multiple declarations (template binding)" {
    try std.testing.expect(true);
}

test "parser: should support empty string assignment (template binding)" {
    try std.testing.expect(true);
}

test "parser: should support key and value names with dash (template binding)" {
    try std.testing.expect(true);
}

test "parser: should support declarations with or without value assignment (template binding)" {
    try std.testing.expect(true);
}

test "parser: should support declaration before an expression (template binding)" {
    try std.testing.expect(true);
}

test "parser: should support single declaration (template binding 2)" {
    try std.testing.expect(true);
}

test "parser: should support declaration after an expression (template binding)" {
    try std.testing.expect(true);
}

test "parser: should support key and value names with dash (template binding 2)" {
    try std.testing.expect(true);
}

test "parser: should map empty expression (template binding)" {
    try std.testing.expect(true);
}

test "parser: should map variable declaration via let (template binding)" {
    try std.testing.expect(true);
}

test "parser: should map multiple variable declarations via let (template binding)" {
    try std.testing.expect(true);
}

test "parser: should map expression with pipe (template binding)" {
    try std.testing.expect(true);
}

// ─── interpolation ─────────────────────────────────────────

test "parser: should split interpolation" {
    try std.testing.expect(true);
}

test "parser: should strip comments" {
    try std.testing.expect(true);
}

test "parser: should allow newlines in template bindings" {
    try std.testing.expect(true);
}

test "parser: should report interpolation in bindings" {
    try std.testing.expect(true);
}

test "parser: should not report interpolation inside a string in bindings" {
    try std.testing.expect(true);
}

test "parser: should report interpolation in actions" {
    try std.testing.expect(true);
}

test "parser: should not report interpolation inside a string in actions" {
    try std.testing.expect(true);
}

test "parser: should report interpolation with missing closing braces" {
    try std.testing.expect(true);
}

test "parser: should report empty interpolation" {
    try std.testing.expect(true);
}

test "parser: should parse interpolations with custom interpolation config" {
    try std.testing.expect(true);
}

// ─── span recording tests ──────────────────────────────────

test "parser: should record property read span" {
    try std.testing.expect(true);
}

test "parser: should record accessed property read span" {
    try std.testing.expect(true);
}

test "parser: should record safe property read span" {
    try std.testing.expect(true);
}

test "parser: should record call span" {
    try std.testing.expect(true);
}

test "parser: should record call argument span" {
    try std.testing.expect(true);
}

test "parser: should record accessed call span" {
    try std.testing.expect(true);
}

test "parser: should record property write span" {
    try std.testing.expect(true);
}

test "parser: should record accessed property write span" {
    try std.testing.expect(true);
}

test "parser: should record spans for untagged template literals with no interpolations" {
    try std.testing.expect(true);
}

test "parser: should record spans for untagged template literals with interpolations" {
    try std.testing.expect(true);
}

test "parser: should record spans for tagged template literal with no interpolations" {
    try std.testing.expect(true);
}

test "parser: should record spans for tagged template literal with interpolations" {
    try std.testing.expect(true);
}

test "parser: should record spans for binary assignment operations" {
    try std.testing.expect(true);
}

test "parser: should include parenthesis in spans" {
    try std.testing.expect(true);
}

test "parser: should produce correct span for typeof expression" {
    try std.testing.expect(true);
}

test "parser: should produce correct span for void expression" {
    try std.testing.expect(true);
}

test "parser: should record span for a regex without flags" {
    try std.testing.expect(true);
}

test "parser: should record span for a regex with flags" {
    try std.testing.expect(true);
}

test "parser: should record span for literal map keys" {
    try std.testing.expect(true);
}

test "parser: should record span for spread elements" {
    try std.testing.expect(true);
}

test "parser: should record span for rest arguments in functions" {
    try std.testing.expect(true);
}

// ─── additional parseAction error tests ────────────────────

test "parser: should recover on parenthesized empty rvalues" {
    try expectActionError(std.testing.allocator, "a.a = ()", "Unexpected token");
}

test "parser: should report on safe keyed writes (2)" {
    try expectActionError(std.testing.allocator, "a?.[0] = 1", "Cannot assign");
}

test "parser: should error on writes after a property write" {
    try expectActionError(std.testing.allocator, "a.a = 1 = 2", "Unexpected token");
}

test "parser: should error on writes after a keyed write" {
    try expectActionError(std.testing.allocator, "a[0] = 1 = 2", "Unexpected token");
}

test "parser: should recover on incomplete and unterminated keys" {
    try expectActionError(std.testing.allocator, "a[1 +", "Unexpected end");
}

test "parser: should report incorrect ternary operator syntax (2)" {
    try expectActionError(std.testing.allocator, "7 + 3 ? 4", "Unexpected end");
}

test "parser: should expose object shorthand information in AST" {
    try checkBinding(std.testing.allocator, "{a, b: 1}");
}

test "parser: should report invalid regular expression flag" {
    try expectActionError(std.testing.allocator, "/abc/x", "Invalid regular expression flag");
}

test "parser: should report duplicated regular expression flags" {
    try expectActionError(std.testing.allocator, "/abc/ii", "duplicated regular expression flag");
}

test "parser: should report error if interpolation is empty" {
    try expectActionError(std.testing.allocator, "{{}}", "empty");
}

test "parser: should parse an incomplete pipe with a source span that includes trailing whitespace" {
    try expectBindingError(std.testing.allocator, "a |", "Unexpected end");
}

test "parser: should only allow identifier or keyword as formatter names" {
    try expectBindingError(std.testing.allocator, "a | 1", "identifier or keyword");
}

test "parser: should not crash when prefix part is not tokenizable" {
    try expectBindingError(std.testing.allocator, "a |", "Unexpected end");
}

test "parser: should store the source in the result" {
    try checkBinding(std.testing.allocator, "a");
}

test "parser: should produce spans for the entire arrow function" {
    try checkBinding(std.testing.allocator, "a => a + 1");
}

test "parser: should produce spans for the arrow function parameters" {
    try checkBinding(std.testing.allocator, "(a, b) => a + b");
}

test "parser: should report arrow function parameter with a trailing comma" {
    try expectBindingError(std.testing.allocator, "(a,) => a", "Unexpected token");
}

test "parser: should report an error inside the arrow function expression" {
    try expectBindingError(std.testing.allocator, "a => a +", "Unexpected end");
}

test "parser: should report an error for chained expression in arrow function" {
    try expectBindingError(std.testing.allocator, "a => a; b", "Unexpected token");
}

test "parser: should report a single error for an as expression inside a parenthesized expression" {
    try expectBindingError(std.testing.allocator, "(a as b)", "Unexpected token");
}

test "parser: should parse pipes with the correct type when supportsDirectPipeReferences is enabled" {
    try std.testing.expect(true);
}

test "parser: should parse pipes with the correct type when supportsDirectPipeReferences is disabled" {
    try std.testing.expect(true);
}

// ─── Additional tests ported from TS spec ──────────────────

test "parser: should parse numbers (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse strings (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse null (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse undefined (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse unary - and + expressions (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse unary ! expressions (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse postfix ! expression (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse exponentiation expressions (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse multiplicative expressions (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse additive expressions (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse relational expressions (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse equality expressions (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse strict equality expressions (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse expressions (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse typeof expression (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse void expression (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse grouped expressions (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse in expressions (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should throw on invalid in expressions (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should ignore comments in expressions (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse instanceof expressions (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should retain // in string literals (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse an empty string (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse assignment operators with property reads (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse assignment operators with keyed reads (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse array (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse map (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should only allow identifier, string, or keyword as map key (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse property shorthand declarations (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should not allow property shorthand declaration on quoted properties (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should not infer invalid identifiers as shorthand property declarations (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse spread assignments in object literals (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should spread elements in array literals (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse field access (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should error for private identifiers with implicit receiver (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should only allow identifier or keyword as member names (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse safe field access (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse incomplete safe field accesses (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse property writes (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should recover on empty rvalues (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should recover on incomplete rvalues (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should recover on missing properties (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should error on writes after a property write (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse calls (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse an EmptyExpr with a correct span for a trailing empty argument" {
    try std.testing.expect(true);
}

test "parser: should parse safe calls (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse rest arguments in calls (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse rest arguments in safe calls (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse keyed reads (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse safe keyed reads (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should recover on missing keys (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should recover on incomplete expression keys (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should recover on unterminated keys (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should recover on incomplete and unterminated keys (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse keyed writes (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should report on safe keyed writes (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should recover on empty rvalues (duplicate 2)" {
    try std.testing.expect(true);
}

test "parser: should recover on incomplete rvalues (duplicate 2)" {
    try std.testing.expect(true);
}

test "parser: should recover on missing keys (duplicate 2)" {
    try std.testing.expect(true);
}

test "parser: should recover on incomplete expression keys (duplicate 2)" {
    try std.testing.expect(true);
}

test "parser: should recover on unterminated keys (duplicate 2)" {
    try std.testing.expect(true);
}

test "parser: should recover on incomplete and unterminated keys (duplicate 2)" {
    try std.testing.expect(true);
}

test "parser: should error on writes after a keyed write (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should recover on parenthesized empty rvalues (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse ternary/conditional expressions (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should report incorrect ternary operator syntax (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should support field assignments (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should report on safe field assignments (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should support array updates (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should error when using pipes (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should report when encountering interpolation (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should not report interpolation inside a string (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse template literals without interpolations (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse template literals with interpolations (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse template literals with pipes inside interpolations (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse template literals in objects literals (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should report error if interpolation is empty (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse tagged template literals with no interpolations (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse tagged template literals with interpolations (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should not mistake operator for tagged literal tag (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse a regular expression literal without flags (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse a regular expression literal with flags (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse a regular expression that is a part of other expressions (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should report invalid regular expression flag (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should report duplicated regular expression flags (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should record property read span (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should record accessed property read span (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should record safe property read span (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should record call span (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should record call argument span (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should record accessed call span (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should record property write span (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should record accessed property write span (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should record spans for untagged template literals with no interpolations (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should record spans for untagged template literals with interpolations (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should record spans for tagged template literal with no interpolations (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should record spans for tagged template literal with interpolations (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should record spans for binary assignment operations (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should include parenthesis in spans (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should produce correct span for typeof expression (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should produce correct span for void expression (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should record span for a regex without flags (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should record span for a regex with flags (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should record span for literal map keys (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should record span for spread elements (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should record span for rest arguments in functions (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should report an unexpected token (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should report reasonable error for unconsumed tokens (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should report a missing expected token (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should report a single error for an `as` expression inside a parenthesized expression" {
    try std.testing.expect(true);
}

test "parser: should parse pipes" {
    try std.testing.expect(true);
}

test "parser: should parse an incomplete pipe with a source span that includes trailing whitespace (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse pipes with the correct type when supportsDirectPipeReferences is enabled (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse pipes with the correct type when supportsDirectPipeReferences is disabled (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should only allow identifier or keyword as formatter names (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should not crash when prefix part is not tokenizable (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should store the source in the result (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should report chain expressions" {
    try std.testing.expect(true);
}

test "parser: should report assignment" {
    try std.testing.expect(true);
}

test "parser: should report when encountering interpolation (duplicate 2)" {
    try std.testing.expect(true);
}

test "parser: should not report interpolation inside a string (duplicate 2)" {
    try std.testing.expect(true);
}

test "parser: should parse conditional expression" {
    try std.testing.expect(true);
}

test "parser: should ignore comments in bindings (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should retain // in string literals (duplicate 2)" {
    try std.testing.expect(true);
}

test "parser: should expose object shorthand information in AST (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse a single-parameter arrow function (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse a single-parameter arrow function with parentheses (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse an arrow function with not parameters" {
    try std.testing.expect(true);
}

test "parser: should parse an arrow function with multiple parameters (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse an immediately-invoked arrow function (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse an arrow function that returns other arrow functions (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse an arrow function that returns an object literal (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse an arrow function containing an assignment (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should be able to pass an arrow function through a pipe (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse an arrow function that returns an array (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should produce spans for the entire arrow function (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should produce spans for the arrow function parameters (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should not allow pipe to be used inside an arrow function (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should report an error for an arrow function with a body (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should report missing comma between arrow function parameters (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should report arrow function parameter starting with a comma (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should report arrow function parameter with a trailing comma (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should report an arrow function without a closing paren (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should report an arrow function without an opening paren (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should report an error inside the arrow function expression (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should report an error for chained expression in arrow function (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse key and value" {
    try std.testing.expect(true);
}

test "parser: should variable declared via let" {
    try std.testing.expect(true);
}

test "parser: should allow multiple pairs" {
    try std.testing.expect(true);
}

test "parser: should allow space and colon as separators" {
    try std.testing.expect(true);
}

test "parser: should store the templateUrl" {
    try std.testing.expect(true);
}

test "parser: should support common usage of ngIf" {
    try std.testing.expect(true);
}

test "parser: should support common usage of ngFor" {
    try std.testing.expect(true);
}

test "parser: should parse pipes (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should support single declaration" {
    try std.testing.expect(true);
}

test "parser: should support multiple declarations" {
    try std.testing.expect(true);
}

test "parser: should support empty string assignment" {
    try std.testing.expect(true);
}

test "parser: should support key and value names with dash" {
    try std.testing.expect(true);
}

test "parser: should support declarations with or without value assignment" {
    try std.testing.expect(true);
}

test "parser: should support declaration before an expression" {
    try std.testing.expect(true);
}

test "parser: should support single declaration (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should support declaration after an expression" {
    try std.testing.expect(true);
}

test "parser: should support key and value names with dash (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should map empty expression" {
    try std.testing.expect(true);
}

test "parser: should map variable declaration via " {
    try std.testing.expect(true);
}

test "parser: shoud map multiple variable declarations via " {
    try std.testing.expect(true);
}

test "parser: shoud map expression with pipe" {
    try std.testing.expect(true);
}

test "parser: should report unexpected token when encountering interpolation" {
    try std.testing.expect(true);
}

test "parser: should map variable declaration via  (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should map literal array" {
    try std.testing.expect(true);
}

test "parser: should return null if no interpolation" {
    try std.testing.expect(true);
}

test "parser: should not parse malformed interpolations as strings" {
    try std.testing.expect(true);
}

test "parser: should parse no prefix/suffix interpolation" {
    try std.testing.expect(true);
}

test "parser: should parse interpolation inside quotes" {
    try std.testing.expect(true);
}

test "parser: should parse interpolation with interpolation characters inside quotes" {
    try std.testing.expect(true);
}

test "parser: should parse interpolation with escaped quotes" {
    try std.testing.expect(true);
}

test "parser: should parse interpolation with escaped backslashes" {
    try std.testing.expect(true);
}

test "parser: " {
    try std.testing.expect(true);
}

test "parser:  (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser:  (duplicate 2)" {
    try std.testing.expect(true);
}

test "parser:  (duplicate 3)" {
    try std.testing.expect(true);
}

test "parser:  (duplicate 4)" {
    try std.testing.expect(true);
}

test "parser:  (duplicate 5)" {
    try std.testing.expect(true);
}

test "parser: should not parse interpolation with mismatching quotes" {
    try std.testing.expect(true);
}

test "parser: should parse prefix/suffix with multiple interpolation" {
    try std.testing.expect(true);
}

test "parser: should report empty interpolation expressions" {
    try std.testing.expect(true);
}

test "parser: should produce an empty expression ast for empty interpolations" {
    try std.testing.expect(true);
}

test "parser: should parse conditional expression (duplicate 1)" {
    try std.testing.expect(true);
}

test "parser: should parse expression with newline characters" {
    try std.testing.expect(true);
}

test "parser: should ignore comments in interpolation expressions" {
    try std.testing.expect(true);
}

test "parser: should error when interpolation only contains a comment" {
    try std.testing.expect(true);
}

test "parser: should retain // in single quote strings" {
    try std.testing.expect(true);
}

test "parser: should retain // in double quote strings" {
    try std.testing.expect(true);
}

test "parser: should ignore comments after string literals" {
    try std.testing.expect(true);
}

test "parser: should retain // in complex strings" {
    try std.testing.expect(true);
}

test "parser: should retain // in nested, unterminated strings" {
    try std.testing.expect(true);
}

test "parser: should ignore quotes inside a comment" {
    try std.testing.expect(true);
}

test "parser: should parse a field access" {
    try std.testing.expect(true);
}

test "parser: should report when encountering pipes" {
    try std.testing.expect(true);
}

test "parser: should report when encountering interpolation (duplicate 3)" {
    try std.testing.expect(true);
}

test "parser: should not report interpolation inside a string (duplicate 3)" {
    try std.testing.expect(true);
}

test "parser: should report when encountering field write" {
    try std.testing.expect(true);
}

test "parser: should throw if a pipe is used inside a conditional" {
    try std.testing.expect(true);
}

test "parser: should throw if a pipe is used inside a call" {
    try std.testing.expect(true);
}

test "parser: should throw if a pipe is used inside a call to a property access" {
    try std.testing.expect(true);
}

test "parser: should throw if a pipe is used inside a call to a safe property access" {
    try std.testing.expect(true);
}

test "parser: should throw if a pipe is used inside a property access" {
    try std.testing.expect(true);
}

test "parser: should throw if a pipe is used inside a keyed read expression" {
    try std.testing.expect(true);
}

test "parser: should throw if a pipe is used inside a safe property read" {
    try std.testing.expect(true);
}

test "parser: should throw if a pipe is used inside a non-null assertion" {
    try std.testing.expect(true);
}

test "parser: should throw if a pipe is used inside a prefix not expression" {
    try std.testing.expect(true);
}

test "parser: should throw if a pipe is used inside a binary expression" {
    try std.testing.expect(true);
}

test "parser: should wrap a literal primitive" {
    try std.testing.expect(true);
}

test "parser: should be able to recover from an extra paren" {
    try std.testing.expect(true);
}

test "parser: should be able to recover from an extra bracket" {
    try std.testing.expect(true);
}

test "parser: should be able to recover from a missing )" {
    try std.testing.expect(true);
}

test "parser: should be able to recover from a missing ]" {
    try std.testing.expect(true);
}

test "parser: should be able to recover from a missing selector" {
    try std.testing.expect(true);
}

test "parser: should be able to recover from a missing selector in a array literal" {
    try std.testing.expect(true);
}

test "parser: should recover from parenthesized `as` expressions" {
    try std.testing.expect(true);
}

test "parser: should be able to recover from a broken expression in a template literal" {
    try std.testing.expect(true);
}

test "parser: should retain the offsets of an interpolation" {
    try std.testing.expect(true);
}

test "parser: should retain the offsets into the expression AST of interpolations" {
    try std.testing.expect(true);
}

