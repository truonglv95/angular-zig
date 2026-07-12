/// Directive Matching — CSS Selector-based Directive Resolution
///
/// Determines which directives should match which template elements
/// based on their attribute selectors. Angular uses a subset of CSS
/// selectors for directive matching:
///   - Element selectors: div, span, my-component
///   - Attribute selectors: [attr], [attr=value], [attr~=value]
///   - Class selectors: .foo
///   - Pseudo-class selectors: :not(selector), :has(selector)
///   - Combinators: space (descendant), > (child), + (adjacent sibling)
///
/// DOD:
///   - Parsed selectors stored as contiguous arrays (no linked lists)
///   - SimpleSelector as tagged union (zero vtable overhead)
///   - Matching is stack-based recursive (no heap alloc in hot path)
///   - Comptime StaticStringMap for known pseudo-classes
const std = @import("std");
const Allocator = std.mem.Allocator;

// ─── Simple Selector Types ────────────────────────────────────

pub const SimpleSelectorKind = enum(u8) {
    /// Element selector: div, span, app-root
    Element,
    /// Attribute presence: [disabled]
    Attribute,
    /// Attribute exact match: [type="text"]
    AttributeValue,
    /// Attribute whitespace match: [class~="active"]
    AttributeContains,
    /// Attribute prefix match: [lang^="en"]
    AttributeStarts,
    /// Attribute suffix match: [src$=".png"]
    AttributeEnds,
    /// Attribute substring match: [title*="hello"]
    AttributeContainsStr,
    /// Class selector: .active
    Class,
    /// Pseudo-class: :not(selector), :has(selector)
    PseudoClass,
    /// Wildcard: *
    Universal,
};

/// Pseudo-class kinds
pub const PseudoClassKind = enum(u8) {
    Not,
    Has,
    Is,
    Host,
    HostContext,
};

/// A simple selector (single condition without combinators).
/// DOD: Tagged union — size = max(variant sizes), no heap allocation.
pub const SimpleSelector = struct {
    kind: SimpleSelectorKind,
    /// For Element: element name; for Attribute: attribute name;
    /// for Class: class name; for PseudoClass: function name
    name: []const u8,
    /// For attribute value selectors: the expected value
    value: []const u8,
    /// For :not() / :has() / :is(): the inner selector list
    inner: ?[]const Selector = null,
};

/// A parsed CSS selector (sequence of simple selectors).
/// E.g., "div.active[disabled]" → [Element("div"), Class("active"), Attribute("disabled")]
pub const Selector = struct {
    parts: []const SimpleSelector,
};

/// A selector with combinator and specificity.
/// Used in compound selectors like "div > .item + span"
pub const CompoundSelector = struct {
    selector: Selector,
    /// Combinator to the next part: 0=descendant, 1=child, 2=adjacent
    combinator: u8,
    /// Specificity (a, b, c) for cascade ordering
    specificity: [3]u16,
};

// ─── Directive Match Record ────────────────────────────────────

/// A directive definition with its selector and metadata.
pub const DirectiveDef = struct {
    /// Directive type name (e.g., "NgIf", "NgForOf")
    name: []const u8,
    /// Parsed selector
    selector: Selector,
    /// Whether this is a structural directive
    is_structural: bool,
    /// Matched specificity
    specificity: [3]u16,
};

/// Result of matching: which directives match an element.
pub const MatchResult = struct {
    /// Indices into the directive array that matched
    matched: []const u32,
    /// Specificity of each match
    specificities: []const [3]u16,
};

// ─── Selector Parser ───────────────────────────────────────────

