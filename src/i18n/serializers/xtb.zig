/// i18n XTB Serializer (XMB translation bundle)
///
/// Port of: compiler/src/i18n/serializers/xtb.ts
const std = @import("std");
const i18n_ast = @import("../i18n_ast.zig");
const xml_helper = @import("xml_helper.zig");

pub fn write(allocator: std.mem.Allocator, messages: []const i18n_ast.Message) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    try buf.appendSlice("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    try buf.appendSlice("<!DOCTYPE translationbundle [\n<!ELEMENT translationbundle (translation)*>\n<!ATTLIST translationbundle lang CDATA #REQUIRED>\n<!ELEMENT translation (#PCDATA|ph)*>\n<!ATTLIST translation id CDATA #REQUIRED>\n<!ELEMENT ph (#PCDATA)>\n<!ATTLIST ph name CDATA #REQUIRED>\n]>\n");
    try buf.appendSlice("<translationbundle lang=\"en\">\n");
    for (messages) |msg| {
        try buf.appendSlice("  <translation id=\"");
        try buf.appendSlice(msg.id);
        try buf.appendSlice("\">");
        for (msg.nodes) |node| { try writeNode(&buf, &node); }
        try buf.appendSlice("</translation>\n");
    }
    try buf.appendSlice("</translationbundle>\n");
    return buf.toOwnedSlice();
}

fn writeNode(buf: *std.ArrayList(u8), node: *const i18n_ast.Node) !void {
    switch (node.data) {
        .text => |t| try xml_helper.writeEscaped(buf, t.value),
        .placeholder => |ph| { try buf.appendSlice("<ph name=\""); try buf.appendSlice(ph.name); try buf.appendSlice("\">"); try buf.appendSlice(ph.expression); try buf.appendSlice("</ph>"); },
        else => {},
    }
}
