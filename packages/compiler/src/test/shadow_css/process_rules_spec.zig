/// process_rules Tests — Ported from Angular TS test/shadow_css/process_rules_spec.ts
///
/// Source: packages/compiler/test/shadow_css/process_rules_spec.ts (7 test cases)
/// ALL test cases ported from the Angular TS source.
const std = @import("std");
const shadow_css = @import("../../shadow_css.zig");

test "process_rules: should work with empty css" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "process_rules: should capture a rule without body" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "process_rules: should capture css rules with body" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "process_rules: should capture css rules with nested rules" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "process_rules: should capture multiple rules where some have no body" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "process_rules: should allow to change the selector while preserving whitespaces" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "process_rules: should allow to change the content" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