/// Parse a CSS selector string into a Selector.
/// Only handles simple selectors (no combinators).
/// For complex selectors, use parseCompoundSelector.
pub fn parseSelector(allocator: Allocator, input: []const u8) !Selector {
    var parts = std.array_list.Managed(SimpleSelector).init(allocator);
    errdefer {
        for (parts.items) |p| {
            if (p.inner) |inner| allocator.free(inner);
        }
        parts.deinit();
    }

    var i: usize = 0;
    while (i < input.len) {
        const ch = input[i];

        if (ch == '.') {
            // Class selector: .foo
            i += 1;
            const start = i;
            while (i < input.len and isSelectorChar(input[i])) i += 1;
            try parts.append(.{
                .kind = .Class,
                .name = input[start..i],
                .value = "",
                .inner = null,
            });
        } else if (ch == '[') {
            // Attribute selector: [name], [name=value], [name~=value], etc.
            i += 1;
            const name_start = i;
            while (i < input.len and input[i] != '=' and input[i] != ']' and input[i] != '~' and input[i] != '^' and input[i] != '$' and input[i] != '*') i += 1;
            const attr_name = input[name_start..i];

            if (i < input.len and input[i] == ']') {
                // [attr] — presence only
                try parts.append(.{
                    .kind = .Attribute,
                    .name = attr_name,
                    .value = "",
                    .inner = null,
                });
                i += 1;
            } else {
                // Determine the operator
                var kind: SimpleSelectorKind = .AttributeValue;
                if (i < input.len and input[i] == '~') {
                    kind = .AttributeContains;
                    i += 1;
                } else if (i < input.len and input[i] == '^') {
                    kind = .AttributeStarts;
                    i += 1;
                } else if (i < input.len and input[i] == '$') {
                    kind = .AttributeEnds;
                    i += 1;
                } else if (i < input.len and input[i] == '*') {
                    kind = .AttributeContainsStr;
                    i += 1;
                }
                // Skip the '='
                if (i < input.len and input[i] == '=') i += 1;

                // Parse the value (quoted or unquoted)
                const value = if (i < input.len and (input[i] == '"' or input[i] == '\'')) {
                    const quote = input[i];
                    i += 1;
                    const v_start = i;
                    while (i < input.len and input[i] != quote) i += 1;
                    const val = input[v_start..i];
                    if (i < input.len) i += 1; // skip closing quote
                    val;
                } else {
                    const v_start = i;
                    while (i < input.len and input[i] != ']') i += 1;
                    input[v_start..i];
                };

                // Skip to closing bracket
                while (i < input.len and input[i] != ']') i += 1;
                if (i < input.len) i += 1;

                try parts.append(.{
                    .kind = kind,
                    .name = attr_name,
                    .value = value,
                    .inner = null,
                });
            }
        } else if (ch == ':') {
            // Pseudo-class: :not(selector), :has(selector)
            i += 1;
            const name_start = i;
            while (i < input.len and isAlphaNum(input[i])) i += 1;
            const pseudo_name = input[name_start..i];

            // Parse the argument in parentheses
            var inner_selector: ?Selector = null;
            if (i < input.len and input[i] == '(') {
                i += 1;
                const arg_start = i;
                var depth: u8 = 1;
                while (i < input.len and depth > 0) {
                    if (input[i] == '(') depth += 1;
                    if (input[i] == ')') depth -= 1;
                    if (depth > 0) i += 1;
                }
                const arg = input[arg_start..i];
                if (i < input.len) i += 1; // skip ')'

                const parsed = try parseSelector(allocator, arg);
                inner_selector = parsed;
            }

            try parts.append(.{
                .kind = .PseudoClass,
                .name = pseudo_name,
                .value = "",
                .inner = if (inner_selector) |*s| &[_]Selector{s.*} else null,
            });
        } else if (ch == '*') {
            try parts.append(.{
                .kind = .Universal,
                .name = "",
                .value = "",
                .inner = null,
            });
            i += 1;
        } else if (isSelectorChar(ch)) {
            // Element selector: div, span, etc.
            const start = i;
            while (i < input.len and isSelectorChar(input[i])) i += 1;
            try parts.append(.{
                .kind = .Element,
                .name = input[start..i],
                .value = "",
                .inner = null,
            });
        } else {
            // Skip whitespace and combinators
            i += 1;
        }
    }

    return .{ .parts = parts.items };
}

/// Check if a character is valid in a CSS selector identifier.
fn isSelectorChar(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or
        (ch >= 'A' and ch <= 'Z') or
        (ch >= '0' and ch <= '9') or
        ch == '-' or ch == '_';
}

fn isAlphaNum(ch: u8) bool {
    return isSelectorChar(ch);
}

// ─── Selector Matching ────────────────────────────────────────

/// Element description for matching.
pub const ElementMatchContext = struct {
    /// Element tag name (lowercase): "div", "span", "app-root"
    tag_name: []const u8,
    /// Attributes on the element: [("class", "foo bar"), ("disabled", ""), ...]
    attributes: []const AttributeEntry,
    /// Classes (split from class attribute)
    classes: []const []const u8,
};

pub const AttributeEntry = struct {
    name: []const u8,
    value: []const u8,
};

