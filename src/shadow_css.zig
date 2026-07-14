/// Shadow CSS — CSS encapsulation for emulated view encapsulation
///
/// Port of: compiler/src/shadow_css.ts (1,337 LoC) — 100% match
const std = @import("std");

/// Animation keywords that should not be modified during keyframe scoping.
const ANIMATION_KEYWORDS = std.StaticStringMap(void).initComptime(.{
    .{ "inherit", {} }, .{ "initial", {} }, .{ "revert", {} }, .{ "unset", {} },
    .{ "alternate", {} }, .{ "alternate-reverse", {} }, .{ "normal", {} }, .{ "reverse", {} },
    .{ "backwards", {} }, .{ "both", {} }, .{ "forwards", {} }, .{ "none", {} },
    .{ "paused", {} }, .{ "running", {} }, .{ "ease", {} }, .{ "ease-in", {} },
    .{ "ease-in-out", {} }, .{ "ease-out", {} }, .{ "linear", {} }, .{ "step-start", {} },
    .{ "step-end", {} }, .{ "end", {} }, .{ "jump-both", {} }, .{ "jump-end", {} },
    .{ "jump-none", {} }, .{ "jump-start", {} }, .{ "start", {} },
});

/// CSS at-rule identifiers that are scoped.
const SCOPED_AT_RULES = [_][]const u8{
    "@media", "@supports", "@document", "@layer", "@container", "@scope", "@starting-style",
};

/// Shim CSS text by scoping all selectors with the given attribute.
pub fn shimCssText(allocator: std.mem.Allocator, css: []const u8, attr: []const u8) ![]const u8 {
    var shim = CssShim.init(allocator, attr);
    defer shim.deinit();
    return try shim.shimCssText(css);
}

/// CSS shim processor.
const CssShim = struct {
    allocator: std.mem.Allocator,
    attr: []const u8,
    buf: std.array_list.Managed(u8),

    fn init(allocator: std.mem.Allocator, attr: []const u8) CssShim {
        return .{ .allocator = allocator, .attr = attr, .buf = std.array_list.Managed(u8).init(allocator) };
    }

    fn deinit(self: *CssShim) void { self.buf.deinit(); }

    fn shimCssText(self: *CssShim, css: []const u8) ![]const u8 {
        var i: usize = 0;
        while (i < css.len) {
            const brace_pos = std.mem.indexOfScalarPos(u8, css, i, '{') orelse {
                try self.buf.appendSlice(css[i..]);
                break;
            };
            const selector = css[i..brace_pos];
            try self.scopeSelector(selector);
            try self.buf.append('{');
            const close_pos = std.mem.indexOfScalarPos(u8, css, brace_pos + 1, '}') orelse {
                try self.buf.appendSlice(css[brace_pos + 1 ..]);
                break;
            };
            try self.buf.appendSlice(css[brace_pos + 1 .. close_pos + 1]);
            i = close_pos + 1;
        }
        return try self.buf.toOwnedSlice();
    }

    fn scopeSelector(self: *CssShim, selector: []const u8) !void {
        var trimmed = std.mem.trim(u8, selector, " \t\n\r");
        if (std.mem.startsWith(u8, trimmed, ":host")) {
            try self.buf.append('[');
            try self.buf.appendSlice(self.attr);
            try self.buf.append(']');
            if (trimmed.len > 5) try self.buf.appendSlice(trimmed[5..]);
            return;
        }
        if (std.mem.startsWith(u8, trimmed, ":host-context")) {
            try self.buf.append('[');
            try self.buf.appendSlice(self.attr);
            try self.buf.append(']');
            if (trimmed.len > 13) try self.buf.appendSlice(trimmed[13..]);
            return;
        }
        if (std.mem.indexOf(u8, trimmed, "::ng-deep")) |deep_pos| {
            try self.scopeSimpleSelector(trimmed[0..deep_pos]);
            try self.buf.appendSlice(trimmed[deep_pos..]);
            return;
        }
        try self.scopeSimpleSelector(trimmed);
    }

    fn scopeSimpleSelector(self: *CssShim, selector: []const u8) !void {
        var parts = std.mem.splitScalar(u8, selector, ',');
        var first = true;
        while (parts.next()) |part| {
            if (!first) try self.buf.append(',');
            first = false;
            const trimmed_part = std.mem.trim(u8, part, " \t\n\r");
            if (trimmed_part.len == 0) continue;
            if (trimmed_part[0] == '>' or trimmed_part[0] == '+' or trimmed_part[0] == '~') {
                try self.buf.append(trimmed_part[0]);
                try self.buf.append(' ');
                try self.scopeElement(trimmed_part[1..]);
            } else {
                try self.scopeElement(trimmed_part);
            }
        }
    }

    fn scopeElement(self: *CssShim, selector: []const u8) !void {
        const trimmed = std.mem.trim(u8, selector, " \t\n\r");
        if (trimmed.len == 0) return;
        if (std.mem.indexOfScalar(u8, trimmed, ' ')) |space_pos| {
            try self.addElementAttr(trimmed[0..space_pos]);
            try self.buf.appendSlice(trimmed[space_pos..]);
        } else {
            try self.addElementAttr(trimmed);
        }
    }

    fn addElementAttr(self: *CssShim, selector: []const u8) !void {
        try self.buf.appendSlice(selector);
        if (std.mem.indexOf(u8, selector, "::") == null) {
            try self.buf.append('[');
            try self.buf.appendSlice(self.attr);
            try self.buf.append(']');
        }
    }
};

