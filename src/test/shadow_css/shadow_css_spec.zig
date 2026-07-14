/// Shadow CSS Tests — Ported from Angular TS test/shadow_css/ specs
///
/// Source: packages/compiler/test/shadow_css/*.ts (8 files, 1956 lines total)
const std = @import("std");
const shadow_css = @import("../../shadow_css.zig");

test "shadow_css: should scope simple selector" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div { color: red; }", "_ngcontent-test");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "div[_ngcontent-test]") != null);
}

test "shadow_css: should scope :host" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, ":host { color: red; }", "_ngcontent-test");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "[_ngcontent-test]") != null);
}

test "shadow_css: should scope :host-context" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, ":host-context(.dark) { color: white; }", "_ngcontent-test");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "[_ngcontent-test]") != null);
}

test "shadow_css: should scope comma selectors" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div, span { color: red; }", "_ngcontent-test");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "div[_ngcontent-test]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "span") != null);
}

test "shadow_css: should handle ng-deep" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div ::ng-deep span { color: red; }", "_ngcontent-test");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "div") != null);
}

test "shadow_css: should scope child combinator" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div > span { color: red; }", "_ngcontent-test");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "div[_ngcontent-test]") != null);
}

test "shadow_css: should scope pseudo-element" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div::before { content: ''; }", "_ngcontent-test");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "::before") != null);
}

test "shadow_css: should scope multiple rules" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.shimCssText(allocator, "div { color: red; } span { font-size: 12px; }", "_ngcontent-test");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "div[_ngcontent-test]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "span[_ngcontent-test]") != null);
}

test "shadow_css: isKeyframesRule detects @keyframes" {
    try std.testing.expect(shadow_css.isKeyframesRule("@keyframes spin"));
    try std.testing.expect(shadow_css.isKeyframesRule("@-webkit-keyframes spin"));
    try std.testing.expect(!shadow_css.isKeyframesRule("@media screen"));
    try std.testing.expect(!shadow_css.isKeyframesRule("div"));
}

test "shadow_css: isMediaRule detects @media" {
    try std.testing.expect(shadow_css.isMediaRule("@media screen"));
    try std.testing.expect(!shadow_css.isMediaRule("@keyframes spin"));
}

test "shadow_css: isHostRule detects :host" {
    try std.testing.expect(shadow_css.isHostRule(":host"));
    try std.testing.expect(shadow_css.isHostRule(":host(.active)"));
    try std.testing.expect(!shadow_css.isHostRule(":host-context(.dark)"));
}

test "shadow_css: isHostContextRule detects :host-context" {
    try std.testing.expect(shadow_css.isHostContextRule(":host-context(.dark)"));
    try std.testing.expect(!shadow_css.isHostContextRule(":host"));
}

test "shadow_css: hasNgDeep detects ::ng-deep" {
    try std.testing.expect(shadow_css.hasNgDeep("div::ng-deep span"));
    try std.testing.expect(!shadow_css.hasNgDeep("div span"));
}

test "shadow_css: escapeInStrings handles quotes" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.escapeInStrings(allocator, "animation: \"my:anim\" 1s;");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, shadow_css.COLON_IN_PLACEHOLDER) != null);
    try std.testing.expect(std.mem.endsWith(u8, result, ";"));
}

test "shadow_css: unescapeInStrings restores original" {
    const allocator = std.testing.allocator;
    const escaped = try shadow_css.escapeInStrings(allocator, "animation: \"my:anim\" 1s;");
    defer allocator.free(escaped);
    const unescaped = try shadow_css.unescapeInStrings(allocator, escaped);
    defer allocator.free(unescaped);
    try std.testing.expectEqualStrings("animation: \"my:anim\" 1s;", unescaped);
}

test "shadow_css: splitOnTopLevelCommas basic" {
    const allocator = std.testing.allocator;
    const parts = try shadow_css.splitOnTopLevelCommas(allocator, "a,b,c", false);
    defer allocator.free(parts);
    try std.testing.expectEqual(@as(usize, 3), parts.len);
    try std.testing.expectEqualStrings("a", parts[0]);
    try std.testing.expectEqualStrings("b", parts[1]);
    try std.testing.expectEqualStrings("c", parts[2]);
}

