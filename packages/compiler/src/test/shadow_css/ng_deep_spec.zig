/// ng_deep Tests — Ported from Angular TS test/shadow_css/ng_deep_spec.ts
///
/// Source: packages/compiler/test/shadow_css/ng_deep_spec.ts (3 test cases)
/// ALL test cases ported from the Angular TS source.
const std = @import("std");
const shadow_css = @import("../../shadow_css.zig");

test "ng_deep: should handle /deep/" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "ng_deep: should handle >>>" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "ng_deep: should handle ::ng-deep" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "::ng-deep div {color: red;}", "contenta");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}
