/// i18n Parser — Convert HTML subtrees to i18n Messages
///
/// Port of: compiler/src/i18n/i18n_parser.ts
const std = @import("std");
const i18n_ast = @import("i18n_ast.zig");

/// Parse an HTML subtree into an i18n Message.
/// This is the main entry point for i18n message extraction.
pub fn parse(allocator: std.mem.Allocator, source: []const u8, meaning: []const u8, description: []const u8, custom_id: []const u8) !i18n_ast.Message {
    var msg = i18n_ast.Message.init(allocator);
    msg.meaning = meaning;
    msg.description = description;
    msg.custom_id = custom_id;
    // TODO: walk the HTML AST and build message nodes
    _ = source;
    return msg;
}
