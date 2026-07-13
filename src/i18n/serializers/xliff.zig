/// i18n XLIFF 1.2 Serializer
///
/// Port of: compiler/src/i18n/serializers/xliff.ts
///
/// Serializes i18n messages to the XLIFF 1.2 XML format.
/// This is the default format for Angular i18n translation files.
const std = @import("std");

const i18n_ast = @import("../i18n_ast.zig");
const xml_helper = @import("xml_helper.zig");
const placeholder = @import("placeholder.zig");

/// Serialize messages to XLIFF 1.2 format.
pub fn write(allocator: std.mem.Allocator, messages: []const i18n_ast.Message) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    // XML declaration
    try buf.appendSlice("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    // XLIFF root
    try buf.appendSlice("<xliff version=\"1.2\" xmlns=\"urn:oasis:names:tc:xliff:document:1.2\">\n");
    try buf.appendSlice("  <file source-language=\"en\" datatype=\"plaintext\" original=\"ng2.template\">\n");
    try buf.appendSlice("    <body>\n");

    // Write each message as a trans-unit
    for (messages) |msg| {
        try writeTransUnit(&buf, &msg);
    }

    try buf.appendSlice("    </body>\n");
    try buf.appendSlice("  </file>\n");
    try buf.appendSlice("</xliff>\n");

    return buf.toOwnedSlice();
}

fn writeTransUnit(buf: *std.ArrayList(u8), msg: *const i18n_ast.Message) !void {
    // <trans-unit id="msgId" datatype="html">
    try buf.appendSlice("      <trans-unit id=\"");
    try buf.appendSlice(msg.id);
    try buf.appendSlice("\" datatype=\"html\">\n");

    // <source>serialized message</source>
    try buf.appendSlice("        <source>");
    for (msg.nodes) |node| {
        try writeNode(buf, &node);
    }
    try buf.appendSlice("</source>\n");

    // Target placeholder (empty — to be filled by translator)
    try buf.appendSlice("        <target></target>\n");

    // Context group for meaning/description
    if (msg.meaning.len > 0) {
        try buf.appendSlice("        <context-group purpose=\"location\">\n");
        try buf.appendSlice("          <context context-type=\"meaning\">");
        try xml_helper.writeEscaped(buf, msg.meaning);
        try buf.appendSlice("</context>\n");
        try buf.appendSlice("        </context-group>\n");
    }

    if (msg.description.len > 0) {
        try buf.appendSlice("        <note priority=\"1\" from=\"description\">");
        try xml_helper.writeEscaped(buf, msg.description);
        try buf.appendSlice("</note>\n");
    }

    try buf.appendSlice("      </trans-unit>\n");
}

fn writeNode(buf: *std.ArrayList(u8), node: *const i18n_ast.Node) !void {
    switch (node.data) {
        .text => |t| try xml_helper.writeEscaped(buf, t.value),
        .container => |c| {
            for (c.children) |child| {
                try writeNode(buf, &child);
            }
        },
        .icu => |icu| {
            try buf.appendSlice("{");
            try buf.appendSlice(icu.expression);
            try buf.appendSlice("}");
        },
        .placeholder => |ph| {
            try buf.appendSlice("<x id=\"");
            try buf.appendSlice(ph.name);
            try buf.appendSlice("\"/>");
        },
        .tag_placeholder => |tp| {
            if (tp.is_start) {
                try buf.appendSlice("<x id=\"START_TAG_");
                try buf.appendSlice(tp.tag);
                try buf.appendSlice("\"/>");
            } else if (tp.is_close) {
                try buf.appendSlice("<x id=\"CLOSE_TAG_");
                try buf.appendSlice(tp.tag);
                try buf.appendSlice("\"/>");
            }
            for (tp.children) |child| {
                try writeNode(buf, &child);
            }
        },
    }
}
