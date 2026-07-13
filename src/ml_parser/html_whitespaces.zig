/// HTML Whitespaces — WhitespaceVisitor for collapsing/expanding whitespace
///
/// Port of: compiler/src/ml_parser/html_whitespaces.ts (356 LoC)
const std = @import("std");
const ml_ast = @import("ast.zig");

/// Whitespace processing mode.
pub const WhitespaceMode = enum(u8) {
    Preserve, Collapse, Remove,
};

/// Visit and process whitespace in the HTML AST.
/// Collapses redundant whitespace and removes insignificant whitespace
/// based on the preserveWhitespaces config option.
pub fn visitWhitespace(nodes: []const *const ml_ast.Node, mode: WhitespaceMode) void {
    _ = nodes;
    _ = mode;
    // TODO: implement whitespace collapsing
    // The full implementation walks the AST and removes/collapses
    // text nodes that contain only whitespace, except in <pre> and <textarea>.
}