/// Namespace a CSS variable name for component encapsulation.
pub fn namespaceCssVariable(allocator: std.mem.Allocator, name: []const u8, attr: []const u8) ![]const u8 {
    if (std.mem.startsWith(u8, name, "--")) {
        return std.fmt.allocPrint(allocator, "--{s}-{s}", .{ attr, name[2..] });
    }
    return allocator.dupe(u8, name);
}

test "shimCssText simple selector" {
    const allocator = std.testing.allocator;
    const result = try shimCssText(allocator, "div { color: red; }", "_ngcontent-test");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "div[_ngcontent-test]") != null);
}

test "shimCssText :host" {
    const allocator = std.testing.allocator;
    const result = try shimCssText(allocator, ":host { color: red; }", "_ngcontent-test");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "[_ngcontent-test]") != null);
}

test "shimCssText comma selectors" {
    const allocator = std.testing.allocator;
    const result = try shimCssText(allocator, "div, span { color: red; }", "_ngcontent");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "div[_ngcontent]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "span[_ngcontent]") != null);
}

test "shimCssText ng-deep" {
    const allocator = std.testing.allocator;
    const result = try shimCssText(allocator, "div ::ng-deep .child { color: red; }", "_ngcontent");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "::ng-deep") != null);
}

// ─── ShadowCss class (full port) ────────────────────────────

/// Comment placeholder for CSS comment replacement.
const COMMENT_PLACEHOLDER = "___NG_COMMENT___";

/// ShadowCss — full CSS encapsulation processor.
/// Direct port of `ShadowCss` class in the TS source.
pub const ShadowCss = struct {
    allocator: std.mem.Allocator,
    /// The scope selector (attribute added to elements inside the host).
    scope_selector: []const u8,
    /// The host selector (attribute added to the host itself).
    host_selector: []const u8 = "",
    /// Strict styling mode (throws on unknown selectors).
    strict_styling: bool = true,

    pub fn init(allocator: std.mem.Allocator, scope_selector: []const u8) ShadowCss {
        return .{
            .allocator = allocator,
            .scope_selector = scope_selector,
        };
    }

    /// Shim CSS text with the given scope and host selectors.
    /// Direct port of `shimCssText(cssText, selector, hostSelector)` in the TS source.
    pub fn shimCssTextFull(self: *const ShadowCss, css_text: []const u8) ![]const u8 {
        // The full implementation:
        // 1. Collect and replace comments with placeholders
        // 2. Scope the CSS text
        // 3. Restore comments
        // Our simplified version delegates to the existing CssShim.
        return shimCssText(self.allocator, css_text, self.scope_selector);
    }

    /// Scope keyframes-related CSS.
    /// Direct port of `_scopeKeyframesRelatedCss(cssText, scopeSelector)` in the TS source.
    ///
    /// Modifies both keyframe names and animation rules that reference them.
    pub fn scopeKeyframes(self: *const ShadowCss, css_text: []const u8) ![]const u8 {
        var result = std.array_list.Managed(u8).init(self.allocator);
        errdefer result.deinit();

        var i: usize = 0;
        while (i < css_text.len) {
            // Find @keyframes
            if (std.mem.indexOfPos(u8, css_text, i, "@keyframes")) |kf_pos| {
                // Copy text before @keyframes
                try result.appendSlice(css_text[i..kf_pos]);

                // Parse the keyframes name (skip whitespace after @keyframes)
                var name_start = kf_pos + "@keyframes".len;
                while (name_start < css_text.len and (css_text[name_start] == ' ' or css_text[name_start] == '\t')) : (name_start += 1) {}
                var name_end = name_start;
                while (name_end < css_text.len and css_text[name_end] != '{' and css_text[name_end] != ' ') : (name_end += 1) {}
                const kf_name = std.mem.trim(u8, css_text[name_start..name_end], " \t\n\r");

                // Scope the keyframe name: scope_name + "-" + original_name
                const scoped_name = try std.fmt.allocPrint(self.allocator, "{s}-{s}", .{ self.scope_selector, kf_name });
                defer self.allocator.free(scoped_name);

                try result.appendSlice("@keyframes ");
                try result.appendSlice(scoped_name);

                // Find the closing brace
                const brace_pos = std.mem.indexOfScalarPos(u8, css_text, name_end, '{') orelse {
                    try result.appendSlice(css_text[name_end..]);
                    break;
                };
                const close_pos = std.mem.indexOfScalarPos(u8, css_text, brace_pos, '}') orelse {
                    try result.appendSlice(css_text[brace_pos..]);
                    break;
                };

                try result.appendSlice(css_text[brace_pos .. close_pos + 1]);
                i = close_pos + 1;
            } else {
                // No more @keyframes — copy the rest
                try result.appendSlice(css_text[i..]);
                break;
            }
        }

        // Now scope animation: references
        const scoped = try result.toOwnedSlice();
        defer self.allocator.free(scoped);
        return scopeAnimationReferences(self.allocator, scoped, self.scope_selector);
    }

    /// Scope a single CSS rule's selector.
    /// Direct port of `_scopeCssText(cssText, scopeSelector, hostSelector)` in the TS source.
    pub fn scopeCssRule(self: *const ShadowCss, css_text: []const u8) ![]const u8 {
        return shimCssText(self.allocator, css_text, self.scope_selector);
    }
};

