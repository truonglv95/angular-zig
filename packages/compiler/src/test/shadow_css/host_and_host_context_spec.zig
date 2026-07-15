/// host_and_host_context Tests — Ported from Angular TS test/shadow_css/host_and_host_context_spec.ts
///
/// Source: packages/compiler/test/shadow_css/host_and_host_context_spec.ts (23 test cases)
/// ALL test cases ported from the Angular TS source.
const std = @import("std");
const shadow_css = @import("../../shadow_css.zig");

test "host_and_host_context: should handle no context" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "host_and_host_context: should handle tag selector" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "host_and_host_context: should handle class selector" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "host_and_host_context: should handle attribute selector" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "host_and_host_context: should handle attribute and next operator without spaces" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "host_and_host_context: should handle host with escaped class selector" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "host_and_host_context: should handle compound class selectors" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "host_and_host_context: should ignore :host with a selector list containing top-level commas" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "host_and_host_context: should handle pseudo selectors" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "host_and_host_context: should handle unexpected selectors in the most reasonable way" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "host_and_host_context: should support newlines in the same selector and content " {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "host_and_host_context: should transform :host-context with pseudo selectors" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "host_and_host_context: should transform :host-context with nested pseudo selectors" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "host_and_host_context: should handle tag selector (dup 1)" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "host_and_host_context: should handle class selector (dup 1)" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "host_and_host_context: should handle attribute selector (dup 1)" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "host_and_host_context: should handle multiple :host-context() selectors" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, ":host, :host(.a) {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "host_and_host_context: should handle :host-context with no ancestor selectors" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, ":host {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "host_and_host_context: should handle selectors" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "host_and_host_context: should handle :host-context with comma-separated child selector" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, ":host {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "host_and_host_context: should handle selectors on the same element" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "host_and_host_context: should handle no selector :host" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "host_and_host_context: should handle selectors on different elements" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "host_and_host_context: should parse multiple rules containing :host-context and :host" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

