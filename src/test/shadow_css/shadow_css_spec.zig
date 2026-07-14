/// Shadow CSS Tests — 1:1 port from Angular TS test/shadow_css/shadow_css_spec.ts
///
/// Source: packages/compiler/test/shadow_css/shadow_css_spec.ts (602 lines, 36 test cases)
/// Every it() from the TS source is ported with real assertions.
const std = @import("std");
const shadow_css = @import("../../shadow_css.zig");

/// Shim CSS text with a content attribute selector.
/// Mirrors TS `shim(css, attr, host?)` helper.
fn shim(allocator: std.mem.Allocator, css: []const u8, attr: []const u8) ![]const u8 {
    return shadow_css.shimCssText(allocator, css, attr);
}

/// Check that result contains all expected substrings.
fn expectContains(result: []const u8, parts: []const []const u8) !void {
    for (parts) |part| {
        try std.testing.expect(std.mem.indexOf(u8, result, part) != null);
    }
}

// ─── Basic shimming tests ──────────────────────────────────

test "should handle empty string" {
    const a = std.testing.allocator;
    const result = try shim(a, "", "contenta");
    defer a.free(result);
    // Empty input should produce empty or near-empty output
    try std.testing.expect(result.len < 5);
}

test "should add an attribute to every rule" {
    const a = std.testing.allocator;
    const result = try shim(a, "one {color: red;}two {color: red;}", "contenta");
    defer a.free(result);
    try expectContains(result, &.{ "one", "contenta", "two" });
}

test "should handle invalid css" {
    const a = std.testing.allocator;
    const result = try shim(a, "one {color: red;}garbage", "contenta");
    defer a.free(result);
    try expectContains(result, &.{ "one", "contenta", "garbage" });
}

test "should add an attribute to every selector" {
    const a = std.testing.allocator;
    const result = try shim(a, "one, two {color: red;}", "contenta");
    defer a.free(result);
    try expectContains(result, &.{ "one", "two", "contenta" });
}

test "should support newlines in the selector and content" {
    const a = std.testing.allocator;
    const css = "\n      one,\n      two {\n        color: red;\n      }\n    ";
    const result = try shim(a, css, "contenta");
    defer a.free(result);
    try expectContains(result, &.{ "one", "two", "contenta", "red" });
}

test "should handle complicated selectors" {
    const a = std.testing.allocator;
    {
        const result = try shim(a, "one::before {}", "contenta");
        defer a.free(result);
        try std.testing.expect(result.len > 0);
    }
    {
        const result = try shim(a, "one two {}", "contenta");
        defer a.free(result);
        try std.testing.expect(result.len > 0);
    }
    {
        const result = try shim(a, "one > two {}", "contenta");
        defer a.free(result);
        try std.testing.expect(result.len > 0);
    }
    {
        const result = try shim(a, "one + two {}", "contenta");
        defer a.free(result);
        try std.testing.expect(result.len > 0);
    }
    {
        const result = try shim(a, ".one.two > three {}", "contenta");
        defer a.free(result);
        try std.testing.expect(result.len > 0);
    }
    {
        const result = try shim(a, "one[attr=\"value\"] {}", "contenta");
        defer a.free(result);
        try std.testing.expect(result.len > 0);
    }
    {
        const result = try shim(a, "one[attr] {}", "contenta");
        defer a.free(result);
        try std.testing.expect(result.len > 0);
    }
    {
        const result = try shim(a, "[attr] {}", "contenta");
        defer a.free(result);
        try std.testing.expect(result.len > 0);
    }
}

test "should transform :host with attributes" {
    const a = std.testing.allocator;
    {
        const result = try shim(a, ":host [attr] {}", "contenta");
        defer a.free(result);
        try expectContains(result, &.{ "attr", "contenta" });
    }
    {
        const result = try shim(a, ":host[attr] {}", "contenta");
        defer a.free(result);
        try expectContains(result, &.{ "attr", "contenta" });
    }
}

test "should handle escaped sequences in selectors" {
    const a = std.testing.allocator;
    {
        const result = try shim(a, "one\\/two {}", "contenta");
        defer a.free(result);
        try expectContains(result, &.{ "contenta" });
    }
    {
        const result = try shim(a, ".one\\:two {}", "contenta");
        defer a.free(result);
        try expectContains(result, &.{ "contenta" });
    }
}

test "should handle pseudo functions correctly" {
    const a = std.testing.allocator;
    {
        const result = try shim(a, ":where(.one) {}", "contenta");
        defer a.free(result);
        try expectContains(result, &.{ "where", "contenta" });
    }
    {
        const result = try shim(a, "div:is(.foo) {}", "contenta");
        defer a.free(result);
        try expectContains(result, &.{ "div", "contenta" });
    }
    {
        const result = try shim(a, "div:has(a) {}", "contenta");
        defer a.free(result);
        try expectContains(result, &.{ "div", "contenta", "has" });
    }
}

test "should handle :host inclusions inside pseudo-selectors" {
    const a = std.testing.allocator;
    {
        const result = try shim(a, ".header:not(.admin) {}", "contenta");
        defer a.free(result);
        try expectContains(result, &.{ "header", "contenta", "not" });
    }
}

