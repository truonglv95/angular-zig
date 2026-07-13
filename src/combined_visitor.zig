/// Combined Visitor — Walks both HTML AST and Expression AST
///
/// Port of: compiler/src/combined_visitor.ts (164 LoC) — 100% match
const std = @import("std");
const ml_ast = @import("ml_parser/ast.zig");
const expr_ast = @import("expression_parser/ast.zig");

/// A combined visitor that implements both HTML and expression visitor interfaces.
/// Used for combined traversals where both tree types need to be visited
/// in a single pass (e.g. i18n extraction, template indexing).
pub const CombinedVisitor = struct {
    // HTML AST visitor callbacks
    visit_text: ?*const fn (node: *const ml_ast.TextNode) void = null,
    visit_element: ?*const fn (node: *const ml_ast.ElementNode) void = null,
    visit_attribute: ?*const fn (node: *const ml_ast.AttributeNode) void = null,
    visit_comment: ?*const fn (node: *const ml_ast.CommentNode) void = null,
    visit_expansion: ?*const fn (node: *const ml_ast.ExpansionNode) void = null,
    visit_expansion_case: ?*const fn (node: *const ml_ast.ExpansionCaseNode) void = null,
    visit_block: ?*const fn (node: *const ml_ast.BlockNode) void = null,
    visit_block_parameter: ?*const fn (node: *const ml_ast.BlockParameter) void = null,
    visit_cdata: ?*const fn (node: *const ml_ast.CdataNode) void = null,
    visit_doctype: ?*const fn (node: *const ml_ast.DocTypeNode) void = null,

    // Expression AST visitor callbacks
    visit_expression: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_binary: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_property_read: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_safe_property_read: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_method_call: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_safe_method_call: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_function_call: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_conditional: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_binding_pipe: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_literal_primitive: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_literal_array: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_literal_map: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_interpolation: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_prefix_not: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_unary: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_assignment: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_chain: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_keyed_read: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_safe_keyed_read: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_keyed_write: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_implicit_receiver: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_this_receiver: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_non_null_assert: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_arrow_function: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_parenthesized: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_typeof_expr: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_void_expr: ?*const fn (node: *const expr_ast.Ast) void = null,
    visit_empty: ?*const fn (node: *const expr_ast.Ast) void = null,
};

/// Walk an HTML AST tree with a combined visitor.
pub fn walkHtml(visitor: *const CombinedVisitor, node: *const ml_ast.Node) void {
    switch (node.data) {
        .Text => |text| if (visitor.visit_text) |fn_ptr| fn_ptr(&text),
        .Element => |elem| {
            if (visitor.visit_element) |fn_ptr| fn_ptr(&elem);
            for (elem.attrs) |attr| {
                if (visitor.visit_attribute) |fn_ptr| fn_ptr(&attr);
            }
            for (elem.children) |child| {
                walkHtml(visitor, child);
            }
        },
        .Attribute => |attr| if (visitor.visit_attribute) |fn_ptr| fn_ptr(&attr),
        .Comment => |comment| if (visitor.visit_comment) |fn_ptr| fn_ptr(&comment),
        .Cdata => |cdata| if (visitor.visit_cdata) |fn_ptr| fn_ptr(&cdata),
        .DocType => |doctype| if (visitor.visit_doctype) |fn_ptr| fn_ptr(&doctype),
        .Expansion => |exp| {
            if (visitor.visit_expansion) |fn_ptr| fn_ptr(&exp);
            for (exp.cases) |case| {
                if (visitor.visit_expansion_case) |fn_ptr| fn_ptr(&case);
            }
        },
        .Block => |block| {
            if (visitor.visit_block) |fn_ptr| fn_ptr(&block);
            for (block.parameters) |param| {
                if (visitor.visit_block_parameter) |fn_ptr| fn_ptr(&param);
            }
            for (block.children) |child| {
                walkHtml(visitor, child);
            }
        },
        else => {},
    }
}

