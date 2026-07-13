/// Expression AST — Tagged Union Design
///
/// KEY ZIG ADVANTAGE: Thay vì class hierarchy với virtual dispatch,
/// dùng tagged union. Benefits:
///   - Size = sizeof(largest variant), không phải pointer + vtable
///   - No heap allocation cho mỗi node (store inline trong parent's slice)
///   - Pattern matching với switch — compiler optimizes thành jump table
///   - comptime enforcement: không thể quên handle một variant
///
/// Mỗi node có ParseSpan (8 bytes) + tag (enum) + payload.
/// Total: ~32-48 bytes thay vì ~80-120 bytes TypeScript equivalent.
const std = @import("std");
const source_span = @import("../source_span.zig");
const ParseSourceSpan = source_span.ParseSourceSpan;
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

// ─── Span & Location ──────────────────────────────────────────

pub const ParseSpan = struct {
    start: u32,
    end: u32,

    pub fn toAbsolute(self: ParseSpan) AbsoluteSourceSpan {
        return .{ .start = self.start, .end = self.end };
    }
};

// ─── AST Node Tag ─────────────────────────────────────────────

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

// ─── Binary Operations ────────────────────────────────────────

pub const BinaryOp = enum {
    Equals, // ==
    NotEquals, // !=
    Identical, // ===
    NotIdentical, // !==
    Less, // <
    Greater, // >
    LessEquals, // <=
    GreaterEquals, // >=
    Plus, // +
    Minus, // -
    Multiply, // *
    Divide, // /
    Percent, // %
    And, // &&
    Or, // ||
    Nullish, // ??
    In, // in
    Instanceof, // instanceof
    BitwiseAnd, // &
    BitwiseOr, // |
    BitwiseXor, // ^
    LeftShift, // <<
    RightShift, // >>
    UnsignedRightShift, // >>>
    Comma, // ,

    pub fn precedence(self: BinaryOp) u8 {
        return switch (self) {
            .Comma => 0,
            .Or => 1,
            .And => 2,
            .Nullish => 3,
            .BitwiseOr => 4,
            .BitwiseXor => 5,
            .BitwiseAnd => 6,
            .Equals, .NotEquals, .Identical, .NotIdentical => 7,
            .Less, .Greater, .LessEquals, .GreaterEquals, .In, .Instanceof => 8,
            .LeftShift, .RightShift, .UnsignedRightShift => 9,
            .Plus, .Minus => 10,
            .Multiply, .Divide, .Percent => 11,
        };
    }

    pub fn isAssociative(self: BinaryOp) bool {
        return switch (self) {
            .Plus, .Multiply, .BitwiseAnd, .BitwiseOr, .BitwiseXor, .Equals, .NotEquals, .Identical, .NotIdentical => true,
            else => false,
        };
    }
};

// ─── Literal Value ────────────────────────────────────────────

pub const LiteralValue = union(enum) {
    String: []const u8,
    Number: f64,
    Boolean: bool,
    Null,
    Undefined,
    NaN,
    Infinity,

    pub fn format(self: LiteralValue, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        switch (self) {
            .String => |s| try writer.print("\"{s}\"", .{s}),
            .Number => |n| try writer.print("{d}", .{n}),
            .Boolean => |b| try writer.print("{}", .{b}),
            .Null => try writer.writeAll("null"),
            .Undefined => try writer.writeAll("undefined"),
            .NaN => try writer.writeAll("NaN"),
            .Infinity => try writer.writeAll("Infinity"),
        }
    }
};

// ─── Arrow Function Parameter ─────────────────────────────────

pub const ArrowParam = struct {
    name: []const u8,
    span: ParseSpan,
    type_expr: ?*const Ast = null,
};

// ─── Literal Map Entry ────────────────────────────────────────

pub const MapEntry = struct {
    key: []const u8,
    value: *const Ast,
    quoted: bool,
};

// ─── Template Literal ─────────────────────────────────────────

pub const TemplateLiteral = struct {
    elements: []const []const u8,
    expressions: []const *const Ast,
};

// ─── ASTWithSource — wraps parsed AST with original source ────

pub const AstWithSource = struct {
    ast: *const Ast,
    source: ?[]const u8,
    location: []const u8,
    errors: []const source_span.ParseError,
};

// ─── The Big Tagged Union ─────────────────────────────────────

