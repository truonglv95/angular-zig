/// HTML Tags — HTML tag definitions (content type, void-ness, etc.)
///
/// Port of: compiler/src/ml_parser/html_tags.ts (194 LoC)
///
/// Defines HTML tag definitions including:
///   - Content type (parsable, raw text, escapable raw text)
///   - Void elements (self-closing, no children)
///   - Implicit namespace prefixes (svg, math)
///   - Closed-by-children rules (e.g., <li> closes <li>)
///   - Ignore-first-LF rule (for <pre>, <textarea>)
///   - preventNamespaceInheritance (for <foreignObject>)
const std = @import("std");

/// TagContentType — the content model for HTML elements.
/// Direct port of `TagContentType` from tags.ts.
pub const TagContentType = enum(u8) {
    /// Parsable HTML content (default).
    ParsableData,
    /// Raw text content (script, style) — no entity decoding.
    RawText,
    /// Escapable raw text (textarea, title) — entity decoding but no tags.
    EscapableRawText,
};

/// HtmlTagDefinition — definition of an HTML tag's properties.
/// Direct port of `HtmlTagDefinition` class in the TS source.
pub const HtmlTagDefinition = struct {
    name: []const u8 = "",
    content_type: TagContentType = .ParsableData,
    is_void: bool = false,
    closed_by_parent: bool = false,
    implicit_namespace: ?[]const u8 = null,
    ignore_first_lf: bool = false,
    can_self_close: bool = false,
    prevent_namespace_inheritance: bool = false,
    /// Tags that close this element when encountered as children.
    closed_by_children: []const []const u8 = &.{},

    /// Check if this tag is closed by a child with the given name.
    /// Direct port of `isClosedByChild(name)` in the TS source.
    pub fn isClosedByChild(self: HtmlTagDefinition, child_name: []const u8) bool {
        if (self.is_void) return true;
        for (self.closed_by_children) |tag| {
            if (std.ascii.eqlIgnoreCase(tag, child_name)) return true;
        }
        return false;
    }

    /// Get the content type for this tag, optionally namespace-specific.
    pub fn getContentType(self: HtmlTagDefinition) TagContentType {
        return self.content_type;
    }
};

/// Void HTML elements (self-closing, no children).
/// Direct port of the void tag definitions in the TS source.
pub const VOID_TAGS = [_][]const u8{
    "base",  "meta",  "area", "embed", "link",   "img",
    "input", "param", "hr",   "br",    "source", "track",
    "wbr",   "col",
};

/// Tags with raw text content type.
pub const RAW_TEXT_TAGS = [_][]const u8{
    "style", "script",
};

/// Tags with escapable raw text content type.
pub const ESCAPABLE_RAW_TEXT_TAGS = [_][]const u8{
    "textarea", "title",
};

/// Tags that ignore the first line feed.
pub const IGNORE_FIRST_LF_TAGS = [_][]const u8{
    "pre", "listing", "textarea",
};

/// Check if a tag name is a void element.
pub fn isVoidTag(name: []const u8) bool {
    for (VOID_TAGS) |tag| {
        if (std.ascii.eqlIgnoreCase(tag, name)) return true;
    }
    return false;
}

/// Check if a tag name has raw text content.
pub fn isRawTextTag(name: []const u8) bool {
    for (RAW_TEXT_TAGS) |tag| {
        if (std.ascii.eqlIgnoreCase(tag, name)) return true;
    }
    return false;
}

/// Check if a tag name has escapable raw text content.
pub fn isEscapableRawTextTag(name: []const u8) bool {
    for (ESCAPABLE_RAW_TEXT_TAGS) |tag| {
        if (std.ascii.eqlIgnoreCase(tag, name)) return true;
    }
    return false;
}

/// Tags that close <p> when encountered as children.
const P_CLOSED_BY = [_][]const u8{
    "address",  "article", "aside", "blockquote", "div",    "dl",
    "fieldset", "footer",  "form",  "h1",         "h2",     "h3",
    "h4",       "h5",      "h6",    "header",     "hgroup", "hr",
    "main",     "nav",     "ol",    "p",          "pre",    "section",
    "table",    "ul",
};

