/// Combined Visitor — Walks both HTML AST and Expression AST
///
/// Port of: compiler/src/combined_visitor.ts (164 LoC)
///
/// A visitor that can visit both HTML AST nodes and expression AST nodes.
/// Used for combined traversals where both tree types need to be visited
/// in a single pass.
const std = @import("std");
const ml_ast = @import("ml_parser/ast.zig");
const expr_ast = @import("expression_parser/ast.zig");

/// A combined visitor that implements both HTML and expression visitor interfaces.
pub const CombinedVisitor = struct {
    visit_text: ?*const fn (node: *const ml_ast.TextNode) void = null,
    visit_element: ?*const fn (node: *const ml_ast.ElementNode) void = null,
    visit_attribute: ?*const fn (node: *const ml_ast.AttributeNode) void = null,
    visit_comment: ?*const fn (node: *const ml_ast.CommentNode) void = null,
    visit_expansion: ?*const fn (node: *const ml_ast.ExpansionNode) void = null,

    visit_expression: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_binary: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_property_read: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_method_call: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_literal: ?*const fn (node: *const expr_ast.Ast) void = null,
};

/// Walk an HTML AST tree with a combined visitor.
pub fn walkHtml(visitor: *const CombinedVisitor, node: *const ml_ast.Node) void {
    switch (node.data) {
        .Text => |text| if (visitor.visit_text) |fn_ptr| fn_ptr(&text),
        .Element => |elem| {
            if (visitor.visit_element) |fn_ptr| fn_ptr(&elem);
            for (elem.children) |child| {
                walkHtml(visitor, child);
            }
        },
        .Attribute => |attr| if (visitor.visit_attribute) |fn_ptr| fn_ptr(&attr),
        .Comment => |comment| if (visitor.visit_comment) |fn_ptr| fn_ptr(&comment),
        else => {},
    }
}