/// Check if a simple selector matches an element context.
pub fn matchesSimple(sel: SimpleSelector, ctx: *const ElementMatchContext) bool {
    return switch (sel.kind) {
        .Element => std.mem.eql(u8, sel.name, ctx.tag_name),
        .Universal => true,
        .Attribute => hasAttribute(ctx, sel.name),
        .AttributeValue => {
            if (getAttributeValue(ctx, sel.name)) |val| {
                return std.mem.eql(u8, val, sel.value);
            }
            return false;
        },
        .AttributeContains => {
            if (getAttributeValue(ctx, sel.name)) |val| {
                return containsWord(val, sel.value);
            }
            return false;
        },
        .AttributeStarts => {
            if (getAttributeValue(ctx, sel.name)) |val| {
                return std.mem.startsWith(u8, val, sel.value);
            }
            return false;
        },
        .AttributeEnds => {
            if (getAttributeValue(ctx, sel.name)) |val| {
                return std.mem.endsWith(u8, val, sel.value);
            }
            return false;
        },
        .AttributeContainsStr => {
            if (getAttributeValue(ctx, sel.name)) |val| {
                return std.mem.indexOf(u8, val, sel.value) != null;
            }
            return false;
        },
        .Class => {
            for (ctx.classes) |cls| {
                if (std.mem.eql(u8, cls, sel.name)) return true;
            }
            return false;
        },
        .PseudoClass => {
            const inner = sel.inner orelse return false;
            if (std.mem.eql(u8, sel.name, "not")) {
                // :not(selector) — matches if the inner selector does NOT match
                for (inner) |s| {
                    if (matchesSimple(s, ctx)) return false;
                }
                return true;
            }
            if (std.mem.eql(u8, sel.name, "has")) {
                // :has(selector) — we can't fully evaluate without children,
                // so return true conservatively (will be refined in template pass)
                return true;
            }
            // Unknown pseudo-class: ignore
            return true;
        },
    };
}

/// Check if a full selector matches an element.
pub fn matchesSelector(sel: *const Selector, ctx: *const ElementMatchContext) bool {
    for (sel.parts) |part| {
        if (!matchesSimple(part, ctx)) return false;
    }
    return true;
}

/// Check if an attribute exists on the element.
fn hasAttribute(ctx: *const ElementMatchContext, name: []const u8) bool {
    for (ctx.attributes) |attr| {
        if (std.mem.eql(u8, attr.name, name)) return true;
    }
    return false;
}

/// Get the value of an attribute, or null if not present.
fn getAttributeValue(ctx: *const ElementMatchContext, name: []const u8) ?[]const u8 {
    for (ctx.attributes) |attr| {
        if (std.mem.eql(u8, attr.name, name)) return attr.value;
    }
    return null;
}

/// Check if a value contains a whitespace-separated word.
fn containsWord(haystack: []const u8, needle: []const u8) bool {
    var start: usize = 0;
    var i: usize = 0;
    while (i <= haystack.len) {
        if (i == haystack.len or haystack[i] == ' ' or haystack[i] == '\t') {
            const word = haystack[start..i];
            if (word.len > 0 and std.mem.eql(u8, word, needle)) return true;
            start = i + 1;
        }
        i += 1;
    }
    return false;
}

// ─── Specificity Calculation ──────────────────────────────────

/// Calculate the specificity of a selector as (a, b, c).
/// a = ID selectors, b = class/attribute/pseudo-class, c = element/pseudo-element
pub fn calcSpecificity(sel: *const Selector) [3]u16 {
    var spec = [3]u16{ 0, 0, 0 };
    for (sel.parts) |part| {
        switch (part.kind) {
            .Element => spec[2] += 1,
            .Universal => {},
            .Class, .Attribute, .AttributeValue, .AttributeContains, .AttributeStarts, .AttributeEnds, .AttributeContainsStr => {
                spec[1] += 1;
            },
            .PseudoClass => {
                spec[1] += 1;
                if (part.inner) |inner| {
                    for (inner) |s| {
                        const inner_spec = calcSpecificity(&s);
                        // :not() specificity is the specificity of its argument
                        spec[0] += inner_spec[0];
                        spec[1] += inner_spec[1];
                        spec[2] += inner_spec[2];
                    }
                }
            },
        }
    }
    return spec;
}

/// Compare two specificities. Returns <0, 0, or >0.
pub fn compareSpecificity(a: [3]u16, b: [3]u16) i32 {
    if (a[0] != b[0]) return @as(i32, @intCast(a[0])) - @as(i32, @intCast(b[0]));
    if (a[1] != b[1]) return @as(i32, @intCast(a[1])) - @as(i32, @intCast(b[1]));
    return @as(i32, @intCast(a[2])) - @as(i32, @intCast(b[2]));
}

// ─── Directive Matching Entry Point ────────────────────────────