test "shadow_css: splitOnTopLevelCommas with parens" {
    const allocator = std.testing.allocator;
    const parts = try shadow_css.splitOnTopLevelCommas(allocator, "a,func(x,y),c", false);
    defer allocator.free(parts);
    try std.testing.expectEqual(@as(usize, 3), parts.len);
    try std.testing.expectEqualStrings("func(x,y)", parts[1]);
}

test "shadow_css: namespaceCssVariable prefixes CSS variables" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.namespaceCssVariable(allocator, "--my-color", "my-attr");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("--my-attr-my-color", result);
}

test "shadow_css: namespaceCssVariable ignores non-variables" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.namespaceCssVariable(allocator, "color", "my-attr");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("color", result);
}

test "shadow_css: isScopedAtRule" {
    try std.testing.expect(shadow_css.isScopedAtRule("@media screen"));
    try std.testing.expect(shadow_css.isScopedAtRule("@supports (display: flex)"));
    try std.testing.expect(!shadow_css.isScopedAtRule("@keyframes spin"));
    try std.testing.expect(!shadow_css.isScopedAtRule("div"));
}

test "shadow_css: hasSlotted" {
    try std.testing.expect(shadow_css.hasSlotted("::slotted(span)"));
    try std.testing.expect(!shadow_css.hasSlotted("div span"));
}

test "shadow_css: isAnimationTimingFunction" {
    try std.testing.expect(shadow_css.isAnimationTimingFunction("ease"));
    try std.testing.expect(shadow_css.isAnimationTimingFunction("linear"));
    try std.testing.expect(shadow_css.isAnimationTimingFunction("step-start"));
    try std.testing.expect(!shadow_css.isAnimationTimingFunction("my-anim"));
}

test "shadow_css: isAnimationDirection" {
    try std.testing.expect(shadow_css.isAnimationDirection("alternate"));
    try std.testing.expect(shadow_css.isAnimationDirection("normal"));
    try std.testing.expect(!shadow_css.isAnimationDirection("forwards"));
}

test "shadow_css: isAnimationFillMode" {
    try std.testing.expect(shadow_css.isAnimationFillMode("backwards"));
    try std.testing.expect(shadow_css.isAnimationFillMode("both"));
    try std.testing.expect(shadow_css.isAnimationFillMode("forwards"));
    try std.testing.expect(shadow_css.isAnimationFillMode("none"));
    try std.testing.expect(!shadow_css.isAnimationFillMode("running"));
}

test "shadow_css: isAnimationPlayState" {
    try std.testing.expect(shadow_css.isAnimationPlayState("paused"));
    try std.testing.expect(shadow_css.isAnimationPlayState("running"));
    try std.testing.expect(!shadow_css.isAnimationPlayState("forwards"));
}

test "shadow_css: isGlobalValue" {
    try std.testing.expect(shadow_css.isGlobalValue("inherit"));
    try std.testing.expect(shadow_css.isGlobalValue("initial"));
    try std.testing.expect(shadow_css.isGlobalValue("revert"));
    try std.testing.expect(shadow_css.isGlobalValue("unset"));
    try std.testing.expect(!shadow_css.isGlobalValue("none"));
}

test "shadow_css: insertPseudo before pseudo" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.insertPseudo(allocator, "div:hover", "[scope]");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("div[scope]:hover", result);
}

test "shadow_css: insertPseudo no pseudo" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.insertPseudo(allocator, "div", "[scope]");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("div[scope]", result);
}

test "shadow_css: replaceAfter found" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.replaceAfter(allocator, "div span div", 4, "div", "div[scope]");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("div span div[scope]", result);
}

test "shadow_css: replaceAfter not found" {
    const allocator = std.testing.allocator;
    const result = try shadow_css.replaceAfter(allocator, "div span", 4, "div", "div[scope]");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("div span", result);
}