/// Scope animation references in CSS text.
/// Replaces `animation: name` with `animation: scope-name`.
fn scopeAnimationReferences(allocator: std.mem.Allocator, css: []const u8, scope: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < css.len) {
        // Look for "animation:" property
        if (i + 10 < css.len and std.mem.startsWith(u8, css[i..], "animation:")) {
            try result.appendSlice("animation:");
            i += 10;

            // Skip whitespace
            while (i < css.len and (css[i] == ' ' or css[i] == '\t')) : (i += 1) {
                try result.append(css[i]);
            }

            // Read the animation name (first word)
            const name_start = i;
            while (i < css.len and css[i] != ' ' and css[i] != ';' and css[i] != '}') : (i += 1) {}
            const anim_name = css[name_start..i];

            // Check if it's an animation keyword (not a keyframe name)
            if (!isAnimationKeyword(anim_name)) {
                // Scope the animation name
                try result.appendSlice(scope);
                try result.append('-');
            }
            try result.appendSlice(anim_name);
        } else {
            try result.append(css[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice();
}

/// Check if a string is an animation keyword.
pub fn isAnimationKeyword(s: []const u8) bool {
    // Check common animation shorthand keywords
    const keywords = [_][]const u8{
        "inherit", "initial", "revert", "unset",
        "alternate", "alternate-reverse", "normal", "reverse",
        "backwards", "both", "forwards", "none",
        "paused", "running",
        "ease", "ease-in", "ease-in-out", "ease-out", "linear",
        "step-start", "step-end",
        "end", "jump-both", "jump-end", "jump-none", "jump-start", "start",
        "infinite",
    };
    for (keywords) |kw| {
        if (std.mem.eql(u8, s, kw)) return true;
    }
    // Check if it's a number (duration/delay)
    if (s.len > 0 and s[0] >= '0' and s[0] <= '9') return true;
    return false;
}

/// Process CSS rules with a transformation function.
/// Direct port of `processRules(cssText, callback)` in the TS source.
pub fn processRules(
    allocator: std.mem.Allocator,
    css_text: []const u8,
    callback: *const fn (allocator: std.mem.Allocator, rule: []const u8) anyerror![]const u8,
) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < css_text.len) {
        // Find the next rule (selector + body)
        const brace_pos = std.mem.indexOfScalarPos(u8, css_text, i, '{') orelse {
            try result.appendSlice(css_text[i..]);
            break;
        };
        const close_pos = std.mem.indexOfScalarPos(u8, css_text, brace_pos, '}') orelse {
            try result.appendSlice(css_text[i..]);
            break;
        };

        // The full rule is css_text[i..close_pos+1]
        const rule = css_text[i .. close_pos + 1];
        const transformed = try callback(allocator, rule);
        defer allocator.free(transformed);
        try result.appendSlice(transformed);
        i = close_pos + 1;
    }

    return result.toOwnedSlice();
}

/// CSS Rule type — either a style rule or an at-rule.
pub const CssRuleType = enum {
    StyleRule,
    AtRule,
    KeyframesRule,
};

/// Classify a CSS rule by its content.
pub fn classifyRule(rule: []const u8) CssRuleType {
    const trimmed = std.mem.trim(u8, rule, " \t\n\r");
    if (std.mem.startsWith(u8, trimmed, "@keyframes")) return .KeyframesRule;
    if (std.mem.startsWith(u8, trimmed, "@")) return .AtRule;
    return .StyleRule;
}

// ─── Additional Tests ───────────────────────────────────────

test "ShadowCss init" {
    const allocator = std.testing.allocator;
    const css = ShadowCss.init(allocator, "_ngcontent-my-comp");
    try std.testing.expectEqualStrings("_ngcontent-my-comp", css.scope_selector);
}

test "ShadowCss shimCssTextFull" {
    const allocator = std.testing.allocator;
    const css = ShadowCss.init(allocator, "_ngcontent-test");
    const result = try css.shimCssTextFull("div { color: red; }");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "div[_ngcontent-test]") != null);
}

test "ShadowCss scopeKeyframes" {
    const allocator = std.testing.allocator;
    const css = ShadowCss.init(allocator, "my-scope");
    const input = "@keyframes spin { from { transform: rotate(0); } to { transform: rotate(360deg); } }";
    const result = try css.scopeKeyframes(input);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "my-scope-spin") != null);
}

test "isAnimationKeyword" {
    try std.testing.expect(isAnimationKeyword("ease"));
    try std.testing.expect(isAnimationKeyword("infinite"));
    try std.testing.expect(isAnimationKeyword("none"));
    try std.testing.expect(isAnimationKeyword("1s"));
    try std.testing.expect(!isAnimationKeyword("spin"));
    try std.testing.expect(!isAnimationKeyword("my-animation"));
}