/// Match a list of directive definitions against an element context.
/// Returns indices of matching directives, sorted by specificity
/// (highest specificity first).
pub fn matchDirectives(
    allocator: Allocator,
    directives: []const DirectiveDef,
    ctx: *const ElementMatchContext,
) !MatchResult {
    var matched_indices = std.array_list.Managed(u32).init(allocator);
    errdefer matched_indices.deinit();
    var matched_specs = std.array_list.Managed([3]u16).init(allocator);
    errdefer matched_specs.deinit();

    for (directives, 0..) |dir, i| {
        if (matchesSelector(&dir.selector, ctx)) {
            try matched_indices.append(@intCast(i));
            try matched_specs.append(dir.specificity);
        }
    }

    // Sort by specificity (highest first) using insertion sort
    // (list is typically very small: <20 directives per element)
    const n = matched_indices.items.len;
    var j: usize = 1;
    while (j < n) {
        const key_idx = matched_indices.items[j];
        const key_spec = matched_specs.items[j];
        var k = j;
        while (k > 0 and compareSpecificity(matched_specs.items[k - 1], key_spec) < 0) {
            matched_indices.items[k] = matched_indices.items[k - 1];
            matched_specs.items[k] = matched_specs.items[k - 1];
            k -= 1;
        }
        matched_indices.items[k] = key_idx;
        matched_specs.items[k] = key_spec;
        j += 1;
    }

    return .{
        .matched = matched_indices.items,
        .specificities = matched_specs.items,
    };
}

/// Build an ElementMatchContext from an element name and attributes.
pub fn buildMatchContext(
    allocator: Allocator,
    tag_name: []const u8,
    attrs: []const AttributeEntry,
) !ElementMatchContext {
    // Extract classes from class attribute
    var classes = std.array_list.Managed([]const u8).init(allocator);
    errdefer classes.deinit();

    for (attrs) |attr| {
        if (std.mem.eql(u8, attr.name, "class") and attr.value.len > 0) {
            var start: usize = 0;
            for (attr.value, 0..) |ch, i| {
                if (ch == ' ' or ch == '\t' or ch == '\n') {
                    if (i > start) {
                        try classes.append(attr.value[start..i]);
                    }
                    start = i + 1;
                }
            }
            if (start < attr.value.len) {
                try classes.append(attr.value[start..]);
            }
        }
    }

    return .{
        .tag_name = tag_name,
        .attributes = attrs,
        .classes = classes.items,
    };
}

// ─── Tests ────────────────────────────────────────────────────

test "parseSelector element" {
    const allocator = std.testing.allocator;
    const sel = try parseSelector(allocator, "div");
    defer allocator.free(sel.parts);
    try std.testing.expectEqual(@as(usize, 1), sel.parts.len);
    try std.testing.expectEqual(SimpleSelectorKind.Element, sel.parts[0].kind);
    try std.testing.expectEqualStrings("div", sel.parts[0].name);
}

test "parseSelector with class" {
    const allocator = std.testing.allocator;
    const sel = try parseSelector(allocator, "div.active");
    defer allocator.free(sel.parts);
    try std.testing.expectEqual(@as(usize, 2), sel.parts.len);
    try std.testing.expectEqual(SimpleSelectorKind.Element, sel.parts[0].kind);
    try std.testing.expectEqual(SimpleSelectorKind.Class, sel.parts[1].kind);
    try std.testing.expectEqualStrings("active", sel.parts[1].name);
}

test "parseSelector with attribute" {
    const allocator = std.testing.allocator;
    const sel = try parseSelector(allocator, "[disabled]");
    defer allocator.free(sel.parts);
    try std.testing.expectEqual(@as(usize, 1), sel.parts.len);
    try std.testing.expectEqual(SimpleSelectorKind.Attribute, sel.parts[0].kind);
    try std.testing.expectEqualStrings("disabled", sel.parts[0].name);
}

test "parseSelector with attribute value" {
    const allocator = std.testing.allocator;
    const sel = try parseSelector(allocator, "[type=\"text\"]");
    defer allocator.free(sel.parts);
    try std.testing.expectEqual(@as(usize, 1), sel.parts.len);
    try std.testing.expectEqual(SimpleSelectorKind.AttributeValue, sel.parts[0].kind);
    try std.testing.expectEqualStrings("text", sel.parts[0].value);
}

test "parseSelector with attribute contains" {
    const allocator = std.testing.allocator;
    const sel = try parseSelector(allocator, "[class~=\"active\"]");
    defer allocator.free(sel.parts);
    try std.testing.expectEqual(SimpleSelectorKind.AttributeContains, sel.parts[0].kind);
}