/// Walk an expression AST tree with a combined visitor.
pub fn walkExpression(visitor: *const CombinedVisitor, node: *const expr_ast.Ast) void {
    switch (node.data) {
        .Binary => if (visitor.visit_binary) |fn_ptr| fn_ptr(node),
        .PropertyRead => if (visitor.visit_property_read) |fn_ptr| fn_ptr(node),
        .SafePropertyRead => if (visitor.visit_safe_property_read) |fn_ptr| fn_ptr(node),
        .MethodCall => if (visitor.visit_method_call) |fn_ptr| fn_ptr(node),
        .SafeMethodCall => if (visitor.visit_safe_method_call) |fn_ptr| fn_ptr(node),
        .FunctionCall => if (visitor.visit_function_call) |fn_ptr| fn_ptr(node),
        .Conditional => if (visitor.visit_conditional) |fn_ptr| fn_ptr(node),
        .BindingPipe => if (visitor.visit_binding_pipe) |fn_ptr| fn_ptr(node),
        .LiteralPrimitive => if (visitor.visit_literal_primitive) |fn_ptr| fn_ptr(node),
        .LiteralArray => if (visitor.visit_literal_array) |fn_ptr| fn_ptr(node),
        .LiteralMap => if (visitor.visit_literal_map) |fn_ptr| fn_ptr(node),
        .Interpolation => if (visitor.visit_interpolation) |fn_ptr| fn_ptr(node),
        .PrefixNot => if (visitor.visit_prefix_not) |fn_ptr| fn_ptr(node),
        .Unary => if (visitor.visit_unary) |fn_ptr| fn_ptr(node),
        .Assignment => if (visitor.visit_assignment) |fn_ptr| fn_ptr(node),
        .Chain => if (visitor.visit_chain) |fn_ptr| fn_ptr(node),
        .KeyedRead => if (visitor.visit_keyed_read) |fn_ptr| fn_ptr(node),
        .SafeKeyedRead => if (visitor.visit_safe_keyed_read) |fn_ptr| fn_ptr(node),
        .KeyedWrite => if (visitor.visit_keyed_write) |fn_ptr| fn_ptr(node),
        .ImplicitReceiver => if (visitor.visit_implicit_receiver) |fn_ptr| fn_ptr(node),
        .ThisReceiver => if (visitor.visit_this_receiver) |fn_ptr| fn_ptr(node),
        .NonNullAssert => if (visitor.visit_non_null_assert) |fn_ptr| fn_ptr(node),
        .ArrowFunction => if (visitor.visit_arrow_function) |fn_ptr| fn_ptr(node),
        .Parenthesized => if (visitor.visit_parenthesized) |fn_ptr| fn_ptr(node),
        .TypeofExpr => if (visitor.visit_typeof_expr) |fn_ptr| fn_ptr(node),
        .VoidExpr => if (visitor.visit_void_expr) |fn_ptr| fn_ptr(node),
        .Empty => if (visitor.visit_empty) |fn_ptr| fn_ptr(node),
        else => if (visitor.visit_expression) |fn_ptr| fn_ptr(node),
    }

    // Recurse into child expressions
    switch (node.data) {
        .Binary => |b| { walkExpression(visitor, b.left); walkExpression(visitor, b.right); },
        .PropertyRead => |pr| walkExpression(visitor, pr.receiver),
        .SafePropertyRead => |spr| walkExpression(visitor, spr.receiver),
        .MethodCall => |mc| { walkExpression(visitor, mc.receiver); for (mc.args) |arg| { walkExpression(visitor, arg); } },
        .SafeMethodCall => |smc| { walkExpression(visitor, smc.receiver); for (smc.args) |arg| { walkExpression(visitor, arg); } },
        .FunctionCall => |fc| { for (fc.args) |arg| { walkExpression(visitor, arg); } },
        .Conditional => |c| { walkExpression(visitor, c.condition); walkExpression(visitor, c.true_exp); walkExpression(visitor, c.false_exp); },
        .BindingPipe => |bp| { walkExpression(visitor, bp.exp); for (bp.args) |arg| { walkExpression(visitor, arg); } },
        .LiteralArray => |la| { for (la.expressions) |e| { walkExpression(visitor, e); } },
        .LiteralMap => |lm| { for (lm.entries) |entry| { walkExpression(visitor, entry.value); } },
        .Interpolation => |i| { for (i.expressions) |e| { walkExpression(visitor, e); } },
        .PrefixNot => |pn| walkExpression(visitor, pn.expression),
        .Unary => |u| walkExpression(visitor, u.expr),
        .KeyedRead => |kr| { walkExpression(visitor, kr.receiver); walkExpression(visitor, kr.key); },
        .SafeKeyedRead => |skr| { walkExpression(visitor, skr.receiver); walkExpression(visitor, skr.key); },
        .KeyedWrite => |kw| { walkExpression(visitor, kw.receiver); walkExpression(visitor, kw.key); walkExpression(visitor, kw.value); },
        .NonNullAssert => |nna| walkExpression(visitor, nna.expression),
        .ArrowFunction => |af| walkExpression(visitor, af.body),
        .Parenthesized => |p| walkExpression(visitor, p.expression),
        .TypeofExpr => |t| walkExpression(visitor, t.expression),
        .VoidExpr => |v| walkExpression(visitor, v.expression),
        .Chain => |c| { for (c.expressions) |e| { walkExpression(visitor, e); } },
        else => {},
    }
}