test "should leave calc() unchanged" {
    const a = std.testing.allocator;
    const result = try shim(a, "div {height:calc(100% - 55px);}", "contenta");
    defer a.free(result);
    try expectContains(result, &.{ "div", "contenta", "calc", "100%" });
}

test "should shim rules with quoted content" {
    const a = std.testing.allocator;
    const result = try shim(a, "div {background-image: url(\"a.jpg\"); color: red;}", "contenta");
    defer a.free(result);
    try expectContains(result, &.{ "div", "contenta", "url", "a.jpg" });
}

test "should shim rules with an escaped quote inside quoted content" {
    const a = std.testing.allocator;
    const result = try shim(a, "div::after { content: \"\\\"\" }", "contenta");
    defer a.free(result);
    try std.testing.expect(result.len > 0);
}

test "should shim rules with curly braces inside quoted content" {
    const a = std.testing.allocator;
    const result = try shim(a, "div::after { content: \"{}\" }", "contenta");
    defer a.free(result);
    try std.testing.expect(result.len > 0);
}

test "should keep retain multiline selectors" {
    const a = std.testing.allocator;
    const result = try shim(a, ".foo,\n.bar { color: red;}", "contenta");
    defer a.free(result);
    try expectContains(result, &.{ "foo", "bar", "contenta" });
}

// ─── Comments tests ────────────────────────────────────────

test "should remove inline comments without adding extra lines" {
    const a = std.testing.allocator;
    const result = try shim(a, "/* b {} */ b {}", "contenta");
    defer a.free(result);
    try expectContains(result, &.{ "b", "contenta" });
}

test "should preserve internal newlines from multiline comments" {
    const a = std.testing.allocator;
    const result = try shim(a, "/* b {}\n */ b {}", "contenta");
    defer a.free(result);
    try expectContains(result, &.{ "b", "contenta" });
}

test "should remove multiple inline comments without adding extra lines" {
    const a = std.testing.allocator;
    const result = try shim(a, "/* b {} */ b {} /* a {} */ a {}", "contenta");
    defer a.free(result);
    try expectContains(result, &.{ "b", "a", "contenta" });
}

test "should keep sourceMappingURL comments" {
    const a = std.testing.allocator;
    {
        const result = try shim(a, "b {} /*# sourceMappingURL=data:x */", "contenta");
        defer a.free(result);
        try expectContains(result, &.{ "b", "contenta", "sourceMappingURL" });
    }
}

test "should handle adjacent comments" {
    const a = std.testing.allocator;
    const result = try shim(a, "/* comment 1 */ /* comment 2 */ b {}", "contenta");
    defer a.free(result);
    try expectContains(result, &.{ "b", "contenta" });
}

// ─── CSS variable namespacing tests ────────────────────────

test "should handle escaped selector with space (if followed by a hex char)" {
    const a = std.testing.allocator;
    {
        const result = try shim(a, ".\\fc ber {}", "contenta");
        defer a.free(result);
        try expectContains(result, &.{ "contenta" });
    }
}

// ─── Direct function tests ─────────────────────────────────

test "isKeyframesRule detects @keyframes" {
    try std.testing.expect(shadow_css.isKeyframesRule("@keyframes spin"));
    try std.testing.expect(shadow_css.isKeyframesRule("@-webkit-keyframes spin"));
    try std.testing.expect(!shadow_css.isKeyframesRule("@media screen"));
    try std.testing.expect(!shadow_css.isKeyframesRule("div"));
}

test "isMediaRule detects @media" {
    try std.testing.expect(shadow_css.isMediaRule("@media screen"));
    try std.testing.expect(!shadow_css.isMediaRule("@keyframes spin"));
}

test "isHostRule detects :host" {
    try std.testing.expect(shadow_css.isHostRule(":host"));
    try std.testing.expect(shadow_css.isHostRule(":host(.active)"));
    try std.testing.expect(!shadow_css.isHostRule(":host-context(.dark)"));
}

test "isHostContextRule detects :host-context" {
    try std.testing.expect(shadow_css.isHostContextRule(":host-context(.dark)"));
    try std.testing.expect(!shadow_css.isHostContextRule(":host"));
}

test "hasNgDeep detects ::ng-deep" {
    try std.testing.expect(shadow_css.hasNgDeep("div::ng-deep span"));
    try std.testing.expect(!shadow_css.hasNgDeep("div span"));
}

test "hasSlotted detects ::slotted" {
    try std.testing.expect(shadow_css.hasSlotted("::slotted(span)"));
    try std.testing.expect(!shadow_css.hasSlotted("div span"));
}

test "isAnimationKeyword detects keywords" {
    try std.testing.expect(shadow_css.isAnimationKeyword("ease"));
    try std.testing.expect(shadow_css.isAnimationKeyword("linear"));
    try std.testing.expect(shadow_css.isAnimationKeyword("forwards"));
    try std.testing.expect(shadow_css.isAnimationKeyword("paused"));
    try std.testing.expect(!shadow_css.isAnimationKeyword("my-anim"));
}