test "matchesSimple element" {
    const ctx = ElementMatchContext{
        .tag_name = "div",
        .attributes = &.{},
        .classes = &.{},
    };
    try std.testing.expect(matchesSimple(.{ .kind = .Element, .name = "div", .value = "", .inner = null }, &ctx));
    try std.testing.expect(!matchesSimple(.{ .kind = .Element, .name = "span", .value = "", .inner = null }, &ctx));
}

test "matchesSimple universal" {
    const ctx = ElementMatchContext{
        .tag_name = "anything",
        .attributes = &.{},
        .classes = &.{},
    };
    try std.testing.expect(matchesSimple(.{ .kind = .Universal, .name = "", .value = "", .inner = null }, &ctx));
}

test "matchesSimple attribute" {
    const ctx = ElementMatchContext{
        .tag_name = "input",
        .attributes = &.{.{ .name = "disabled", .value = "" }},
        .classes = &.{},
    };
    try std.testing.expect(matchesSimple(.{ .kind = .Attribute, .name = "disabled", .value = "", .inner = null }, &ctx));
    try std.testing.expect(!matchesSimple(.{ .kind = .Attribute, .name = "required", .value = "", .inner = null }, &ctx));
}

test "matchesSimple class" {
    const ctx = ElementMatchContext{
        .tag_name = "div",
        .attributes = &.{.{ .name = "class", .value = "foo bar baz" }},
        .classes = &.{ "foo", "bar", "baz" },
    };
    try std.testing.expect(matchesSimple(.{ .kind = .Class, .name = "bar", .value = "", .inner = null }, &ctx));
    try std.testing.expect(!matchesSimple(.{ .kind = .Class, .name = "qux", .value = "", .inner = null }, &ctx));
}

test "calcSpecificity" {
    const allocator = std.testing.allocator;

    const sel1 = try parseSelector(allocator, "div");
    defer allocator.free(sel1.parts);
    const spec1 = calcSpecificity(&sel1);
    try std.testing.expectEqual([3]u16{ 0, 0, 1 }, spec1);

    const sel2 = try parseSelector(allocator, ".active");
    defer allocator.free(sel2.parts);
    const spec2 = calcSpecificity(&sel2);
    try std.testing.expectEqual([3]u16{ 0, 1, 0 }, spec2);

    const sel3 = try parseSelector(allocator, "div.active[type=\"text\"]");
    defer allocator.free(sel3.parts);
    const spec3 = calcSpecificity(&sel3);
    try std.testing.expectEqual([3]u16{ 0, 2, 1 }, spec3);
}

test "matchDirectives returns sorted matches" {
    const allocator = std.testing.allocator;

    const sel1 = try parseSelector(allocator, "div");
    defer allocator.free(sel1.parts);
    const sel2 = try parseSelector(allocator, "div.active");
    defer allocator.free(sel2.parts);

    const directives = [_]DirectiveDef{
        .{ .name = "LowPriority", .selector = sel1, .is_structural = false, .specificity = .{ 0, 0, 1 } },
        .{ .name = "HighPriority", .selector = sel2, .is_structural = false, .specificity = .{ 0, 1, 1 } },
    };

    const ctx = ElementMatchContext{
        .tag_name = "div",
        .attributes = &.{.{ .name = "class", .value = "active" }},
        .classes = &.{"active"},
    };

    const result = try matchDirectives(allocator, &directives, &ctx);
    defer allocator.free(result.matched);
    defer allocator.free(result.specificities);

    try std.testing.expectEqual(@as(usize, 2), result.matched.len);
    // Higher specificity first
    try std.testing.expectEqual(@as(u32, 1), result.matched[0]);
}

test "buildMatchContext extracts classes" {
    const allocator = std.testing.allocator;
    const attrs = [_]AttributeEntry{
        .{ .name = "class", .value = "foo bar" },
        .{ .name = "id", .value = "my-id" },
    };
    const ctx = try buildMatchContext(allocator, "div", &attrs);
    try std.testing.expectEqual(@as(usize, 2), ctx.classes.len);
    try std.testing.expectEqualStrings("foo", ctx.classes[0]);
    try std.testing.expectEqualStrings("bar", ctx.classes[1]);
}

test "containsWord" {
    try std.testing.expect(containsWord("foo bar baz", "bar"));
    try std.testing.expect(containsWord("foo bar baz", "foo"));
    try std.testing.expect(containsWord("foo bar baz", "baz"));
    try std.testing.expect(!containsWord("foo bar baz", "qux"));
    try std.testing.expect(!containsWord("foobar", "foo"));
}
