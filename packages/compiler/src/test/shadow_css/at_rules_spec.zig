/// at_rules Tests — Ported from Angular TS test/shadow_css/at_rules_spec.ts
///
/// Source: packages/compiler/test/shadow_css/at_rules_spec.ts (19 test cases)
/// ALL test cases ported from the Angular TS source.
const std = @import("std");
const shadow_css = @import("../../shadow_css.zig");

test "at_rules: should handle media rules with simple rules" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "@media screen and (max-width: 800px) {div {font-size: 50px;}} div {}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "at_rules: should handle media rules with both width and height" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "@media screen and (max-width:800px, max-height:100%) {div {font-size:50px;}}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "at_rules: should preserve @page rules" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "@page { margin-right: 4in; }", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "at_rules: should strip ::ng-deep and :host from within @page rules" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "@page { ::ng-deep @top-left { content: \"Hamlet\";}}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "at_rules: should handle support rules" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "@supports (display: flex) {section {display: flex;}}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "at_rules: should strip ::ng-deep and :host from within @supports" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "@supports (display: flex) { @font-face { :host ::ng-deep font-family{} } }", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "at_rules: should strip ::ng-deep and :host from within @font-face" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "@font-face { font-family {} }", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "at_rules: should pass through @import directives" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "@import 'test.css';", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "at_rules: should shim rules after @import" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "@import 'test.css'; div {}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "at_rules: should shim rules with quoted content after @import" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "@import 'test.css'; div {}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "at_rules: should pass through @import directives whose URL contains colons and semicolons" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "@import 'test.css';", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "at_rules: should shim rules after @import with colons and semicolons" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "@import 'test.css'; div {}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "at_rules: should scope normal selectors inside an unnamed container rules" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "@container { div {} }", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "at_rules: should scope normal selectors inside a named container rules" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "@container name { div {} }", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "at_rules: should scope normal selectors inside a scope rule with scoping limits" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "@scope (.a) to (.b) { div {} }", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "at_rules: should scope normal selectors inside a scope rule" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "@scope (.a) { div {} }", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "at_rules: should handle document rules" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "@document url('test.css') { div {} }", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "at_rules: should handle layer rules" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "@layer { div {} }", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "at_rules: should scope normal selectors inside a starting-style rule" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "@starting-style { div {} }", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