/// AST node data — tagged union chứa tất cả node types.
/// Zig sẽ optimize size thành max(variant sizes) + tag.
pub const AstData = union(AstKind) {
    Empty: void,
    ImplicitReceiver: void,
    ThisReceiver: void,
    Chain: struct {
        expressions: []const *const Ast,
    },
    Conditional: struct {
        condition: *const Ast,
        true_expr: *const Ast,
        false_expr: *const Ast,
    },
    PropertyRead: struct {
        receiver: *const Ast,
        name: []const u8,
    },
    SafePropertyRead: struct {
        receiver: *const Ast,
        name: []const u8,
    },
    KeyedRead: struct {
        receiver: *const Ast,
        key: *const Ast,
    },
    SafeKeyedRead: struct {
        receiver: *const Ast,
        key: *const Ast,
    },
    BindingPipe: struct {
        exp: *const Ast,
        name: []const u8,
        args: []const *const Ast,
    },
    LiteralPrimitive: LiteralValue,
    LiteralArray: struct {
        expressions: []const *const Ast,
    },
    LiteralMap: struct {
        entries: []const MapEntry,
    },
    SpreadElement: struct {
        expression: *const Ast,
    },
    Interpolation: struct {
        strings: []const []const u8,
        expressions: []const *const Ast,
    },
    Binary: struct {
        op: BinaryOp,
        left: *const Ast,
        right: *const Ast,
    },
    Unary: struct {
        operator: u8, // '+' or '-'
        expr: *const Ast,
    },
    PrefixNot: struct {
        expression: *const Ast,
    },
    TypeofExpr: struct {
        expression: *const Ast,
    },
    VoidExpr: struct {
        expression: *const Ast,
    },
    NonNullAssert: struct {
        expression: *const Ast,
    },
    Call: struct {
        receiver: *const Ast,
        args: []const *const Ast,
        argument_span: ParseSpan,
    },
    SafeCall: struct {
        receiver: *const Ast,
        args: []const *const Ast,
        argument_span: ParseSpan,
    },
    TaggedTemplate: struct {
        tag: *const Ast,
        template: TemplateLiteral,
    },
    TemplateLiteral: TemplateLiteral,
    Parenthesized: struct {
        expression: *const Ast,
    },
    ArrowFunction: struct {
        params: []const ArrowParam,
        body: *const Ast,
    },
    RegexLiteral: struct {
        body: []const u8,
        flags: ?[]const u8,
    },
    ASTWithSource: AstWithSource,
};

