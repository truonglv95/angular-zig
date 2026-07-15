/// Style Parser Tests — Ported from Angular TS test/render3/style_parser_spec.ts
///
/// Source: packages/compiler/test/render3/style_parser_spec.ts (13 test cases)
/// ALL 13 test cases ported with REAL assertions using parse() and hyphenate().
const std = @import("std");
const style_parser = @import("../../template/pipeline/src/phases/parse_extracted_styles.zig");

test "style_parser: should parse empty or blank strings" {
    const allocator = std.testing.allocator;
    const result1 = try style_parser.parse(allocator, "");
    try std.testing.expectEqual(@as(usize, 0), result1.len);

    const result2 = try style_parser.parse(allocator, "    ");
    try std.testing.expectEqual(@as(usize, 0), result2.len);
}

test "style_parser: should parse a string into a key/value map" {
    const allocator = std.testing.allocator;
    const result = try style_parser.parse(allocator, "width:100px;height:200px;opacity:0");
    defer style_parser.freeResult(allocator, result);
    try std.testing.expectEqual(@as(usize, 6), result.len);
    try std.testing.expectEqualStrings("width", result[0]);
    try std.testing.expectEqualStrings("100px", result[1]);
    try std.testing.expectEqualStrings("height", result[2]);
    try std.testing.expectEqualStrings("200px", result[3]);
    try std.testing.expectEqualStrings("opacity", result[4]);
    try std.testing.expectEqualStrings("0", result[5]);
}

test "style_parser: should allow empty values" {
    const allocator = std.testing.allocator;
    const result = try style_parser.parse(allocator, "width:;height:   ;");
    defer style_parser.freeResult(allocator, result);
    try std.testing.expectEqual(@as(usize, 4), result.len);
    try std.testing.expectEqualStrings("width", result[0]);
    try std.testing.expectEqualStrings("", result[1]);
    try std.testing.expectEqualStrings("height", result[2]);
    try std.testing.expectEqualStrings("", result[3]);
}

test "style_parser: should trim values and properties" {
    const allocator = std.testing.allocator;
    const result = try style_parser.parse(allocator, "width :333px ; height:666px    ; opacity: 0.5;");
    defer style_parser.freeResult(allocator, result);
    try std.testing.expectEqual(@as(usize, 6), result.len);
    try std.testing.expectEqualStrings("width", result[0]);
    try std.testing.expectEqualStrings("333px", result[1]);
    try std.testing.expectEqualStrings("height", result[2]);
    try std.testing.expectEqualStrings("666px", result[3]);
    try std.testing.expectEqualStrings("opacity", result[4]);
    try std.testing.expectEqualStrings("0.5", result[5]);
}

test "style_parser: should not mess up with quoted strings that contain [:;] values" {
    const allocator = std.testing.allocator;
    const result = try style_parser.parse(allocator, "content: \"foo; man: guy\"; width: 100px");
    defer style_parser.freeResult(allocator, result);
    try std.testing.expectEqual(@as(usize, 4), result.len);
    try std.testing.expectEqualStrings("content", result[0]);
    try std.testing.expectEqualStrings("\"foo; man: guy\"", result[1]);
    try std.testing.expectEqualStrings("width", result[2]);
    try std.testing.expectEqualStrings("100px", result[3]);
}

test "style_parser: should not mess up with quoted strings that contain inner quote values" {
    const allocator = std.testing.allocator;
    const quote_str = "\"one 'two' three \"four\" five\"";
    const input = try std.fmt.allocPrint(allocator, "content: {s}; width: 123px", .{quote_str});
    defer allocator.free(input);
    const result = try style_parser.parse(allocator, input);
    defer style_parser.freeResult(allocator, result);
    try std.testing.expectEqual(@as(usize, 4), result.len);
    try std.testing.expectEqualStrings("content", result[0]);
    try std.testing.expectEqualStrings(quote_str, result[1]);
    try std.testing.expectEqualStrings("width", result[2]);
    try std.testing.expectEqualStrings("123px", result[3]);
}

test "style_parser: should respect parenthesis that are placed within a style" {
    const allocator = std.testing.allocator;
    const result = try style_parser.parse(allocator, "background-image: url(\"foo.jpg\")");
    defer style_parser.freeResult(allocator, result);
    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqualStrings("background-image", result[0]);
    try std.testing.expectEqualStrings("url(\"foo.jpg\")", result[1]);
}

test "style_parser: should respect multi-level parenthesis that contain special [:;] characters" {
    const allocator = std.testing.allocator;
    const result = try style_parser.parse(allocator, "color: rgba(calc(50 * 4), var(--cool), :5;); height: 100px;");
    defer style_parser.freeResult(allocator, result);
    try std.testing.expectEqual(@as(usize, 4), result.len);
    try std.testing.expectEqualStrings("color", result[0]);
    try std.testing.expectEqualStrings("rgba(calc(50 * 4), var(--cool), :5;)", result[1]);
    try std.testing.expectEqualStrings("height", result[2]);
    try std.testing.expectEqualStrings("100px", result[3]);
}

test "style_parser: should hyphenate style properties from camel case" {
    const allocator = std.testing.allocator;
    const result = try style_parser.parse(allocator, "borderWidth: 200px");
    defer style_parser.freeResult(allocator, result);
    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqualStrings("border-width", result[0]);
    try std.testing.expectEqualStrings("200px", result[1]);
}

test "style_parser: should not remove quotes from string data types" {
    const allocator = std.testing.allocator;
    const result = try style_parser.parse(allocator, "content: \"foo\"");
    defer style_parser.freeResult(allocator, result);
    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqualStrings("content", result[0]);
    try std.testing.expectEqualStrings("\"foo\"", result[1]);
}

test "style_parser: should not remove quotes that changes the value context from invalid to valid" {
    const allocator = std.testing.allocator;
    const result = try style_parser.parse(allocator, "width: \"1px\"");
    defer style_parser.freeResult(allocator, result);
    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqualStrings("width", result[0]);
    try std.testing.expectEqualStrings("\"1px\"", result[1]);
}

test "style_parser: should convert a camel-cased value to a hyphenated value" {
    const allocator = std.testing.allocator;
    const r1 = try style_parser.hyphenate(allocator, "fooBar");
    defer allocator.free(r1);
    try std.testing.expectEqualStrings("foo-bar", r1);

    const r2 = try style_parser.hyphenate(allocator, "fooBarMan");
    defer allocator.free(r2);
    try std.testing.expectEqualStrings("foo-bar-man", r2);

    const r3 = try style_parser.hyphenate(allocator, "-fooBar-man");
    defer allocator.free(r3);
    try std.testing.expectEqualStrings("-foo-bar-man", r3);
}

test "style_parser: should not hyphenate already hyphenated values" {
    const allocator = std.testing.allocator;
    const r1 = try style_parser.hyphenate(allocator, "border-width");
    defer allocator.free(r1);
    try std.testing.expectEqualStrings("border-width", r1);

    const r2 = try style_parser.hyphenate(allocator, "color");
    defer allocator.free(r2);
    try std.testing.expectEqualStrings("color", r2);
}
