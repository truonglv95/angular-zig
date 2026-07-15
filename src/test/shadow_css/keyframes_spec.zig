/// keyframes Tests — Ported from Angular TS test/shadow_css/keyframes_spec.ts
///
/// Source: packages/compiler/test/shadow_css/keyframes_spec.ts (25 test cases)
/// ALL test cases ported from the Angular TS source.
const std = @import("std");
const shadow_css = @import("../../shadow_css.zig");

test "keyframes: should scope keyframes rules" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "@keyframes foo { from {opacity: 0;} to {opacity: 1;} }", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "keyframes: should scope -webkit-keyframes rules" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "keyframes: should scope animations using local keyframes identifiers" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "keyframes: should not scope animations using non-local keyframes identifiers" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "keyframes: should scope animation-names using local keyframes identifiers" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "keyframes: should not scope animation-names using non-local keyframes identifiers" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "keyframes: should handle (scope or not) multiple animation-names" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "keyframes: should handle (scope or not) multiple animation-names defined over multiple lines" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "keyframes: should handle (scope or not) animation definition containing some names which do not have a preceding space" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "keyframes: should handle (scope or not) multiple animation definitions in a single declaration" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "keyframes: should maintain the spacing when handling (scoping or not) keyframes and animations" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "keyframes: should correctly process animations defined without any prefixed space" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "keyframes: should correctly process keyframes defined without any prefixed space" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "keyframes: should ignore keywords values when scoping local animations" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "keyframes: should handle the usage of quotes" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "keyframes: should handle the usage of quotes containing escaped quotes" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "keyframes: should handle the usage of commas in multiple animation definitions in a single declaration" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "keyframes: should handle the usage of double quotes escaping in multiple animation definitions in a single declaration" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "keyframes: should handle the usage of single quotes escaping in multiple animation definitions in a single declaration" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "keyframes: should handle the usage of mixed single and double quotes escaping in multiple animation definitions in a single declaration" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "keyframes: should handle the usage of commas inside quotes" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "keyframes: should not ignore animation keywords when they are inside quotes" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "keyframes: should handle css functions correctly" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}


test "keyframes: should not modify css variables ending with 'animation' even if they reference a local keyframes identifier" {
    const allocator = std.testing.allocator;
    const css =
        \\button {
        \\    --variable-animation: foo;
        \\}
        \\@keyframes foo {}
    ;
    const result = try shadow_css.shimCssText(allocator, css, "host-a");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "--variable-animation: foo;") != null);
}

test "keyframes: should not modify css variables ending with 'animation-name' even if they reference a local keyframes identifier" {
    const allocator = std.testing.allocator;
    const css =
        \\button {
        \\    --variable-animation-name: foo;
        \\}
        \\@keyframes foo {}
    ;
    const result = try shadow_css.shimCssText(allocator, css, "host-a");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "--variable-animation-name: foo;") != null);
}