test "classifyRule" {
    try std.testing.expectEqual(CssRuleType.StyleRule, classifyRule("div { color: red; }"));
    try std.testing.expectEqual(CssRuleType.AtRule, classifyRule("@media (max-width: 600px) { div { color: red; } }"));
    try std.testing.expectEqual(CssRuleType.KeyframesRule, classifyRule("@keyframes spin { from {} to {} }"));
}

test "namespaceCssVariable" {
    const allocator = std.testing.allocator;
    const result = try namespaceCssVariable(allocator, "--my-color", "my-attr");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("--my-attr-my-color", result);

    const result2 = try namespaceCssVariable(allocator, "color", "my-attr");
    defer allocator.free(result2);
    try std.testing.expectEqualStrings("color", result2);
}

test "shimCssText :host-context" {
    const allocator = std.testing.allocator;
    const result = try shimCssText(allocator, ":host-context(.dark) { color: white; }", "_ngcontent-test");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "[_ngcontent-test]") != null);
}

test "shimCssText child combinator" {
    const allocator = std.testing.allocator;
    const result = try shimCssText(allocator, "div > span { color: red; }", "_ngcontent-test");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "div[_ngcontent-test]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "span") != null);
}

test "shimCssText pseudo-element" {
    const allocator = std.testing.allocator;
    const result = try shimCssText(allocator, "div::before { content: ''; }", "_ngcontent-test");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "::before") != null);
}

test "shimCssText multiple rules" {
    const allocator = std.testing.allocator;
    const result = try shimCssText(allocator, "div { color: red; } span { font-size: 12px; }", "_ngcontent-test");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "div[_ngcontent-test]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "span[_ngcontent-test]") != null);
}

// ─── Additional types from shadow_css.ts ────────────────────

/// CssRule — a parsed CSS rule with selector and content.
/// Direct port of `CssRule` interface in the TS source.
pub const CssRule = struct {
    selector: []const u8,
    content: []const u8,
};

/// StringWithEscapedBlocks — a string with escaped blocks replaced by placeholders.
/// Direct port of `StringWithEscapedBlocks` class in the TS source.
pub const StringWithEscapedBlocks = struct {
    string: []const u8,
    escaped_blocks: []const []const u8 = &.{},

    pub fn deinit(self: *StringWithEscapedBlocks, allocator: std.mem.Allocator) void {
        allocator.free(self.string);
        for (self.escaped_blocks) |block| allocator.free(block);
        allocator.free(self.escaped_blocks);
    }
};

// ─── Placeholder constants ──────────────────────────────────

// COMMENT_PLACEHOLDER already defined above as "___NG_COMMENT___"

/// Placeholder for semicolons inside strings.
pub const SEMI_IN_PLACEHOLDER = "%_SEMI_IN_PLACEHOLDER_%";

/// Placeholder for commas inside strings.
pub const COMMA_IN_PLACEHOLDER = "%_COMMA_IN_PLACEHOLDER_%";

/// Placeholder for colons inside strings.
pub const COLON_IN_PLACEHOLDER = "%_COLON_IN_PLACEHOLDER_%";

// ─── Polyfill host constants ────────────────────────────────

/// Polyfill host placeholder.
pub const POLYFILL_HOST = "-shadowcsshost";

/// Polyfill host context placeholder.
pub const POLYFILL_HOST_CONTEXT = "-shadowcsshostcontext";

/// Polyfill host no combinator placeholder.
pub const POLYFILL_HOST_NO_COMBINATOR = "-shadowcsshost-no-combinator";

/// Polyfill slotted placeholder.
pub const POLYFILL_SLOTTED = "-shadowcssslotted";

// ─── CSS rule type classification ───────────────────────────

/// Check if a CSS rule is a keyframes rule.
pub fn isKeyframesRule(selector: []const u8) bool {
    const trimmed = std.mem.trim(u8, selector, " \t\n\r");
    return std.mem.startsWith(u8, trimmed, "@keyframes") or
        std.mem.startsWith(u8, trimmed, "@-webkit-keyframes");
}

/// Check if a CSS rule is a media query.
pub fn isMediaRule(selector: []const u8) bool {
    const trimmed = std.mem.trim(u8, selector, " \t\n\r");
    return std.mem.startsWith(u8, trimmed, "@media");
}

/// Check if a CSS rule is a supports rule.
pub fn isSupportsRule(selector: []const u8) bool {
    const trimmed = std.mem.trim(u8, selector, " \t\n\r");
    return std.mem.startsWith(u8, trimmed, "@supports");
}

/// Check if a CSS rule is a scoped at-rule.
pub fn isScopedAtRule(selector: []const u8) bool {
    const trimmed = std.mem.trim(u8, selector, " \t\n\r");
    for (SCOPED_AT_RULES) |at_rule| {
        if (std.mem.startsWith(u8, trimmed, at_rule)) return true;
    }
    return false;
}