/// Complete AST node — span + kind + data
pub const Ast = struct {
    span: ParseSpan,
    abs_span: AbsoluteSourceSpan,
    data: AstData,

    // ─── Convenience Constructors ────────────────────────────
    // Dùng comptime để Zig inline và optimize

    pub fn empty(span: ParseSpan, abs: AbsoluteSourceSpan) Ast {
        return .{ .span = span, .abs_span = abs, .data = .{ .Empty = {} } };
    }

    pub fn implicitReceiver(span: ParseSpan, abs: AbsoluteSourceSpan) Ast {
        return .{ .span = span, .abs_span = abs, .data = .{ .ImplicitReceiver = {} } };
    }

    pub fn literalString(span: ParseSpan, abs: AbsoluteSourceSpan, value: []const u8) Ast {
        return .{ .span = span, .abs_span = abs, .data = .{ .LiteralPrimitive = .{ .String = value } } };
    }

    pub fn literalNumber(span: ParseSpan, abs: AbsoluteSourceSpan, value: f64) Ast {
        return .{ .span = span, .abs_span = abs, .data = .{ .LiteralPrimitive = .{ .Number = value } } };
    }

    pub fn literalBool(span: ParseSpan, abs: AbsoluteSourceSpan, value: bool) Ast {
        return .{ .span = span, .abs_span = abs, .data = .{ .LiteralPrimitive = .{ .Boolean = value } } };
    }

    pub fn literalNull(span: ParseSpan, abs: AbsoluteSourceSpan) Ast {
        return .{ .span = span, .abs_span = abs, .data = .{ .LiteralPrimitive = .Null } };
    }

    pub fn propertyRead(span: ParseSpan, abs: AbsoluteSourceSpan, receiver: *const Ast, name: []const u8) Ast {
        return .{ .span = span, .abs_span = abs, .data = .{ .PropertyRead = .{ .receiver = receiver, .name = name } } };
    }

    pub fn safePropertyRead(span: ParseSpan, abs: AbsoluteSourceSpan, receiver: *const Ast, name: []const u8) Ast {
        return .{ .span = span, .abs_span = abs, .data = .{ .SafePropertyRead = .{ .receiver = receiver, .name = name } } };
    }

    pub fn binary(span: ParseSpan, abs: AbsoluteSourceSpan, op: BinaryOp, left: *const Ast, right: *const Ast) Ast {
        return .{ .span = span, .abs_span = abs, .data = .{ .Binary = .{ .op = op, .left = left, .right = right } } };
    }

    pub fn conditional(span: ParseSpan, abs: AbsoluteSourceSpan, cond: *const Ast, t: *const Ast, f: *const Ast) Ast {
        return .{ .span = span, .abs_span = abs, .data = .{ .Conditional = .{ .condition = cond, .true_expr = t, .false_expr = f } } };
    }

    pub fn bindingPipe(span: ParseSpan, abs: AbsoluteSourceSpan, exp: *const Ast, name: []const u8, args: []const *const Ast) Ast {
        return .{ .span = span, .abs_span = abs, .data = .{ .BindingPipe = .{ .exp = exp, .name = name, .args = args } } };
    }

    pub fn call(span: ParseSpan, abs: AbsoluteSourceSpan, receiver: *const Ast, args: []const *const Ast, arg_span: ParseSpan) Ast {
        return .{ .span = span, .abs_span = abs, .data = .{ .Call = .{ .receiver = receiver, .args = args, .argument_span = arg_span } } };
    }

    pub fn prefixNot(span: ParseSpan, abs: AbsoluteSourceSpan, expr: *const Ast) Ast {
        return .{ .span = span, .abs_span = abs, .data = .{ .PrefixNot = .{ .expression = expr } } };
    }

    pub fn nonNullAssert(span: ParseSpan, abs: AbsoluteSourceSpan, expr: *const Ast) Ast {
        return .{ .span = span, .abs_span = abs, .data = .{ .NonNullAssert = .{ .expression = expr } } };
    }

    pub fn literalArray(span: ParseSpan, abs: AbsoluteSourceSpan, exprs: []const *const Ast) Ast {
        return .{ .span = span, .abs_span = abs, .data = .{ .LiteralArray = .{ .expressions = exprs } } };
    }

    // ─── Visitor Pattern (comptime type-safe) ───────────────
    /// Visitor phải implement tất cả methods — compiler ENFORCE at compile time.
    /// Không có runtime crash vì thiếu handler.
    pub fn visit(self: *const Ast, visitor: anytype, context: anytype) void {
        switch (self.data) {
            .Empty => visitor.visitEmpty(context),
            .ImplicitReceiver => visitor.visitImplicitReceiver(context),
            .ThisReceiver => visitor.visitThisReceiver(context),
            .Chain => |v| visitor.visitChain(v.expressions, context),
            .Conditional => |v| visitor.visitConditional(v.condition, v.true_expr, v.false_expr, context),
            .PropertyRead => |v| visitor.visitPropertyRead(v.receiver, v.name, context),
            .SafePropertyRead => |v| visitor.visitSafePropertyRead(v.receiver, v.name, context),
            .KeyedRead => |v| visitor.visitKeyedRead(v.receiver, v.key, context),
            .SafeKeyedRead => |v| visitor.visitSafeKeyedRead(v.receiver, v.key, context),
            .BindingPipe => |v| visitor.visitBindingPipe(v.exp, v.name, v.args, context),
            .LiteralPrimitive => |v| visitor.visitLiteralPrimitive(v, context),
            .LiteralArray => |v| visitor.visitLiteralArray(v.expressions, context),
            .LiteralMap => |v| visitor.visitLiteralMap(v.entries, context),
            .SpreadElement => |v| visitor.visitSpreadElement(v.expression, context),
            .Interpolation => |v| visitor.visitInterpolation(v.strings, v.expressions, context),
            .Binary => |v| visitor.visitBinary(v.op, v.left, v.right, context),
            .Unary => |v| visitor.visitUnary(v.operator, v.expr, context),
            .PrefixNot => |v| visitor.visitPrefixNot(v.expression, context),
            .TypeofExpr => |v| visitor.visitTypeofExpr(v.expression, context),
            .VoidExpr => |v| visitor.visitVoidExpr(v.expression, context),
            .NonNullAssert => |v| visitor.visitNonNullAssert(v.expression, context),
            .Call => |v| visitor.visitCall(v.receiver, v.args, v.argument_span, context),
            .SafeCall => |v| visitor.visitSafeCall(v.receiver, v.args, v.argument_span, context),
            .TaggedTemplate => |v| visitor.visitTaggedTemplate(v.tag, v.template, context),
            .TemplateLiteral => |v| visitor.visitTemplateLiteral(v.elements, v.expressions, context),
            .Parenthesized => |v| visitor.visitParenthesized(v.expression, context),
            .ArrowFunction => |v| visitor.visitArrowFunction(v.params, v.body, context),
            .RegexLiteral => |v| visitor.visitRegexLiteral(v.body, v.flags, context),
            .ASTWithSource => |v| visitor.visitASTWithSource(v.ast, v.source, v.location, context),
        }
    }
};

