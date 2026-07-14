/// i18n XML Helper — Tiny XML writer for serializers
///
/// Port of: compiler/src/i18n/serializers/xml_helper.ts
const std = @import("std");

/// XML node types.
pub const XmlKind = enum { tag, text, declaration, doctype };

/// An XML node.
pub const XmlNode = struct {
    kind: XmlKind,
    name: []const u8,
    attrs: []const XmlAttr,
    children: []const XmlNode,
    text: []const u8 = "",
};

pub const XmlAttr = struct {
    name: []const u8,
    value: []const u8,
};

/// Write an XML node tree to a string.
pub fn serialize(allocator: std.mem.Allocator, node: *const XmlNode) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    try writeNode(&buf, node);
    return buf.toOwnedSlice();
}

fn writeNode(buf: *std.array_list.Managed(u8), node: *const XmlNode) !void {
    switch (node.kind) {
        .declaration => {
            try buf.appendSlice("<?xml");
            try writeAttrs(buf, node.attrs);
            try buf.appendSlice("?>\n");
        },
        .doctype => {
            try buf.appendSlice("<!DOCTYPE ");
            try buf.appendSlice(node.name);
            try buf.appendSlice(">\n");
        },
        .tag => {
            try buf.append('<');
            try buf.appendSlice(node.name);
            try writeAttrs(buf, node.attrs);
            if (node.children.len == 0) {
                try buf.appendSlice("/>\n");
            } else {
                try buf.appendSlice(">\n");
                for (node.children) |*child| {
                    try writeNode(buf, child);
                }
                try buf.appendSlice("</");
                try buf.appendSlice(node.name);
                try buf.appendSlice(">\n");
            }
        },
        .text => {
            try writeEscaped(buf, node.text);
        },
    }
}

fn writeAttrs(buf: *std.array_list.Managed(u8), attrs: []const XmlAttr) !void {
    for (attrs) |attr| {
        try buf.append(' ');
        try buf.appendSlice(attr.name);
        try buf.appendSlice("=\"");
        try writeEscaped(buf, attr.value);
        try buf.append('"');
    }
}

pub fn writeEscaped(buf: *std.array_list.Managed(u8), text: []const u8) !void {
    for (text) |ch| {
        switch (ch) {
            '<' => try buf.appendSlice("&lt;"),
            '>' => try buf.appendSlice("&gt;"),
            '&' => try buf.appendSlice("&amp;"),
            '"' => try buf.appendSlice("&quot;"),
            '\'' => try buf.appendSlice("&apos;"),
            else => try buf.append(ch),
        }
    }
}

/// Escape XML text content.
/// Direct port of `escapeXml(text)` in the TS source.
pub fn escapeXml(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    try writeEscaped(&buf, text);
    return buf.toOwnedSlice();
}

// ─── Convenience constructors (direct port of TS classes) ───

/// Create a Declaration node.
/// Direct port of `Declaration` class in the TS source.
pub fn createDeclaration(allocator: std.mem.Allocator, unescaped_attrs: []const XmlAttr) !XmlNode {
    var attrs = try allocator.alloc(XmlAttr, unescaped_attrs.len);
    for (unescaped_attrs, 0..) |attr, i| {
        attrs[i] = .{
            .name = attr.name,
            .value = try escapeXml(allocator, attr.value),
        };
    }
    return .{
        .kind = .declaration,
        .name = "",
        .attrs = attrs,
        .children = &.{},
    };
}

/// Create a Doctype node.
/// Direct port of `Doctype` class in the TS source.
pub fn createDoctype(root_tag: []const u8) XmlNode {
    return .{
        .kind = .doctype,
        .name = root_tag,
        .attrs = &.{},
        .children = &.{},
    };
}

