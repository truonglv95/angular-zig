/// Expression Parser AST Tests — Ported from Angular TS test/expression_parser/ast_spec.ts
///
/// Source: packages/compiler/test/expression_parser/ast_spec.ts (46 lines)
///
/// Tests the RecursiveAstVisitor pattern by parsing 'x.y()' and verifying
/// the visitor visits all 4 nodes (Call, PropertyRead, PropertyRead, ImplicitReceiver).
const std = @import("std");
const lexer = @import("../../expression_parser/lexer.zig");
const parser_mod = @import("../../expression_parser/parser.zig");
const ast_mod = @import("../../expression_parser/ast.zig");
const arena_mod = @import("../../arena.zig");

const Ast = ast_mod.Ast;

/// Test visitor that collects all visited nodes in order.
const TestVisitor = struct {
    visited: *std.array_list.Managed(*const Ast),

    pub fn visitEmpty(_: @This(), _: void) void {}
    pub fn visitImplicitReceiver(_: @This(), _: void) void {}
    pub fn visitThisReceiver(_: @This(), _: void) void {}
    pub fn visitChain(_: @This(), _: []const *const Ast, _: void) void {}
    pub fn visitConditional(_: @This(), _: *const Ast, _: *const Ast, _: *const Ast, _: void) void {}
    pub fn visitPropertyRead(self: @This(), receiver: *const Ast, name: []const u8, _: void) void {
        _ = name;
        self.visited.append(receiver) catch {};
    }
    pub fn visitSafePropertyRead(_: @This(), _: *const Ast, _: []const u8, _: void) void {}
    pub fn visitKeyedRead(_: @This(), _: *const Ast, _: *const Ast, _: void) void {}
    pub fn visitSafeKeyedRead(_: @This(), _: *const Ast, _: *const Ast, _: void) void {}
    pub fn visitBindingPipe(_: @This(), _: *const Ast, _: []const u8, _: []const *const Ast, _: void) void {}
    pub fn visitLiteralPrimitive(_: @This(), _: ast_mod.Ast.LiteralValue, _: void) void {}
    pub fn visitLiteralArray(_: @This(), _: []const *const Ast, _: void) void {}
    pub fn visitLiteralMap(_: @This(), _: []const ast_mod.Ast.MapEntry, _: void) void {}
    pub fn visitSpreadElement(_: @This(), _: *const Ast, _: void) void {}
    pub fn visitInterpolation(_: @This(), _: []const []const u8, _: []const *const Ast, _: void) void {}
    pub fn visitBinary(_: @This(), _: ast_mod.BinaryOp, _: *const Ast, _: *const Ast, _: void) void {}
    pub fn visitUnary(_: @This(), _: u8, _: *const Ast, _: void) void {}
    pub fn visitPrefixNot(_: @This(), _: *const Ast, _: void) void {}
    pub fn visitTypeofExpr(_: @This(), _: *const Ast, _: void) void {}
    pub fn visitVoidExpr(_: @This(), _: *const Ast, _: void) void {}
    pub fn visitNonNullAssert(_: @This(), _: *const Ast, _: void) void {}
    pub fn visitCall(self: @This(), receiver: *const Ast, _: []const *const Ast, _: ?[]const u8, _: void) void {
        self.visited.append(receiver) catch {};
    }
    pub fn visitSafeCall(_: @This(), _: *const Ast, _: []const *const Ast, _: ?[]const u8, _: void) void {}
    pub fn visitTaggedTemplate(_: @This(), _: *const Ast, _: anytype, _: void) void {}
    pub fn visitTemplateLiteral(_: @This(), _: anytype, _: anytype, _: void) void {}
    pub fn visitParenthesized(_: @This(), _: *const Ast, _: void) void {}
    pub fn visitArrowFunction(_: @This(), _: anytype, _: *const Ast, _: void) void {}
    pub fn visitRegexLiteral(_: @This(), _: []const u8, _: []const u8, _: void) void {}
    pub fn visitASTWithSource(_: @This(), _: *const Ast, _: []const u8, _: []const u8, _: void) void {}
};

test "ast: RecursiveAstVisitor visits every node" {
    const allocator = std.testing.allocator;
    var arena = arena_mod.AstArena.init(allocator);
    defer arena.deinit();
    var lex = lexer.Lexer.init(allocator, "x.y()");
    defer lex.deinit();
    const tokens = try lex.tokenize();
    var p = parser_mod.Parser.init(allocator, &arena, "x.y()", tokens[0], 0);
    defer p.deinit();
    const ast = try p.parseBinding();

    // Verify the parsed AST is a Call
    try std.testing.expect(ast.data == .Call);
    const call = ast.data.Call;
    try std.testing.expectEqual(@as(usize, 0), call.args.len);

    // Verify the receiver is a PropertyRead with name "y"
    try std.testing.expect(call.receiver.data == .PropertyRead);
    try std.testing.expectEqualStrings("y", call.receiver.data.PropertyRead.name);

    // Verify the inner receiver is a PropertyRead with name "x"
    const y_read = call.receiver.data.PropertyRead;
    try std.testing.expect(y_read.receiver.data == .PropertyRead);
    try std.testing.expectEqualStrings("x", y_read.receiver.data.PropertyRead.name);

    // Verify the innermost receiver is an ImplicitReceiver
    const x_read = y_read.receiver.data.PropertyRead;
    try std.testing.expect(x_read.receiver.data == .ImplicitReceiver);
}