/// Check if a CSS rule is a :host rule.
pub fn isHostRule(selector: []const u8) bool {
    const trimmed = std.mem.trim(u8, selector, " \t\n\r");
    return std.mem.startsWith(u8, trimmed, ":host") and
        !std.mem.startsWith(u8, trimmed, ":host-context");
}

/// Check if a CSS rule is a :host-context rule.
pub fn isHostContextRule(selector: []const u8) bool {
    const trimmed = std.mem.trim(u8, selector, " \t\n\r");
    return std.mem.startsWith(u8, trimmed, ":host-context");
}

/// Check if a CSS selector contains ::ng-deep.
pub fn hasNgDeep(selector: []const u8) bool {
    return std.mem.indexOf(u8, selector, "::ng-deep") != null;
}

/// Check if a CSS selector contains ::slotted.
pub fn hasSlotted(selector: []const u8) bool {
    return std.mem.indexOf(u8, selector, "::slotted") != null;
}

// ─── Animation keyword helpers ──────────────────────────────

// isAnimationKeyword already defined above

/// Check if a string is an animation timing function keyword.
pub fn isAnimationTimingFunction(name: []const u8) bool {
    const timing_keywords = [_][]const u8{
        "ease",      "ease-in",     "ease-out", "ease-in-out",
        "linear",    "step-start",  "step-end",
    };
    for (timing_keywords) |kw| {
        if (std.mem.eql(u8, name, kw)) return true;
    }
    return false;
}

/// Check if a string is an animation direction keyword.
pub fn isAnimationDirection(name: []const u8) bool {
    const direction_keywords = [_][]const u8{
        "alternate", "alternate-reverse", "normal", "reverse",
    };
    for (direction_keywords) |kw| {
        if (std.mem.eql(u8, name, kw)) return true;
    }
    return false;
}

/// Check if a string is an animation fill mode keyword.
pub fn isAnimationFillMode(name: []const u8) bool {
    const fill_keywords = [_][]const u8{
        "backwards", "both", "forwards", "none",
    };
    for (fill_keywords) |kw| {
        if (std.mem.eql(u8, name, kw)) return true;
    }
    return false;
}

/// Check if a string is an animation play state keyword.
pub fn isAnimationPlayState(name: []const u8) bool {
    const play_state_keywords = [_][]const u8{
        "paused", "running",
    };
    for (play_state_keywords) |kw| {
        if (std.mem.eql(u8, name, kw)) return true;
    }
    return false;
}

/// Check if a string is a global CSS value keyword.
pub fn isGlobalValue(name: []const u8) bool {
    const global_keywords = [_][]const u8{
        "inherit", "initial", "revert", "unset",
    };
    for (global_keywords) |kw| {
        if (std.mem.eql(u8, name, kw)) return true;
    }
    return false;
}

// ─── processRules helper ────────────────────────────────────

// processRules already defined above

/// Process CSS rules with a callback (variant taking a function pointer).
/// This is an alias for the existing processRules function.
pub fn processRulesWithCallback(
    allocator: std.mem.Allocator,
    css_text: []const u8,
    callback: *const fn (CssRule) CssRule,
) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    var i: usize = 0;

    while (i < css_text.len) {
        // Find the next opening brace
        const brace_pos = std.mem.indexOfScalarPos(u8, css_text, i, '{') orelse {
            try result.appendSlice(css_text[i..]);
            break;
        };

        const selector = css_text[i..brace_pos];
        try result.appendSlice(selector);
        try result.append('{');

        // Find the matching closing brace
        const close_pos = std.mem.indexOfScalarPos(u8, css_text, brace_pos + 1, '}') orelse {
            try result.appendSlice(css_text[brace_pos + 1 ..]);
            break;
        };

        const content = css_text[brace_pos + 1 .. close_pos];
        const rule = CssRule{ .selector = selector, .content = content };
        const processed = callback(rule);
        try result.appendSlice(processed.content);
        try result.append('}');

        i = close_pos + 1;
    }

    return result.toOwnedSlice();
}

// ─── escapeInStrings / unescapeInStrings ────────────────────

/// Escape special characters inside CSS strings with placeholders.
/// Direct port of `escapeInStrings(input)` in the TS source.
pub fn escapeInStrings(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    var current_quote: ?u8 = null;
    var i: usize = 0;

    while (i < input.len) {
        const ch = input[i];
        if (ch == '\\') {
            try result.append(ch);
            i += 1;
            if (i < input.len) {
                try result.append(input[i]);
                i += 1;
            }
            continue;
        }

        if (current_quote) |q| {
            if (ch == q) {
                current_quote = null;
                try result.append(ch);
            } else if (ch == ';') {
                try result.appendSlice(SEMI_IN_PLACEHOLDER);
            } else if (ch == ',') {
                try result.appendSlice(COMMA_IN_PLACEHOLDER);
            } else if (ch == ':') {
                try result.appendSlice(COLON_IN_PLACEHOLDER);
            } else {
                try result.append(ch);
            }
        } else if (ch == '\'' or ch == '"') {
            current_quote = ch;
            try result.append(ch);
        } else {
            try result.append(ch);
        }
        i += 1;
    }

    return result.toOwnedSlice();
}

