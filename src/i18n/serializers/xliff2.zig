/// i18n XLIFF 2.0 Serializer
///
/// Port of: compiler/src/i18n/serializers/xliff2.ts
const std = @import("std");
const i18n_ast = @import("../i18n_ast.zig");
const xml_helper = @import("xml_helper.zig");

pub fn write(allocator: std.mem.Allocator, messages: []const i18n_ast.Message) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    try buf.appendSlice("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    try buf.appendSlice("<xliff version=\"2.0\" xmlns=\"urn:oasis:names:tc:xliff:document:2.0\" srcLang=\"en\">\n");
    try buf.appendSlice("  <file original=\"ng2.template\" id=\"ngi18n\">\n");
    for (messages) |msg| {
        try buf.appendSlice("    <unit id=\"");
        try buf.appendSlice(msg.id);
        try buf.appendSlice("\">\n      <segment>\n        <source>");
        for (msg.nodes) |node| { try writeNode(&buf, &node); }
        try buf.appendSlice("</source>\n      </segment>\n    </unit>\n");
    }
    try buf.appendSlice("  </file>\n</xliff>\n");
    return buf.toOwnedSlice();
}

fn writeNode(buf: *std.ArrayList(u8), node: *const i18n_ast.Node) !void {
    switch (node.data) {
        .text => |t| try xml_helper.writeEscaped(buf, t.value),
        .placeholder => |ph| { try buf.appendSlice("<ph id=\""); try buf.appendSlice(ph.name); try buf.appendSlice(\"/>\"); },
        else => {},
    }
}
