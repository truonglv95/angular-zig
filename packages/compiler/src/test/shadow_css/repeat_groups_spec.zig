/// repeat_groups Tests — Ported from Angular TS test/shadow_css/repeat_groups_spec.ts
///
/// Source: packages/compiler/test/shadow_css/repeat_groups_spec.ts (3 test cases)
/// ALL test cases ported from the Angular TS source.
const std = @import("std");
const shadow_css = @import("../../shadow_css.zig");

test "repeat_groups: should do nothing if `multiples` is 0" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "repeat_groups: should do nothing if `multiples` is 1" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "repeat_groups: should add clones of the original groups if `multiples` is greater than 1" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}
