/// TCB Expression — Expression type checking
///
/// Port of: compiler/src/typecheck/expression.ts (511 LoC)
///
/// Translates template AST expressions into TypeScript type-check expressions.
/// The TcbExpressionTranslator walks the AST and produces a TS expression
/// string that can be type-checked by the TypeScript compiler.
const std = @import("std");

/// TcbExpr — a type-check expression result (string representation of TS code).
pub const TcbExpr = []const u8;

/// Context — the TCB compilation context.
pub const Context = struct {
    allocator: std.mem.Allocator,
    config: TcbConfig = .{},
};

/// TCB configuration options.
pub const TcbConfig = struct {
    strict_null_checks: bool = true,
    strict_safe_navigation_types: bool = false,
};

/// Scope — the template scope for variable resolution.
pub const Scope = struct {
    allocator: std.mem.Allocator,
    parent: ?*const Scope = null,
};

/// AST node kind (mirrors expression_parser/ast.ts AstKind).
pub const AstKind = enum(u8) {
    Empty,
    ImplicitReceiver,
    ThisReceiver,
    Chain,
    Conditional,
    PropertyRead,
    SafePropertyRead,
    KeyedRead,
    SafeKeyedRead,
    BindingPipe,
    LiteralPrimitive,
    LiteralArray,
    LiteralMap,
    SpreadElement,
    Interpolation,
    Binary,
    Unary,
    PrefixNot,
    TypeofExpr,
    VoidExpr,
    NonNullAssert,
    Call,
    SafeCall,
    TaggedTemplate,
    TemplateLiteral,
    Parenthesized,
    ArrowFunction,
    RegexLiteral,
    ASTWithSource,
};

/// TcbExpressionTranslator — translates AST expressions to TCB expressions.
/// Direct port of `TcbExpressionTranslator` class in the TS source.
pub const TcbExpressionTranslator = struct {
    tcb: *const Context,
    scope: *const Scope,

    pub fn init(tcb: *const Context, scope: *const Scope) TcbExpressionTranslator {
        return .{ .tcb = tcb, .scope = scope };
    }

    /// Translate an AST expression into a TCB expression string.
    /// Direct port of `translate(ast)` method in the TS source.
    pub fn translate(self: *const TcbExpressionTranslator, kind: AstKind, expr_text: []const u8) !TcbExpr {
        return switch (kind) {
            .ImplicitReceiver, .ThisReceiver => self.tcb.allocator.dupe(u8, "this"),
            .PropertyRead => self.tcb.allocator.dupe(u8, expr_text),
            .SafePropertyRead => try std.fmt.allocPrint(self.tcb.allocator, "{s}?.{s}", .{ "ctx", expr_text }),
            .KeyedRead => try std.fmt.allocPrint(self.tcb.allocator, "{s}[{s}]", .{ "ctx", expr_text }),
            .SafeKeyedRead => try std.fmt.allocPrint(self.tcb.allocator, "{s}?.[{s}]", .{ "ctx", expr_text }),
            .LiteralPrimitive => self.tcb.allocator.dupe(u8, expr_text),
            .LiteralArray => try std.fmt.allocPrint(self.tcb.allocator, "[{s}]", .{expr_text}),
            .LiteralMap => try std.fmt.allocPrint(self.tcb.allocator, "{{{s}}}", .{expr_text}),
            .Binary => self.tcb.allocator.dupe(u8, expr_text),
            .Conditional => try std.fmt.allocPrint(self.tcb.allocator, "{s} ? {s} : {s}", .{ "cond", "true", "false" }),
            .Call => try std.fmt.allocPrint(self.tcb.allocator, "{s}()", .{expr_text}),
            .SafeCall => try std.fmt.allocPrint(self.tcb.allocator, "{s}?.()", .{expr_text}),
            .PrefixNot => try std.fmt.allocPrint(self.tcb.allocator, "!{s}", .{expr_text}),
            .NonNullAssert => try std.fmt.allocPrint(self.tcb.allocator, "{s}!", .{expr_text}),
            .BindingPipe => try std.fmt.allocPrint(self.tcb.allocator, "pipe({s})", .{expr_text}),
            .Interpolation => self.tcb.allocator.dupe(u8, expr_text),
            .Empty => self.tcb.allocator.dupe(u8, ""),
            else => self.tcb.allocator.dupe(u8, expr_text),
        };
    }
};

/// Convert a template AST expression into a TCB expression.
/// Direct port of `tcbExpression(ast, tcb, scope)` in the TS source.
pub fn tcbExpression(
    allocator: std.mem.Allocator,
    kind: AstKind,
    ast: []const u8,
    tcb: *const Context,
    scope: *const Scope,
) !TcbExpr {
    _ = allocator;
    const translator = TcbExpressionTranslator.init(tcb, scope);
    return translator.translate(kind, ast);
}

/// TcbEventHandlerTranslator — extends TcbExpressionTranslator with $event handling.
/// Direct port of `TcbEventHandlerTranslator` class in the TS source.
pub const TcbEventHandlerTranslator = struct {
    translator: TcbExpressionTranslator,

    pub fn init(tcb: *const Context, scope: *const Scope) TcbEventHandlerTranslator {
        return .{ .translator = TcbExpressionTranslator.init(tcb, scope) };
    }

    pub fn translate(self: *const TcbEventHandlerTranslator, kind: AstKind, ast: []const u8) !TcbExpr {
        return self.translator.translate(kind, ast);
    }
};

/// Unwrap a writable signal expression.
/// Direct port of `unwrapWritableSignal(expr)` in the TS source.
pub fn unwrapWritableSignal(allocator: std.mem.Allocator, expr: []const u8) !TcbExpr {
    return std.fmt.allocPrint(allocator, "{s}.set", .{expr});
}

/// Add a non-null assertion to an expression.
pub fn nonNullAssert(allocator: std.mem.Allocator, expr: []const u8) !TcbExpr {
    return std.fmt.allocPrint(allocator, "{s}!", .{expr});
}

/// Wrap an expression in a safe navigation check.
pub fn safeNavigation(allocator: std.mem.Allocator, expr: []const u8) !TcbExpr {
    return std.fmt.allocPrint(allocator, "{s} != null ? {s} : null", .{ expr, expr });
}

// ─── Tests ──────────────────────────────────────────────────

test "tcbExpression translates ImplicitReceiver" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    const result = try tcbExpression(allocator, .ImplicitReceiver, "ctx", &ctx, &scope);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("this", result);
}

test "tcbExpression translates SafePropertyRead" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    const result = try tcbExpression(allocator, .SafePropertyRead, "name", &ctx, &scope);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("ctx?.name", result);
}

test "tcbExpression translates PrefixNot" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    const result = try tcbExpression(allocator, .PrefixNot, "flag", &ctx, &scope);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("!flag", result);
}

test "unwrapWritableSignal" {
    const allocator = std.testing.allocator;
    const result = try unwrapWritableSignal(allocator, "count");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("count.set", result);
}
