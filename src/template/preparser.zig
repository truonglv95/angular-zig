/// Template Preparser — Detects special elements
const std = @import("std");

pub const PreparsedElementType = enum {
    NG_CONTENT,
    STYLE,
    STYLESHEET,
    SCRIPT,
    OTHER,
};

pub const PreparsedElement = struct {
    type: PreparsedElementType,
    selector_attr: ?[]const u8 = null,
    href_attr: ?[]const u8 = null,
};

/// Preparse an element to detect ng-content, style, script, etc.
pub fn preparseElement(name: []const u8, attrs: []const PreparsedAttr) PreparsedElement {
    if (std.mem.eql(u8, name, "ng-content")) {
        return .{ .type = .NG_CONTENT, .selector_attr = findAttr(attrs, "select") };
    }
    if (std.mem.eql(u8, name, "style")) {
        return .{ .type = .STYLE };
    }
    if (std.mem.eql(u8, name, "link") and findAttr(attrs, "rel") != null and
        std.ascii.eqlIgnoreCase(findAttr(attrs, "rel").?, "stylesheet"))
    {
        return .{ .type = .STYLESHEET, .href_attr = findAttr(attrs, "href") };
    }
    if (std.mem.eql(u8, name, "script")) {
        return .{ .type = .SCRIPT };
    }
    return .{ .type = .OTHER };
}

pub const PreparsedAttr = struct {
    name: []const u8,
    value: ?[]const u8,
};

fn findAttr(attrs: []const PreparsedAttr, name: []const u8) ?[]const u8 {
    for (attrs) |a| {
        if (std.mem.eql(u8, a.name, name)) return a.value;
    }
    return null;
}

// ─── Transform (placeholder) ─────────────────────────────────
/// HTML AST → R3 AST transformation
/// This is a placeholder — full implementation requires
/// integration with BindingParser and expression parsing.
pub const Transform = struct {
    pub const TransformResult = struct {
        nodes: []*@import("../render3/r3_ast.zig").R3Node,
        style_urls: [][]const u8,
        styles: [][]const u8,
        ng_content_selectors: [][]const u8,
        errors: []const @import("../source_span.zig").ParseError,
    };
};

// ─── Tests ────────────────────────────────────────────────────

test "preparse ng-content" {
    const attrs = [_]PreparsedAttr{
        .{ .name = "select", .value = "[hero]" },
    };
    const result = preparseElement("ng-content", &attrs);
    try std.testing.expectEqual(PreparsedElementType.NG_CONTENT, result.type);
    try std.testing.expectEqualStrings("[hero]", result.selector_attr.?);
}

test "preparse stylesheet link" {
    const attrs = [_]PreparsedAttr{
        .{ .name = "rel", .value = "stylesheet" },
        .{ .name = "href", .value = "style.css" },
    };
    const result = preparseElement("link", &attrs);
    try std.testing.expectEqual(PreparsedElementType.STYLESHEET, result.type);
    try std.testing.expectEqualStrings("style.css", result.href_attr.?);
}