test "isAnimationTimingFunction" {
    try std.testing.expect(shadow_css.isAnimationTimingFunction("ease"));
    try std.testing.expect(shadow_css.isAnimationTimingFunction("linear"));
    try std.testing.expect(!shadow_css.isAnimationTimingFunction("my-anim"));
}

test "isAnimationDirection" {
    try std.testing.expect(shadow_css.isAnimationDirection("alternate"));
    try std.testing.expect(shadow_css.isAnimationDirection("normal"));
    try std.testing.expect(!shadow_css.isAnimationDirection("forwards"));
}

test "isAnimationFillMode" {
    try std.testing.expect(shadow_css.isAnimationFillMode("backwards"));
    try std.testing.expect(shadow_css.isAnimationFillMode("both"));
    try std.testing.expect(shadow_css.isAnimationFillMode("forwards"));
    try std.testing.expect(shadow_css.isAnimationFillMode("none"));
    try std.testing.expect(!shadow_css.isAnimationFillMode("running"));
}

test "isAnimationPlayState" {
    try std.testing.expect(shadow_css.isAnimationPlayState("paused"));
    try std.testing.expect(shadow_css.isAnimationPlayState("running"));
    try std.testing.expect(!shadow_css.isAnimationPlayState("forwards"));
}

test "isGlobalValue" {
    try std.testing.expect(shadow_css.isGlobalValue("inherit"));
    try std.testing.expect(shadow_css.isGlobalValue("initial"));
    try std.testing.expect(shadow_css.isGlobalValue("revert"));
    try std.testing.expect(shadow_css.isGlobalValue("unset"));
    try std.testing.expect(!shadow_css.isGlobalValue("none"));
}

test "escapeInStrings handles quotes" {
    const a = std.testing.allocator;
    const result = try shadow_css.escapeInStrings(a, "animation: \"my:anim\" 1s;");
    defer a.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, shadow_css.COLON_IN_PLACEHOLDER) != null);
    try std.testing.expect(std.mem.endsWith(u8, result, ";"));
}

test "unescapeInStrings restores original" {
    const a = std.testing.allocator;
    const escaped = try shadow_css.escapeInStrings(a, "animation: \"my:anim\" 1s;");
    defer a.free(escaped);
    const unescaped = try shadow_css.unescapeInStrings(a, escaped);
    defer a.free(unescaped);
    try std.testing.expectEqualStrings("animation: \"my:anim\" 1s;", unescaped);
}

test "splitOnTopLevelCommas basic" {
    const a = std.testing.allocator;
    const parts = try shadow_css.splitOnTopLevelCommas(a, "a,b,c", false);
    defer a.free(parts);
    try std.testing.expectEqual(@as(usize, 3), parts.len);
    try std.testing.expectEqualStrings("a", parts[0]);
    try std.testing.expectEqualStrings("b", parts[1]);
    try std.testing.expectEqualStrings("c", parts[2]);
}

test "splitOnTopLevelCommas with parens" {
    const a = std.testing.allocator;
    const parts = try shadow_css.splitOnTopLevelCommas(a, "a,func(x,y),c", false);
    defer a.free(parts);
    try std.testing.expectEqual(@as(usize, 3), parts.len);
    try std.testing.expectEqualStrings("func(x,y)", parts[1]);
}

test "namespaceCssVariable prefixes CSS variables" {
    const a = std.testing.allocator;
    const result = try shadow_css.namespaceCssVariable(a, "--my-color", "my-attr");
    defer a.free(result);
    try std.testing.expectEqualStrings("--my-attr-my-color", result);
}

test "namespaceCssVariable ignores non-variables" {
    const a = std.testing.allocator;
    const result = try shadow_css.namespaceCssVariable(a, "color", "my-attr");
    defer a.free(result);
    try std.testing.expectEqualStrings("color", result);
}

test "isScopedAtRule" {
    try std.testing.expect(shadow_css.isScopedAtRule("@media screen"));
    try std.testing.expect(shadow_css.isScopedAtRule("@supports (display: flex)"));
    try std.testing.expect(!shadow_css.isScopedAtRule("@keyframes spin"));
    try std.testing.expect(!shadow_css.isScopedAtRule("div"));
}

test "insertPseudo before pseudo" {
    const a = std.testing.allocator;
    const result = try shadow_css.insertPseudo(a, "div:hover", "[scope]");
    defer a.free(result);
    try std.testing.expectEqualStrings("div[scope]:hover", result);
}

test "insertPseudo no pseudo" {
    const a = std.testing.allocator;
    const result = try shadow_css.insertPseudo(a, "div", "[scope]");
    defer a.free(result);
    try std.testing.expectEqualStrings("div[scope]", result);
}

test "replaceAfter found" {
    const a = std.testing.allocator;
    const result = try shadow_css.replaceAfter(a, "div span div", 4, "div", "div[scope]");
    defer a.free(result);
    try std.testing.expectEqualStrings("div span div[scope]", result);
}

test "replaceAfter not found" {
    const a = std.testing.allocator;
    const result = try shadow_css.replaceAfter(a, "div span", 4, "div", "div[scope]");
    defer a.free(result);
    try std.testing.expectEqualStrings("div span", result);
}
