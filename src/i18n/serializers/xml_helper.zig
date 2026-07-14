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
pub fn escapeXml(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    try writeEscaped(&buf, text);
    return buf.toOwnedSlice();
}
