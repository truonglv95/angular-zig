/// i18n XMB Serializer (Google internal format)
///
/// Port of: compiler/src/i18n/serializers/xmb.ts
const std = @import("std");
const i18n_ast = @import("../i18n_ast.zig");
const xml_helper = @import("xml_helper.zig");

pub fn write(allocator: std.mem.Allocator, messages: []const i18n_ast.Message) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    try buf.appendSlice("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    try buf.appendSlice("<!DOCTYPE messagebundle [\n<!ELEMENT messagebundle (msg)*>\n<!ATTLIST messagebundle class CDATA #IMPLIED>\n<!ELEMENT msg (#PCDATA|ph|ex)*>\n<!ATTLIST msg id CDATA #IMPLIED>\n<!ELEMENT ph (#PCDATA)>\n<!ATTLIST ph name CDATA #REQUIRED>\n<!ELEMENT ex (#PCDATA)>\n<!ATTLIST ex name CDATA #REQUIRED>\n]>\n");
    try buf.appendSlice("<messagebundle>\n");
    for (messages) |msg| {
        try buf.appendSlice("  <msg id=\"");
        try buf.appendSlice(msg.id);
        try buf.appendSlice("\">");
        for (msg.nodes) |node| { try writeNode(&buf, &node); }
        try buf.appendSlice("</msg>\n");
    }
    try buf.appendSlice("</messagebundle>\n");
    return buf.toOwnedSlice();
}

fn writeNode(buf: *std.ArrayList(u8), node: *const i18n_ast.Node) !void {
    switch (node.data) {
        .text => |t| try xml_helper.writeEscaped(buf, t.value),
        .placeholder => |ph| { try buf.appendSlice("<ph name=\""); try buf.appendSlice(ph.name); try buf.appendSlice("\">"); try buf.appendSlice(ph.expression); try buf.appendSlice("</ph>"); },
        else => {},
    }
}