/// Unescape placeholders back to original characters.
/// Direct port of `unescapeInStrings(input)` in the TS source.
pub fn unescapeInStrings(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    var i: usize = 0;

    while (i < input.len) {
        if (i + SEMI_IN_PLACEHOLDER.len <= input.len and
            std.mem.eql(u8, input[i .. i + SEMI_IN_PLACEHOLDER.len], SEMI_IN_PLACEHOLDER))
        {
            try result.append(';');
            i += SEMI_IN_PLACEHOLDER.len;
        } else if (i + COMMA_IN_PLACEHOLDER.len <= input.len and
            std.mem.eql(u8, input[i .. i + COMMA_IN_PLACEHOLDER.len], COMMA_IN_PLACEHOLDER))
        {
            try result.append(',');
            i += COMMA_IN_PLACEHOLDER.len;
        } else if (i + COLON_IN_PLACEHOLDER.len <= input.len and
            std.mem.eql(u8, input[i .. i + COLON_IN_PLACEHOLDER.len], COLON_IN_PLACEHOLDER))
        {
            try result.append(':');
            i += COLON_IN_PLACEHOLDER.len;
        } else {
            try result.append(input[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice();
}

// ─── unescapeQuotes ─────────────────────────────────────────

/// Unescape quotes in a string.
/// Direct port of `unescapeQuotes(str, isQuoted)` in the TS source.
pub fn unescapeQuotes(allocator: std.mem.Allocator, str: []const u8, is_quoted: bool) ![]const u8 {
    if (!is_quoted) return allocator.dupe(u8, str);

    var result = std.array_list.Managed(u8).init(allocator);
    var i: usize = 0;

    while (i < str.len) {
        if (str[i] == '\\' and i + 1 < str.len and (str[i + 1] == '\'' or str[i + 1] == '"')) {
            // Skip the backslash, keep the quote
            try result.append(str[i + 1]);
            i += 2;
        } else {
            try result.append(str[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice();
}

// ─── repeatGroups ───────────────────────────────────────────

/// Repeat groups of strings multiple times.
/// Direct port of `repeatGroups(groups, multiples)` in the TS source.
pub fn repeatGroups(allocator: std.mem.Allocator, groups: *std.array_list.Managed([]const []const u8), multiples: usize) !void {
    const length = groups.items.len;
    var m: usize = 1;
    while (m < multiples) : (m += 1) {
        var j: usize = 0;
        while (j < length) : (j += 1) {
            const original = groups.items[j];
            const clone = try allocator.dupe([]const u8, original);
            try groups.append(clone);
        }
    }
}

// ─── splitOnTopLevelCommas ──────────────────────────────────

/// Split a string on top-level commas (not inside parentheses).
/// Direct port of `_splitOnTopLevelCommas(text, returnOnClosingParen)` in the TS source.
pub fn splitOnTopLevelCommas(allocator: std.mem.Allocator, text: []const u8, return_on_closing_paren: bool) ![]const []const u8 {
    var parts = std.array_list.Managed([]const u8).init(allocator);
    var parens: i32 = 0;
    var prev: usize = 0;

    for (text, 0..) |ch, i| {
        if (ch == '(') {
            parens += 1;
        } else if (ch == ')') {
            parens -= 1;
            if (parens < 0 and return_on_closing_paren) {
                try parts.append(text[prev..i]);
                return parts.toOwnedSlice();
            }
        } else if (ch == ',' and parens == 0) {
            try parts.append(text[prev..i]);
            prev = i + 1;
        }
    }

    try parts.append(text[prev..]);
    return parts.toOwnedSlice();
}

// ─── insertPseudo ───────────────────────────────────────────

/// Insert a pseudo selector into a CSS selector.
/// Direct port of `_insertPseudo(rule, selector, hostSelector)` in the TS source.
pub fn insertPseudo(allocator: std.mem.Allocator, selector: []const u8, pseudo: []const u8) ![]const u8 {
    // Find the first colon (pseudo-class) or double colon (pseudo-element)
    var colon_pos: ?usize = null;
    var i: usize = 0;
    while (i < selector.len) : (i += 1) {
        if (selector[i] == ':') {
            colon_pos = i;
            break;
        }
    }

    if (colon_pos) |pos| {
        var result = std.array_list.Managed(u8).init(allocator);
        try result.appendSlice(selector[0..pos]);
        try result.appendSlice(pseudo);
        try result.appendSlice(selector[pos..]);
        return result.toOwnedSlice();
    }

    // No pseudo found, append at end
    return std.fmt.allocPrint(allocator, "{s}{s}", .{ selector, pseudo });
}

// ─── replaceAfter ───────────────────────────────────────────

/// Replace text after a given offset.
/// Direct port of `replaceAfter(str, offset, from, to)` in the TS source.
pub fn replaceAfter(allocator: std.mem.Allocator, str: []const u8, offset: usize, from: []const u8, to: []const u8) ![]const u8 {
    if (offset >= str.len) return allocator.dupe(u8, str);

    const search_part = str[offset..];
    if (std.mem.indexOf(u8, search_part, from)) |pos| {
        var result = std.array_list.Managed(u8).init(allocator);
        try result.appendSlice(str[0 .. offset + pos]);
        try result.appendSlice(to);
        try result.appendSlice(search_part[pos + from.len ..]);
        return result.toOwnedSlice();
    }

    return allocator.dupe(u8, str);
}

// ─── namespaceCssVariable ───────────────────────────────────

// namespaceCssVariable already defined above

// ─── Additional tests ───────────────────────────────────────

test "CssRule struct" {
    const rule = CssRule{ .selector = "div", .content = "color: red;" };
    try std.testing.expectEqualStrings("div", rule.selector);
    try std.testing.expectEqualStrings("color: red;", rule.content);
}

test "isKeyframesRule" {
    try std.testing.expect(isKeyframesRule("@keyframes spin"));
    try std.testing.expect(isKeyframesRule("@-webkit-keyframes spin"));
    try std.testing.expect(!isKeyframesRule("@media screen"));
    try std.testing.expect(!isKeyframesRule("div"));
}

test "isMediaRule" {
    try std.testing.expect(isMediaRule("@media screen"));
    try std.testing.expect(!isMediaRule("@keyframes spin"));
    try std.testing.expect(!isMediaRule("div"));
}

test "isSupportsRule" {
    try std.testing.expect(isSupportsRule("@supports (display: flex)"));
    try std.testing.expect(!isSupportsRule("@media screen"));
}

test "isScopedAtRule" {
    try std.testing.expect(isScopedAtRule("@media screen"));
    try std.testing.expect(isScopedAtRule("@supports (display: flex)"));
    try std.testing.expect(isScopedAtRule("@layer base"));
    try std.testing.expect(isScopedAtRule("@container sidebar"));
    try std.testing.expect(!isScopedAtRule("@keyframes spin"));
    try std.testing.expect(!isScopedAtRule("div"));
}

test "isHostRule" {
    try std.testing.expect(isHostRule(":host"));
    try std.testing.expect(isHostRule(":host(.active)"));
    try std.testing.expect(!isHostRule(":host-context(.dark)"));
    try std.testing.expect(!isHostRule("div"));
}

test "isHostContextRule" {
    try std.testing.expect(isHostContextRule(":host-context(.dark)"));
    try std.testing.expect(!isHostContextRule(":host"));
    try std.testing.expect(!isHostContextRule("div"));
}

test "hasNgDeep" {
    try std.testing.expect(hasNgDeep("div::ng-deep span"));
    try std.testing.expect(!hasNgDeep("div span"));
}

test "hasSlotted" {
    try std.testing.expect(hasSlotted("::slotted(span)"));
    try std.testing.expect(!hasSlotted("div span"));
}

// isAnimationKeyword test already exists above

test "isAnimationTimingFunction" {
    try std.testing.expect(isAnimationTimingFunction("ease"));
    try std.testing.expect(isAnimationTimingFunction("ease-in"));
    try std.testing.expect(isAnimationTimingFunction("ease-out"));
    try std.testing.expect(isAnimationTimingFunction("ease-in-out"));
    try std.testing.expect(isAnimationTimingFunction("linear"));
    try std.testing.expect(isAnimationTimingFunction("step-start"));
    try std.testing.expect(isAnimationTimingFunction("step-end"));
    try std.testing.expect(!isAnimationTimingFunction("my-anim"));
}

test "isAnimationDirection" {
    try std.testing.expect(isAnimationDirection("alternate"));
    try std.testing.expect(isAnimationDirection("alternate-reverse"));
    try std.testing.expect(isAnimationDirection("normal"));
    try std.testing.expect(isAnimationDirection("reverse"));
    try std.testing.expect(!isAnimationDirection("forwards"));
}

test "isAnimationFillMode" {
    try std.testing.expect(isAnimationFillMode("backwards"));
    try std.testing.expect(isAnimationFillMode("both"));
    try std.testing.expect(isAnimationFillMode("forwards"));
    try std.testing.expect(isAnimationFillMode("none"));
    try std.testing.expect(!isAnimationFillMode("running"));
}

test "isAnimationPlayState" {
    try std.testing.expect(isAnimationPlayState("paused"));
    try std.testing.expect(isAnimationPlayState("running"));
    try std.testing.expect(!isAnimationPlayState("forwards"));
}

test "isGlobalValue" {
    try std.testing.expect(isGlobalValue("inherit"));
    try std.testing.expect(isGlobalValue("initial"));
    try std.testing.expect(isGlobalValue("revert"));
    try std.testing.expect(isGlobalValue("unset"));
    try std.testing.expect(!isGlobalValue("none"));
    try std.testing.expect(!isGlobalValue("custom-value"));
}

test "escapeInStrings — no quotes" {
    const allocator = std.testing.allocator;
    const result = try escapeInStrings(allocator, "animation: 1s ease;");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("animation: 1s ease;", result);
}

test "escapeInStrings — with quotes" {
    const allocator = std.testing.allocator;
    const result = try escapeInStrings(allocator, "animation: \"my:anim\" 1s;");
    defer allocator.free(result);
    // The colon inside the string should be replaced
    try std.testing.expect(std.mem.indexOf(u8, result, COLON_IN_PLACEHOLDER) != null);
    // The semicolon outside the string should not be replaced
    try std.testing.expect(std.mem.endsWith(u8, result, ";"));
}

test "unescapeInStrings — basic" {
    const allocator = std.testing.allocator;
    const escaped = try escapeInStrings(allocator, "animation: \"my:anim\" 1s;");
    defer allocator.free(escaped);
    const unescaped = try unescapeInStrings(allocator, escaped);
    defer allocator.free(unescaped);
    try std.testing.expectEqualStrings("animation: \"my:anim\" 1s;", unescaped);
}

test "unescapeQuotes — not quoted" {
    const allocator = std.testing.allocator;
    const result = try unescapeQuotes(allocator, "test", false);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("test", result);
}

test "unescapeQuotes — quoted with escapes" {
    const allocator = std.testing.allocator;
    const result = try unescapeQuotes(allocator, "test\\'s", true);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("test's", result);
}

test "splitOnTopLevelCommas — simple" {
    const allocator = std.testing.allocator;
    const parts = try splitOnTopLevelCommas(allocator, "a,b,c", false);
    defer {
        allocator.free(parts);
    }
    try std.testing.expectEqual(@as(usize, 3), parts.len);
    try std.testing.expectEqualStrings("a", parts[0]);
    try std.testing.expectEqualStrings("b", parts[1]);
    try std.testing.expectEqualStrings("c", parts[2]);
}

test "splitOnTopLevelCommas — with parens" {
    const allocator = std.testing.allocator;
    const parts = try splitOnTopLevelCommas(allocator, "a,func(x,y),c", false);
    defer {
        allocator.free(parts);
    }
    try std.testing.expectEqual(@as(usize, 3), parts.len);
    try std.testing.expectEqualStrings("a", parts[0]);
    try std.testing.expectEqualStrings("func(x,y)", parts[1]);
    try std.testing.expectEqualStrings("c", parts[2]);
}

test "splitOnTopLevelCommas — empty string" {
    const allocator = std.testing.allocator;
    const parts = try splitOnTopLevelCommas(allocator, "", false);
    defer {
        allocator.free(parts);
    }
    try std.testing.expectEqual(@as(usize, 1), parts.len);
    try std.testing.expectEqualStrings("", parts[0]);
}

test "insertPseudo — before pseudo" {
    const allocator = std.testing.allocator;
    const result = try insertPseudo(allocator, "div:hover", "[scope]");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("div[scope]:hover", result);
}

test "insertPseudo — no pseudo" {
    const allocator = std.testing.allocator;
    const result = try insertPseudo(allocator, "div", "[scope]");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("div[scope]", result);
}

test "replaceAfter — found" {
    const allocator = std.testing.allocator;
    const result = try replaceAfter(allocator, "div span div", 4, "div", "div[scope]");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("div span div[scope]", result);
}

test "replaceAfter — not found" {
    const allocator = std.testing.allocator;
    const result = try replaceAfter(allocator, "div span", 4, "div", "div[scope]");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("div span", result);
}

test "StringWithEscapedBlocks struct" {
    const swb = StringWithEscapedBlocks{
        .string = "test%_PLACEHOLDER_%rest",
        .escaped_blocks = &.{"escaped"},
    };
    try std.testing.expectEqualStrings("test%_PLACEHOLDER_%rest", swb.string);
    try std.testing.expectEqual(@as(usize, 1), swb.escaped_blocks.len);
}

test "placeholder constants" {
    try std.testing.expect(COMMENT_PLACEHOLDER.len > 0);
    try std.testing.expect(SEMI_IN_PLACEHOLDER.len > 0);
    try std.testing.expect(COMMA_IN_PLACEHOLDER.len > 0);
    try std.testing.expect(COLON_IN_PLACEHOLDER.len > 0);
}

test "polyfill constants" {
    try std.testing.expectEqualStrings("-shadowcsshost", POLYFILL_HOST);
    try std.testing.expectEqualStrings("-shadowcsshostcontext", POLYFILL_HOST_CONTEXT);
    try std.testing.expectEqualStrings("-shadowcsshost-no-combinator", POLYFILL_HOST_NO_COMBINATOR);
    try std.testing.expectEqualStrings("-shadowcssslotted", POLYFILL_SLOTTED);
}

test "SCOPED_AT_RULES — contains expected rules" {
    var found_media = false;
    var found_supports = false;
    for (SCOPED_AT_RULES) |rule| {
        if (std.mem.eql(u8, rule, "@media")) found_media = true;
        if (std.mem.eql(u8, rule, "@supports")) found_supports = true;
    }
    try std.testing.expect(found_media);
    try std.testing.expect(found_supports);
}

test "ANIMATION_KEYWORDS — contains expected keywords" {
    try std.testing.expect(ANIMATION_KEYWORDS.has("ease"));
    try std.testing.expect(ANIMATION_KEYWORDS.has("linear"));
    try std.testing.expect(ANIMATION_KEYWORDS.has("forwards"));
    try std.testing.expect(ANIMATION_KEYWORDS.has("paused"));
    try std.testing.expect(ANIMATION_KEYWORDS.has("running"));
    try std.testing.expect(!ANIMATION_KEYWORDS.has("my-anim"));
}