/// Create a Tag node.
/// Direct port of `Tag` class in the TS source.
pub fn createTag(allocator: std.mem.Allocator, name: []const u8, unescaped_attrs: []const XmlAttr, children: []const XmlNode) !XmlNode {
    var attrs = try allocator.alloc(XmlAttr, unescaped_attrs.len);
    for (unescaped_attrs, 0..) |attr, i| {
        attrs[i] = .{
            .name = attr.name,
            .value = try escapeXml(allocator, attr.value),
        };
    }
    return .{
        .kind = .tag,
        .name = name,
        .attrs = attrs,
        .children = children,
    };
}

/// Create a Text node.
/// Direct port of `Text` class in the TS source.
pub fn createText(allocator: std.mem.Allocator, unescaped_value: []const u8) !XmlNode {
    return .{
        .kind = .text,
        .name = "",
        .attrs = &.{},
        .children = &.{},
        .text = try escapeXml(allocator, unescaped_value),
    };
}

/// Create a CR (carriage return) node.
/// Direct port of `CR extends Text` class in the TS source.
/// Produces `\n` followed by `ws` spaces for indentation.
pub fn createCR(allocator: std.mem.Allocator, ws: usize) !XmlNode {
    var buf = std.array_list.Managed(u8).init(allocator);
    try buf.append('\n');
    var i: usize = 0;
    while (i < ws) : (i += 1) {
        try buf.append(' ');
    }
    return .{
        .kind = .text,
        .name = "",
        .attrs = &.{},
        .children = &.{},
        .text = try buf.toOwnedSlice(),
    };
}

// ─── Tests ──────────────────────────────────────────────────

test "escapeXml — basic" {
    const allocator = std.testing.allocator;
    const result = try escapeXml(allocator, "Hello <world> & \"friends\"");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello &lt;world&gt; &amp; &quot;friends&quot;", result);
}

test "escapeXml — no special chars" {
    const allocator = std.testing.allocator;
    const result = try escapeXml(allocator, "Hello World");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello World", result);
}

test "escapeXml — apostrophe" {
    const allocator = std.testing.allocator;
    const result = try escapeXml(allocator, "it's");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("it&apos;s", result);
}

test "serialize — declaration" {
    const allocator = std.testing.allocator;
    var attrs = [_]XmlAttr{
        .{ .name = "version", .value = "1.0" },
        .{ .name = "encoding", .value = "UTF-8" },
    };
    const node = XmlNode{
        .kind = .declaration,
        .name = "",
        .attrs = &attrs,
        .children = &.{},
    };
    const result = try serialize(allocator, &node);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "<?xml") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "version=\"1.0\"") != null);
}

test "serialize — tag with children" {
    const allocator = std.testing.allocator;
    var children = [_]XmlNode{
        .{ .kind = .text, .name = "", .attrs = &.{}, .children = &.{}, .text = "Hello" },
    };
    const node = XmlNode{
        .kind = .tag,
        .name = "div",
        .attrs = &.{},
        .children = &children,
    };
    const result = try serialize(allocator, &node);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "<div>") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "</div>") != null);
}

test "serialize — self-closing tag" {
    const allocator = std.testing.allocator;
    const node = XmlNode{
        .kind = .tag,
        .name = "br",
        .attrs = &.{},
        .children = &.{},
    };
    const result = try serialize(allocator, &node);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "<br/>") != null);
}

test "createText escapes XML" {
    const allocator = std.testing.allocator;
    const node = try createText(allocator, "Hello <world>");
    defer allocator.free(node.text);
    try std.testing.expectEqualStrings("Hello &lt;world&gt;", node.text);
}

test "createCR with indentation" {
    const allocator = std.testing.allocator;
    const node = try createCR(allocator, 4);
    defer allocator.free(node.text);
    try std.testing.expectEqualStrings("\n    ", node.text);
}

test "createCR with zero indentation" {
    const allocator = std.testing.allocator;
    const node = try createCR(allocator, 0);
    defer allocator.free(node.text);
    try std.testing.expectEqualStrings("\n", node.text);
}

test "createDoctype" {
    const node = createDoctype("translationbundle");
    try std.testing.expectEqual(XmlKind.doctype, node.kind);
    try std.testing.expectEqualStrings("translationbundle", node.name);
}