/// Get the tag definition for an HTML tag name.
/// Direct port of `getHtmlTagDefinition(tagName)` in the TS source.
///
/// Performs case-insensitive lookup for HTML tags and case-sensitive for SVG.
pub fn getHtmlTagDefinition(name: []const u8) HtmlTagDefinition {
    // Void tags
    if (isVoidTag(name)) {
        return .{
            .name = name,
            .is_void = true,
            .closed_by_parent = true,
            .can_self_close = true,
        };
    }

    // Raw text tags
    if (isRawTextTag(name)) {
        return .{
            .name = name,
            .content_type = .RawText,
        };
    }

    // Escapable raw text tags
    if (isEscapableRawTextTag(name)) {
        var def = HtmlTagDefinition{
            .name = name,
            .content_type = .EscapableRawText,
        };
        // textarea ignores first LF
        if (std.ascii.eqlIgnoreCase(name, "textarea")) {
            def.ignore_first_lf = true;
        }
        return def;
    }

    // SVG namespace
    if (std.mem.eql(u8, name, "svg")) {
        return .{
            .name = name,
            .implicit_namespace = "svg",
        };
    }

    // foreignObject — SVG namespace but prevents inheritance
    if (std.mem.eql(u8, name, "foreignObject")) {
        return .{
            .name = name,
            .implicit_namespace = "svg",
            .prevent_namespace_inheritance = true,
        };
    }

    // MathML namespace
    if (std.mem.eql(u8, name, "math")) {
        return .{
            .name = name,
            .implicit_namespace = "math",
        };
    }

    // <p> tag — closed by many block-level elements
    if (std.ascii.eqlIgnoreCase(name, "p")) {
        return .{
            .name = name,
            .closed_by_children = &P_CLOSED_BY,
            .closed_by_parent = true,
            .can_self_close = true,
        };
    }

    // <li> — closed by another <li>
    if (std.ascii.eqlIgnoreCase(name, "li")) {
        const li_closed = [_][]const u8{"li"};
        return .{
            .name = name,
            .closed_by_children = &li_closed,
            .closed_by_parent = true,
        };
    }

    // <tr> — closed by another <tr>
    if (std.ascii.eqlIgnoreCase(name, "tr")) {
        const tr_closed = [_][]const u8{"tr"};
        return .{
            .name = name,
            .closed_by_children = &tr_closed,
            .closed_by_parent = true,
        };
    }

    // <td>, <th> — closed by td or th
    if (std.ascii.eqlIgnoreCase(name, "td") or std.ascii.eqlIgnoreCase(name, "th")) {
        const td_closed = [_][]const u8{ "td", "th" };
        return .{
            .name = name,
            .closed_by_children = &td_closed,
            .closed_by_parent = true,
        };
    }

    // <pre>, <listing> — ignore first LF
    if (std.ascii.eqlIgnoreCase(name, "pre") or std.ascii.eqlIgnoreCase(name, "listing")) {
        return .{
            .name = name,
            .ignore_first_lf = true,
            .can_self_close = true,
        };
    }

    // Default: parsable data, can self-close
    return .{
        .name = name,
        .can_self_close = true,
    };
}

// ─── Tests ──────────────────────────────────────────────────

test "isVoidTag" {
    try std.testing.expect(isVoidTag("br"));
    try std.testing.expect(isVoidTag("img"));
    try std.testing.expect(isVoidTag("input"));
    try std.testing.expect(isVoidTag("hr"));
    try std.testing.expect(isVoidTag("BR")); // case-insensitive
    try std.testing.expect(!isVoidTag("div"));
    try std.testing.expect(!isVoidTag("span"));
}

test "isRawTextTag" {
    try std.testing.expect(isRawTextTag("script"));
    try std.testing.expect(isRawTextTag("style"));
    try std.testing.expect(!isRawTextTag("div"));
}

test "isEscapableRawTextTag" {
    try std.testing.expect(isEscapableRawTextTag("textarea"));
    try std.testing.expect(isEscapableRawTextTag("title"));
    try std.testing.expect(!isEscapableRawTextTag("div"));
}

test "getHtmlTagDefinition void tags" {
    const br = getHtmlTagDefinition("br");
    try std.testing.expect(br.is_void);
    try std.testing.expect(br.closed_by_parent);

    const img = getHtmlTagDefinition("img");
    try std.testing.expect(img.is_void);
}

test "getHtmlTagDefinition raw text tags" {
    const script = getHtmlTagDefinition("script");
    try std.testing.expectEqual(TagContentType.RawText, script.content_type);

    const style = getHtmlTagDefinition("style");
    try std.testing.expectEqual(TagContentType.RawText, style.content_type);
}

test "getHtmlTagDefinition escapable raw text" {
    const textarea = getHtmlTagDefinition("textarea");
    try std.testing.expectEqual(TagContentType.EscapableRawText, textarea.content_type);
    try std.testing.expect(textarea.ignore_first_lf);
}

test "getHtmlTagDefinition SVG namespace" {
    const svg = getHtmlTagDefinition("svg");
    try std.testing.expectEqualStrings("svg", svg.implicit_namespace.?);

    const math = getHtmlTagDefinition("math");
    try std.testing.expectEqualStrings("math", math.implicit_namespace.?);
}

test "getHtmlTagDefinition foreignObject" {
    const fo = getHtmlTagDefinition("foreignObject");
    try std.testing.expectEqualStrings("svg", fo.implicit_namespace.?);
    try std.testing.expect(fo.prevent_namespace_inheritance);
}

test "getHtmlTagDefinition p tag" {
    const p = getHtmlTagDefinition("p");
    try std.testing.expect(p.closed_by_parent);
    try std.testing.expect(p.isClosedByChild("div"));
    try std.testing.expect(p.isClosedByChild("h1"));
    try std.testing.expect(p.isClosedByChild("P")); // case-insensitive
    try std.testing.expect(!p.isClosedByChild("span"));
}

test "getHtmlTagDefinition li tag" {
    const li = getHtmlTagDefinition("li");
    try std.testing.expect(li.isClosedByChild("li"));
    try std.testing.expect(li.closed_by_parent);
}

test "getHtmlTagDefinition td/th tags" {
    const td = getHtmlTagDefinition("td");
    try std.testing.expect(td.isClosedByChild("td"));
    try std.testing.expect(td.isClosedByChild("th"));

    const th = getHtmlTagDefinition("th");
    try std.testing.expect(th.isClosedByChild("td"));
    try std.testing.expect(th.isClosedByChild("th"));
}

test "getHtmlTagDefinition pre tag" {
    const pre = getHtmlTagDefinition("pre");
    try std.testing.expect(pre.ignore_first_lf);
}

test "getHtmlTagDefinition default" {
    const div = getHtmlTagDefinition("div");
    try std.testing.expectEqual(TagContentType.ParsableData, div.content_type);
    try std.testing.expect(!div.is_void);
    try std.testing.expect(div.can_self_close);
}

test "HtmlTagDefinition isClosedByChild for void" {
    const br = getHtmlTagDefinition("br");
    // Void tags are always closed by any child.
    try std.testing.expect(br.isClosedByChild("anything"));
}