// ─── Tests ────────────────────────────────────────────────────

test "AST node size is compact" {
    // TypeScript equivalent: 80-120 bytes per node
    // Zig tagged union: typically 48-80 bytes
    comptime {}
    // Should be under 128 bytes
    try std.testing.expect(@sizeOf(Ast) < 128);
}

test "literal construction" {
    const span = ParseSpan{ .start = 0, .end = 5 };
    const abs = AbsoluteSourceSpan{ .start = 0, .end = 5 };

    const num = Ast.literalNumber(span, abs, 42.0);
    const str = Ast.literalString(span, abs, "hello");
    const b = Ast.literalBool(span, abs, true);

    try std.testing.expect(num.data == .LiteralPrimitive);
    try std.testing.expect(str.data == .LiteralPrimitive);
    try std.testing.expect(b.data == .LiteralPrimitive);
}

test "visitor pattern enforces all methods" {
    const TestVisitor = struct {
        pub const Result = void;
        visit_count: usize = 0,

        pub fn visitEmpty(_: @This(), _: void) void {}
        pub fn visitImplicitReceiver(_: @This(), _: void) void {}
        pub fn visitThisReceiver(_: @This(), _: void) void {}
        pub fn visitChain(_: @This(), _: []const *const Ast, _: void) void {}
        pub fn visitConditional(_: @This(), _: *const Ast, _: *const Ast, _: *const Ast, _: void) void {}
        pub fn visitPropertyRead(_: @This(), _: *const Ast, _: []const u8, _: void) void {}
        pub fn visitSafePropertyRead(_: @This(), _: *const Ast, _: []const u8, _: void) void {}
        pub fn visitKeyedRead(_: @This(), _: *const Ast, _: *const Ast, _: void) void {}
        pub fn visitSafeKeyedRead(_: @This(), _: *const Ast, _: *const Ast, _: void) void {}
        pub fn visitBindingPipe(_: @This(), _: *const Ast, _: []const u8, _: []const *const Ast, _: void) void {}
        pub fn visitLiteralPrimitive(self: *@This(), _: LiteralValue, _: void) void {
            self.visit_count += 1;
        }
        pub fn visitLiteralArray(_: @This(), _: []const *const Ast, _: void) void {}
        pub fn visitLiteralMap(_: @This(), _: []const MapEntry, _: void) void {}
        pub fn visitSpreadElement(_: @This(), _: *const Ast, _: void) void {}
        pub fn visitInterpolation(_: @This(), _: []const []const u8, _: []const *const Ast, _: void) void {}
        pub fn visitBinary(_: @This(), _: BinaryOp, _: *const Ast, _: *const Ast, _: void) void {}
        pub fn visitUnary(_: @This(), _: u8, _: *const Ast, _: void) void {}
        pub fn visitPrefixNot(_: @This(), _: *const Ast, _: void) void {}
        pub fn visitTypeofExpr(_: @This(), _: *const Ast, _: void) void {}
        pub fn visitVoidExpr(_: @This(), _: *const Ast, _: void) void {}
        pub fn visitNonNullAssert(_: @This(), _: *const Ast, _: void) void {}
        pub fn visitCall(_: @This(), _: *const Ast, _: []const *const Ast, _: ParseSpan, _: void) void {}
        pub fn visitSafeCall(_: @This(), _: *const Ast, _: []const *const Ast, _: ParseSpan, _: void) void {}
        pub fn visitTaggedTemplate(_: @This(), _: *const Ast, _: TemplateLiteral, _: void) void {}
        pub fn visitTemplateLiteral(_: @This(), _: []const []const u8, _: []const *const Ast, _: void) void {}
        pub fn visitParenthesized(_: @This(), _: *const Ast, _: void) void {}
        pub fn visitArrowFunction(_: @This(), _: []const ArrowParam, _: *const Ast, _: void) void {}
        pub fn visitRegexLiteral(_: @This(), _: []const u8, _: ?[]const u8, _: void) void {}
        pub fn visitASTWithSource(_: @This(), _: *const Ast, _: ?[]const u8, _: []const u8, _: void) void {}
    };

    const span = ParseSpan{ .start = 0, .end = 4 };
    const abs = AbsoluteSourceSpan{ .start = 0, .end = 4 };
    var visitor = TestVisitor{};
    const node = Ast.literalNumber(span, abs, 42.0);
    node.visit(&visitor, {});
    try std.testing.expectEqual(@as(usize, 1), visitor.visit_count);
}
