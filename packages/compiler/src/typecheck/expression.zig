/// TCB Expression — Expression type checking
///
/// Port of: compiler/src/typecheck/expression.ts (511 LoC)
///
/// Translates template AST expressions into TypeScript type-check expressions.
/// The TcbExprTranslator walks the AST and produces a TS expression
/// string that can be type-checked by the TypeScript compiler.
///
/// Key design notes:
///   - `TcbExpr` is modeled as a struct that owns a string buffer plus
///     flags for `wrapped`, `ignore_diagnostics`, and an optional parse
///     span info suffix. Methods like `print()`, `wrapForTypeChecker()`,
///     `addParseSpanInfo()`, and `markIgnoreDiagnostics()` mirror the
///     chainable API of the TS class.
///   - `TcbExprTranslator` implements the AstVisitor pattern via a
///     switch on a tagged union `AstNode`. Each `visitX` method returns
///     a fresh `TcbExpr`.
///   - `VeSafeLhsInferenceBugDetector` mirrors the singleton visitor
///     used to detect when ViewEngine's safe-navigation inference would
///     produce `any` — this affects how we emit safe-property reads.
///   - All recursive translator methods use `anyerror!TcbExpr` to avoid
///     dependency-loop issues between modules.
const std = @import("std");

// ─── Public imports re-exported for callers ─────────────────
pub const TypeCheckingConfig = @import("api.zig").TypeCheckingConfig;

// ─── SourceSpan (mirrors expression_parser/ast.ts) ──────────

/// AbsoluteSourceSpan — start/end byte offsets in source.
pub const AbsoluteSourceSpan = struct {
    start: u32,
    end: u32,

    pub fn empty() AbsoluteSourceSpan {
        return .{ .start = 0, .end = 0 };
    }

    pub fn contains(self: AbsoluteSourceSpan, offset: u32) bool {
        return offset >= self.start and offset < self.end;
    }

    /// Convert to a relative ParseSpan (used when attaching parse span info).
    pub fn toSpan(self: AbsoluteSourceSpan) ParseSpan {
        return .{ .start = self.start, .end = self.end };
    }
};

/// ParseSpan — relative byte offsets within a parse region.
pub const ParseSpan = struct {
    start: u32,
    end: u32,

    pub fn empty() ParseSpan {
        return .{ .start = 0, .end = 0 };
    }
};

// ─── LiteralValue ──────────────────────────────────────────

/// LiteralValue — values supported by LiteralPrimitive AST nodes.
pub const LiteralValue = union(enum) {
    String: []const u8,
    Number: f64,
    Boolean: bool,
    Null,
    Undefined,

    pub fn isString(self: LiteralValue) bool {
        return self == .String;
    }

    pub fn isNumber(self: LiteralValue) bool {
        return self == .Number;
    }

    pub fn isBoolean(self: LiteralValue) bool {
        return self == .Boolean;
    }
};

// ─── BinaryOp ──────────────────────────────────────────────

/// BinaryOp — operation kind for a Binary AST node.
pub const BinaryOp = enum {
    Equals,
    NotEquals,
    Identical,
    NotIdentical,
    Less,
    Greater,
    LessEquals,
    GreaterEquals,
    Plus,
    Minus,
    Multiply,
    Divide,
    Percent,
    And,
    Or,
    Nullish,
    Exponent, // **
    In,
    Instanceof,
    BitwiseAnd,
    BitwiseOr,
    BitwiseXor,
    LeftShift,
    RightShift,
    UnsignedRightShift,
    Comma,

    /// Returns the operator as a string (mirrors `ast.operation` in TS source).
    pub fn symbol(self: BinaryOp) []const u8 {
        return switch (self) {
            .Equals => "==",
            .NotEquals => "!=",
            .Identical => "===",
            .NotIdentical => "!==",
            .Less => "<",
            .Greater => ">",
            .LessEquals => "<=",
            .GreaterEquals => ">=",
            .Plus => "+",
            .Minus => "-",
            .Multiply => "*",
            .Divide => "/",
            .Percent => "%",
            .And => "&&",
            .Or => "||",
            .Nullish => "??",
            .Exponent => "**",
            .In => "in",
            .Instanceof => "instanceof",
            .BitwiseAnd => "&",
            .BitwiseOr => "|",
            .BitwiseXor => "^",
            .LeftShift => "<<",
            .RightShift => ">>",
            .UnsignedRightShift => ">>>",
            .Comma => ",",
        };
    }
};

// ─── Unary operator ────────────────────────────────────────

/// UnaryOperator — unary prefix operators supported by templates.
pub const UnaryOperator = enum {
    Plus,
    Minus,

    pub fn symbol(self: UnaryOperator) []const u8 {
        return switch (self) {
            .Plus => "+",
            .Minus => "-",
        };
    }
};

// ─── LiteralMapKey kind ────────────────────────────────────

/// LiteralMapKeyKind — kind of a key in a literal map.
pub const LiteralMapKeyKind = enum { property, spread };

/// LiteralMapKey — a single key in a literal map.
pub const LiteralMapKey = struct {
    kind: LiteralMapKeyKind,
    key: []const u8 = "",
    source_span: AbsoluteSourceSpan = .{ .start = 0, .end = 0 },
};

// ─── Simplified AST node tagged union ──────────────────────

/// AstKind — the kind tag for the `AstNode` tagged union.
/// Mirrors `AstKind` in `expression_parser/ast.ts`.
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

/// ArrowParam — a parameter for an arrow function AST node.
pub const ArrowParam = struct {
    name: []const u8,
};

/// TemplateLiteralData — pieces + interpolated expressions.
pub const TemplateLiteralData = struct {
    elements: []const []const u8,
    expressions: []const *const AstNode,
};

/// AstNode — simplified AST node used by the translator.
/// Mirrors the `AST` class hierarchy in the TS source via a tagged union.
pub const AstNode = struct {
    span: ParseSpan = .{ .start = 0, .end = 0 },
    source_span: AbsoluteSourceSpan = .{ .start = 0, .end = 0 },
    name_span: ?AbsoluteSourceSpan = null,
    argument_span: ?AbsoluteSourceSpan = null,
    data: AstData,

    pub const AstData = union(AstKind) {
        Empty: void,
        ImplicitReceiver: void,
        ThisReceiver: void,
        Chain: struct { expressions: []const *const AstNode },
        Conditional: struct {
            condition: *const AstNode,
            true_exp: *const AstNode,
            false_exp: *const AstNode,
        },
        PropertyRead: struct {
            receiver: *const AstNode,
            name: []const u8,
        },
        SafePropertyRead: struct {
            receiver: *const AstNode,
            name: []const u8,
        },
        KeyedRead: struct {
            receiver: *const AstNode,
            key: *const AstNode,
        },
        SafeKeyedRead: struct {
            receiver: *const AstNode,
            key: *const AstNode,
        },
        BindingPipe: struct {
            exp: *const AstNode,
            name: []const u8,
            args: []const *const AstNode,
        },
        LiteralPrimitive: struct { value: LiteralValue },
        LiteralArray: struct { expressions: []const *const AstNode },
        LiteralMap: struct {
            keys: []const LiteralMapKey,
            values: []const *const AstNode,
        },
        SpreadElement: struct { expression: *const AstNode },
        Interpolation: struct {
            strings: []const []const u8,
            expressions: []const *const AstNode,
        },
        Binary: struct {
            operation: BinaryOp,
            left: *const AstNode,
            right: *const AstNode,
        },
        Unary: struct {
            operator: UnaryOperator,
            expr: *const AstNode,
        },
        PrefixNot: struct { expression: *const AstNode },
        TypeofExpr: struct { expression: *const AstNode },
        VoidExpr: struct { expression: *const AstNode },
        NonNullAssert: struct { expression: *const AstNode },
        Call: struct {
            receiver: *const AstNode,
            args: []const *const AstNode,
        },
        SafeCall: struct {
            receiver: *const AstNode,
            args: []const *const AstNode,
        },
        TaggedTemplate: struct {
            tag: *const AstNode,
            template: TemplateLiteralData,
        },
        TemplateLiteral: TemplateLiteralData,
        Parenthesized: struct { expression: *const AstNode },
        ArrowFunction: struct {
            parameters: []const ArrowParam,
            body: *const AstNode,
        },
        RegexLiteral: struct {
            body: []const u8,
            flags: ?[]const u8,
        },
        ASTWithSource: struct { ast: *const AstNode },
    };

    /// Convenience constructor for an Empty node.
    pub fn emptyExpr(span: ParseSpan, abs: AbsoluteSourceSpan) AstNode {
        return .{ .span = span, .source_span = abs, .data = .{ .Empty = {} } };
    }

    /// Convenience constructor for a LiteralPrimitive string.
    pub fn literalString(span: ParseSpan, abs: AbsoluteSourceSpan, s: []const u8) AstNode {
        return .{
            .span = span,
            .source_span = abs,
            .data = .{ .LiteralPrimitive = .{ .value = .{ .String = s } } },
        };
    }

    /// Convenience constructor for a LiteralPrimitive number.
    pub fn literalNumber(span: ParseSpan, abs: AbsoluteSourceSpan, n: f64) AstNode {
        return .{
            .span = span,
            .source_span = abs,
            .data = .{ .LiteralPrimitive = .{ .value = .{ .Number = n } } },
        };
    }

    /// Convenience constructor for an ImplicitReceiver.
    pub fn implicitReceiver(span: ParseSpan, abs: AbsoluteSourceSpan) AstNode {
        return .{ .span = span, .source_span = abs, .data = .{ .ImplicitReceiver = {} } };
    }

    /// Convenience constructor for a ThisReceiver.
    pub fn thisReceiver(span: ParseSpan, abs: AbsoluteSourceSpan) AstNode {
        return .{ .span = span, .source_span = abs, .data = .{ .ThisReceiver = {} } };
    }
};

// ─── TcbExpr ───────────────────────────────────────────────

/// TcbExpr — a type-check expression result.
///
/// Direct port of the `TcbExpr` class in `ops/codegen.ts`. The struct
/// owns a heap-allocated string (`expr`) plus a few flags used to drive
/// downstream codegen. Methods chain by returning a new TcbExpr.
pub const TcbExpr = struct {
    allocator: std.mem.Allocator,
    expr: []const u8,
    /// Whether the expression has been wrapped in parens for the type checker.
    wrapped: bool = false,
    /// Whether to ignore diagnostics on this expression.
    ignore_diagnostics: bool = false,
    /// Optional parse span info suffix (e.g. `/*0,5*/`).
    parse_span_info: ?[]const u8 = null,

    /// Construct a new TcbExpr from a raw expression string. The string
    /// is dup'd so callers retain ownership of their input.
    pub fn init(allocator: std.mem.Allocator, expr: []const u8) !TcbExpr {
        const owned = try allocator.dupe(u8, expr);
        return .{ .allocator = allocator, .expr = owned };
    }

    /// Construct a new TcbExpr taking ownership of an already-allocated
    /// string (no dup). Caller must not free `expr` afterwards.
    pub fn initOwned(allocator: std.mem.Allocator, expr: []const u8) TcbExpr {
        return .{ .allocator = allocator, .expr = expr };
    }

    /// Free the owned strings.
    pub fn deinit(self: *const TcbExpr) void {
        self.allocator.free(self.expr);
        if (self.parse_span_info) |s| self.allocator.free(s);
    }

    /// Print the expression, including any parse span info suffix.
    /// Direct port of `TcbExpr.print()` in the TS source.
    pub fn print(self: TcbExpr) ![]const u8 {
        if (self.parse_span_info) |info| {
            return std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.expr, info });
        }
        return self.allocator.dupe(u8, self.expr);
    }

    /// Mark this expression as wrapped for the type checker (chainable).
    /// Direct port of `TcbExpr.wrapForTypeChecker()` in the TS source.
    pub fn wrapForTypeChecker(self: TcbExpr) TcbExpr {
        var copy = self;
        copy.wrapped = true;
        return copy;
    }

    /// Mark this expression to ignore diagnostics (chainable).
    /// Direct port of `TcbExpr.markIgnoreDiagnostics()` in the TS source.
    pub fn markIgnoreDiagnostics(self: TcbExpr) TcbExpr {
        var copy = self;
        copy.ignore_diagnostics = true;
        return copy;
    }

    /// Attach parse span info to this expression (chainable).
    /// Direct port of `TcbExpr.addParseSpanInfo(span)` in the TS source.
    pub fn addParseSpanInfo(self: TcbExpr, span: ParseSpan) !TcbExpr {
        var copy = self;
        const info = try std.fmt.allocPrint(self.allocator, "/*{d},{d}*/", .{ span.start, span.end });
        copy.parse_span_info = info;
        return copy;
    }

    /// Attach an AbsoluteSourceSpan as parse span info (chainable).
    pub fn addAbsoluteParseSpanInfo(self: TcbExpr, span: AbsoluteSourceSpan) !TcbExpr {
        var copy = self;
        const info = try std.fmt.allocPrint(self.allocator, "/*{d},{d}*/", .{ span.start, span.end });
        copy.parse_span_info = info;
        return copy;
    }

    /// Quote-and-escape a string literal for use in a TCB expression.
    /// Direct port of the static `TcbExpr.quoteAndEscape(input)` method.
    pub fn quoteAndEscape(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
        var buf = std.array_list.Managed(u8).init(allocator);
        errdefer buf.deinit();
        try buf.append('\'');
        for (input) |c| {
            switch (c) {
                '\'' => try buf.appendSlice("\\'"),
                '\\' => try buf.appendSlice("\\\\"),
                '\n' => try buf.appendSlice("\\n"),
                '\r' => try buf.appendSlice("\\r"),
                else => try buf.append(c),
            }
        }
        try buf.append('\'');
        return buf.toOwnedSlice();
    }
};

// ─── MaybeResolve callback ─────────────────────────────────

/// MaybeResolveFn — callback used to resolve an AST node to a TcbExpr.
/// Direct port of the `maybeResolve: (ast: AST) => TcbExpr | null` callback.
pub const MaybeResolveFn = *const fn (ast: *const AstNode) ?TcbExpr;

// ─── TcbExprTranslator ─────────────────────────────────────

/// TcbExprTranslator — translates AST expressions into TCB expressions.
///
/// Direct port of `TcbExprTranslator` class in the TS source. Implements
/// the AstVisitor pattern via a switch on `AstNode.data`. Each visit
/// method returns a fresh `TcbExpr`.
pub const TcbExprTranslator = struct {
    allocator: std.mem.Allocator,
    maybe_resolve: ?MaybeResolveFn,
    config: TypeCheckingConfig,

    pub fn init(
        allocator: std.mem.Allocator,
        maybe_resolve: ?MaybeResolveFn,
        config: TypeCheckingConfig,
    ) TcbExprTranslator {
        return .{
            .allocator = allocator,
            .maybe_resolve = maybe_resolve,
            .config = config,
        };
    }

    /// Translate an AST expression into a TCB expression.
    /// Direct port of `translate(ast)` method in the TS source.
    pub fn translate(self: *const TcbExprTranslator, ast: *const AstNode) anyerror!TcbExpr {
        // Unwrap ASTWithSource wrapper if present.
        const unwrapped: *const AstNode = switch (ast.data) {
            .ASTWithSource => |aws| aws.ast,
            else => ast,
        };

        // First, allow custom resolution logic to provide a translation.
        if (self.maybe_resolve) |resolve| {
            if (resolve(unwrapped)) |resolved| {
                return resolved;
            }
        }

        // Otherwise, dispatch to the appropriate visit method.
        return self.dispatch(unwrapped);
    }

    /// Dispatch to the appropriate visit method based on the AST kind.
    fn dispatch(self: *const TcbExprTranslator, ast: *const AstNode) anyerror!TcbExpr {
        return switch (ast.data) {
            .Empty => self.visitEmptyExpr(ast),
            .ImplicitReceiver => error.MethodNotImplemented,
            .ThisReceiver => error.MethodNotImplemented,
            .Chain => |c| self.visitChain(ast, c.expressions),
            .Conditional => |c| self.visitConditional(ast, c.condition, c.true_exp, c.false_exp),
            .PropertyRead => |pr| self.visitPropertyRead(ast, pr.receiver, pr.name),
            .SafePropertyRead => |spr| self.visitSafePropertyRead(ast, spr.receiver, spr.name),
            .KeyedRead => |kr| self.visitKeyedRead(ast, kr.receiver, kr.key),
            .SafeKeyedRead => |skr| self.visitSafeKeyedRead(ast, skr.receiver, skr.key),
            .BindingPipe => error.MethodNotImplemented,
            .LiteralPrimitive => |lp| self.visitLiteralPrimitive(ast, lp.value),
            .LiteralArray => |la| self.visitLiteralArray(ast, la.expressions),
            .LiteralMap => |lm| self.visitLiteralMap(ast, lm.keys, lm.values),
            .SpreadElement => |se| self.visitSpreadElement(ast, se.expression),
            .Interpolation => |i| self.visitInterpolation(ast, i.expressions),
            .Binary => |b| self.visitBinary(ast, b.operation, b.left, b.right),
            .Unary => |u| self.visitUnary(ast, u.operator, u.expr),
            .PrefixNot => |pn| self.visitPrefixNot(ast, pn.expression),
            .TypeofExpr => |te| self.visitTypeofExpression(ast, te.expression),
            .VoidExpr => |ve| self.visitVoidExpression(ast, ve.expression),
            .NonNullAssert => |nna| self.visitNonNullAssert(ast, nna.expression),
            .Call => |c| self.visitCall(ast, c.receiver, c.args),
            .SafeCall => |sc| self.visitSafeCall(ast, sc.receiver, sc.args),
            .TaggedTemplate => |tt| self.visitTaggedTemplateLiteral(ast, tt.tag, tt.template),
            .TemplateLiteral => |tl| self.visitTemplateLiteral(tl),
            .Parenthesized => |p| self.visitParenthesizedExpression(ast, p.expression),
            .ArrowFunction => |af| self.visitArrowFunction(ast, af.parameters, af.body),
            .RegexLiteral => |rl| self.visitRegularExpressionLiteral(ast, rl.body, rl.flags),
            .ASTWithSource => unreachable, // handled in `translate`
        };
    }

    /// visitUnary — `+expr` or `-expr`.
    pub fn visitUnary(
        self: *const TcbExprTranslator,
        ast: *const AstNode,
        operator: UnaryOperator,
        expr: *const AstNode,
    ) anyerror!TcbExpr {
        const sub = try self.translate(expr);
        defer sub.deinit();
        const printed = try sub.print();
        defer self.allocator.free(printed);
        const s = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ operator.symbol(), printed });
        var node = TcbExpr.initOwned(self.allocator, s).wrapForTypeChecker();
        node = try node.addParseSpanInfo(ast.source_span.toSpan());
        return node;
    }

    /// visitBinary — `lhs op rhs`.
    pub fn visitBinary(
        self: *const TcbExprTranslator,
        ast: *const AstNode,
        operation: BinaryOp,
        left: *const AstNode,
        right: *const AstNode,
    ) anyerror!TcbExpr {
        const lhs = try self.translate(left);
        defer lhs.deinit();
        const rhs = try self.translate(right);
        defer rhs.deinit();
        const lhs_printed = try lhs.print();
        defer self.allocator.free(lhs_printed);
        const rhs_printed = try rhs.print();
        defer self.allocator.free(rhs_printed);
        const op_str = operation.symbol();
        const expression = try std.fmt.allocPrint(
            self.allocator,
            "{s} {s} {s}",
            .{ lhs_printed, op_str, rhs_printed },
        );
        defer self.allocator.free(expression);
        const s = if (operation == .Nullish or operation == .Exponent)
            try std.fmt.allocPrint(self.allocator, "({s})", .{expression})
        else
            try self.allocator.dupe(u8, expression);
        var node = TcbExpr.initOwned(self.allocator, s);
        node = try node.addParseSpanInfo(ast.source_span.toSpan());
        return node;
    }

    /// visitChain — `(e1, e2, e3)`.
    pub fn visitChain(
        self: *const TcbExprTranslator,
        ast: *const AstNode,
        expressions: []const *const AstNode,
    ) anyerror!TcbExpr {
        var parts = std.array_list.Managed([]const u8).init(self.allocator);
        defer {
            for (parts.items) |p| self.allocator.free(p);
            parts.deinit();
        }
        for (expressions) |expr| {
            const node = try self.translate(expr);
            defer node.deinit();
            const printed = try node.print();
            try parts.append(printed);
        }
        const joined = try std.mem.join(self.allocator, ", ", parts.items);
        var node = TcbExpr.initOwned(self.allocator, joined);
        node = node.wrapForTypeChecker();
        node = try node.addParseSpanInfo(ast.source_span.toSpan());
        return node;
    }

    /// visitConditional — `(cond ? trueExp : falseExp)`.
    pub fn visitConditional(
        self: *const TcbExprTranslator,
        ast: *const AstNode,
        condition: *const AstNode,
        true_exp: *const AstNode,
        false_exp: *const AstNode,
    ) anyerror!TcbExpr {
        const cond = try self.translate(condition);
        defer cond.deinit();
        const t = try self.translate(true_exp);
        defer t.deinit();
        const f = (try self.translate(false_exp)).wrapForTypeChecker();
        defer f.deinit();
        const cond_p = try cond.print();
        defer self.allocator.free(cond_p);
        const t_p = try t.print();
        defer self.allocator.free(t_p);
        const f_p = try f.print();
        defer self.allocator.free(f_p);
        const s = try std.fmt.allocPrint(
            self.allocator,
            "({s} ? {s} : {s})",
            .{ cond_p, t_p, f_p },
        );
        return (TcbExpr.initOwned(self.allocator, s)).addParseSpanInfo(ast.source_span.toSpan());
    }

    /// visitRegularExpressionLiteral — `/body/flags`.
    pub fn visitRegularExpressionLiteral(
        self: *const TcbExprTranslator,
        ast: *const AstNode,
        body: []const u8,
        flags: ?[]const u8,
    ) anyerror!TcbExpr {
        _ = ast;
        const flags_str = flags orelse "";
        const s = try std.fmt.allocPrint(self.allocator, "/{s}/{s}", .{ body, flags_str });
        var node = TcbExpr.initOwned(self.allocator, s);
        node = node.wrapForTypeChecker();
        return node;
    }

    /// visitInterpolation — `"" + e1 + e2 + ...`.
    pub fn visitInterpolation(
        self: *const TcbExprTranslator,
        ast: *const AstNode,
        expressions: []const *const AstNode,
    ) anyerror!TcbExpr {
        _ = ast;
        var parts = std.array_list.Managed([]const u8).init(self.allocator);
        defer {
            for (parts.items) |p| self.allocator.free(p);
            parts.deinit();
        }
        for (expressions) |expr| {
            const node = try self.translate(expr);
            defer node.deinit();
            const wrapped = node.wrapForTypeChecker();
            const printed = try wrapped.print();
            try parts.append(printed);
        }
        const joined = try std.mem.join(self.allocator, " + ", parts.items);
        const s = try std.fmt.allocPrint(self.allocator, "\"\" + {s}", .{joined});
        return TcbExpr.initOwned(self.allocator, s);
    }

    /// visitKeyedRead — `receiver[key]`.
    pub fn visitKeyedRead(
        self: *const TcbExprTranslator,
        ast: *const AstNode,
        receiver: *const AstNode,
        key: *const AstNode,
    ) anyerror!TcbExpr {
        const recv = (try self.translate(receiver)).wrapForTypeChecker();
        defer recv.deinit();
        const k = try self.translate(key);
        defer k.deinit();
        const r_p = try recv.print();
        defer self.allocator.free(r_p);
        const k_p = try k.print();
        defer self.allocator.free(k_p);
        const s = try std.fmt.allocPrint(self.allocator, "{s}[{s}]", .{ r_p, k_p });
        return (TcbExpr.initOwned(self.allocator, s)).addParseSpanInfo(ast.source_span.toSpan());
    }

    /// visitLiteralArray — `[e1, e2, ...]`.
    pub fn visitLiteralArray(
        self: *const TcbExprTranslator,
        ast: *const AstNode,
        expressions: []const *const AstNode,
    ) anyerror!TcbExpr {
        var parts = std.array_list.Managed([]const u8).init(self.allocator);
        defer {
            for (parts.items) |p| self.allocator.free(p);
            parts.deinit();
        }
        for (expressions) |expr| {
            const node = try self.translate(expr);
            defer node.deinit();
            const printed = try node.print();
            try parts.append(printed);
        }
        const joined = try std.mem.join(self.allocator, ", ", parts.items);
        const literal = try std.fmt.allocPrint(self.allocator, "[{s}]", .{joined});
        defer self.allocator.free(literal);
        const s = if (!self.config.strict_literal_types)
            try std.fmt.allocPrint(self.allocator, "({s} as any)", .{literal})
        else
            try self.allocator.dupe(u8, literal);
        return (TcbExpr.initOwned(self.allocator, s)).addParseSpanInfo(ast.source_span.toSpan());
    }

    /// visitLiteralMap — `{ key: value, ...spread }`.
    pub fn visitLiteralMap(
        self: *const TcbExprTranslator,
        ast: *const AstNode,
        keys: []const LiteralMapKey,
        values: []const *const AstNode,
    ) anyerror!TcbExpr {
        var parts = std.array_list.Managed([]const u8).init(self.allocator);
        defer {
            for (parts.items) |p| self.allocator.free(p);
            parts.deinit();
        }
        for (keys, 0..) |key, idx| {
            const value = try self.translate(values[idx]);
            defer value.deinit();
            const value_printed = try value.print();
            defer self.allocator.free(value_printed);
            const part = switch (key.kind) {
                .property => blk: {
                    const quoted = try TcbExpr.quoteAndEscape(self.allocator, key.key);
                    defer self.allocator.free(quoted);
                    break :blk try std.fmt.allocPrint(self.allocator, "{s}: {s}", .{ quoted, value_printed });
                },
                .spread => try std.fmt.allocPrint(self.allocator, "...{s}", .{value_printed}),
            };
            try parts.append(part);
        }
        const joined = try std.mem.join(self.allocator, ", ", parts.items);
        const literal = try std.fmt.allocPrint(self.allocator, "{{ {s} }}", .{joined});
        defer self.allocator.free(literal);
        const s = if (!self.config.strict_literal_types)
            try std.fmt.allocPrint(self.allocator, "{s} as any", .{literal})
        else
            try self.allocator.dupe(u8, literal);
        var expr = TcbExpr.initOwned(self.allocator, s);
        expr = try expr.addParseSpanInfo(ast.source_span.toSpan());
        expr = expr.wrapForTypeChecker();
        return expr;
    }

    /// visitLiteralPrimitive — `undefined`/`null`/string/number/boolean.
    pub fn visitLiteralPrimitive(
        self: *const TcbExprTranslator,
        ast: *const AstNode,
        value: LiteralValue,
    ) anyerror!TcbExpr {
        const s = switch (value) {
            .Undefined => try self.allocator.dupe(u8, "undefined"),
            .Null => try self.allocator.dupe(u8, "null"),
            .String => |str| try TcbExpr.quoteAndEscape(self.allocator, str),
            .Number => |n| blk: {
                if (std.math.isNan(n)) {
                    break :blk try self.allocator.dupe(u8, "NaN");
                } else if (!std.math.isFinite(n)) {
                    break :blk try self.allocator.dupe(u8, if (n > 0) "Infinity" else "-Infinity");
                } else {
                    break :blk try std.fmt.allocPrint(self.allocator, "{d}", .{n});
                }
            },
            .Boolean => |b| try self.allocator.dupe(u8, if (b) "true" else "false"),
        };
        return (TcbExpr.initOwned(self.allocator, s)).addParseSpanInfo(ast.source_span.toSpan());
    }

    /// visitNonNullAssert — `expr!`.
    pub fn visitNonNullAssert(
        self: *const TcbExprTranslator,
        ast: *const AstNode,
        expression: *const AstNode,
    ) anyerror!TcbExpr {
        const expr = (try self.translate(expression)).wrapForTypeChecker();
        defer expr.deinit();
        const p = try expr.print();
        defer self.allocator.free(p);
        const s = try std.fmt.allocPrint(self.allocator, "{s}!", .{p});
        return (TcbExpr.initOwned(self.allocator, s)).addParseSpanInfo(ast.source_span.toSpan());
    }

    /// visitPrefixNot — `!expr`.
    pub fn visitPrefixNot(
        self: *const TcbExprTranslator,
        ast: *const AstNode,
        expression: *const AstNode,
    ) anyerror!TcbExpr {
        const expr = (try self.translate(expression)).wrapForTypeChecker();
        defer expr.deinit();
        const p = try expr.print();
        defer self.allocator.free(p);
        const s = try std.fmt.allocPrint(self.allocator, "!{s}", .{p});
        return (TcbExpr.initOwned(self.allocator, s)).addParseSpanInfo(ast.source_span.toSpan());
    }

    /// visitTypeofExpression — `typeof expr`.
    pub fn visitTypeofExpression(
        self: *const TcbExprTranslator,
        ast: *const AstNode,
        expression: *const AstNode,
    ) anyerror!TcbExpr {
        const expr = (try self.translate(expression)).wrapForTypeChecker();
        defer expr.deinit();
        const p = try expr.print();
        defer self.allocator.free(p);
        const s = try std.fmt.allocPrint(self.allocator, "typeof {s}", .{p});
        return (TcbExpr.initOwned(self.allocator, s)).addParseSpanInfo(ast.source_span.toSpan());
    }

    /// visitVoidExpression — `void expr`.
    pub fn visitVoidExpression(
        self: *const TcbExprTranslator,
        ast: *const AstNode,
        expression: *const AstNode,
    ) anyerror!TcbExpr {
        const expr = (try self.translate(expression)).wrapForTypeChecker();
        defer expr.deinit();
        const p = try expr.print();
        defer self.allocator.free(p);
        const s = try std.fmt.allocPrint(self.allocator, "void {s}", .{p});
        return (TcbExpr.initOwned(self.allocator, s)).addParseSpanInfo(ast.source_span.toSpan());
    }

    /// visitPropertyRead — `receiver.name`.
    pub fn visitPropertyRead(
        self: *const TcbExprTranslator,
        ast: *const AstNode,
        receiver: *const AstNode,
        name: []const u8,
    ) anyerror!TcbExpr {
        const recv = (try self.translate(receiver)).wrapForTypeChecker();
        defer recv.deinit();
        const r_p = try recv.print();
        defer self.allocator.free(r_p);
        const s = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ r_p, name });
        var node = TcbExpr.initOwned(self.allocator, s);
        if (ast.name_span) |ns| {
            node = try node.addAbsoluteParseSpanInfo(ns);
        }
        node = node.wrapForTypeChecker();
        node = try node.addParseSpanInfo(ast.source_span.toSpan());
        return node;
    }

    /// visitSafePropertyRead — `receiver?.name` or fallback per config.
    pub fn visitSafePropertyRead(
        self: *const TcbExprTranslator,
        ast: *const AstNode,
        receiver: *const AstNode,
        name: []const u8,
    ) anyerror!TcbExpr {
        const recv = (try self.translate(receiver)).wrapForTypeChecker();
        defer recv.deinit();
        const r_p = try recv.print();
        defer self.allocator.free(r_p);
        const name_node = blk: {
            var n = try TcbExpr.init(self.allocator, name);
            if (ast.name_span) |ns| {
                n = try n.addAbsoluteParseSpanInfo(ns);
            }
            break :blk n;
        };
        defer name_node.deinit();
        const name_printed = try name_node.print();
        defer self.allocator.free(name_printed);

        const s = if (self.config.strict_safe_navigation_types)
            try std.fmt.allocPrint(self.allocator, "{s}?.{s}", .{ r_p, name_printed })
        else if (try VeSafeLhsInferenceBugDetector.veWillInferAnyFor(ast))
            try std.fmt.allocPrint(self.allocator, "({s} as any).{s}", .{ r_p, name_printed })
        else
            try std.fmt.allocPrint(self.allocator, "({s}!.{s} as any)", .{ r_p, name_printed });
        return (TcbExpr.initOwned(self.allocator, s)).addParseSpanInfo(ast.source_span.toSpan());
    }

    /// visitSafeKeyedRead — `receiver?.[key]` or fallback per config.
    pub fn visitSafeKeyedRead(
        self: *const TcbExprTranslator,
        ast: *const AstNode,
        receiver: *const AstNode,
        key: *const AstNode,
    ) anyerror!TcbExpr {
        const recv = (try self.translate(receiver)).wrapForTypeChecker();
        defer recv.deinit();
        const k = try self.translate(key);
        defer k.deinit();
        const r_p = try recv.print();
        defer self.allocator.free(r_p);
        const k_p = try k.print();
        defer self.allocator.free(k_p);

        const s = if (self.config.strict_safe_navigation_types)
            try std.fmt.allocPrint(self.allocator, "{s}?.[{s}]", .{ r_p, k_p })
        else if (try VeSafeLhsInferenceBugDetector.veWillInferAnyFor(ast))
            try std.fmt.allocPrint(self.allocator, "({s} as any)[{s}]", .{ r_p, k_p })
        else blk: {
            const element_access = try std.fmt.allocPrint(self.allocator, "{s}![{s}]", .{ r_p, k_p });
            defer self.allocator.free(element_access);
            break :blk try std.fmt.allocPrint(self.allocator, "({s} as any)", .{element_access});
        };
        return (TcbExpr.initOwned(self.allocator, s)).addParseSpanInfo(ast.source_span.toSpan());
    }

    /// visitCall — `expr(arg1, arg2, ...)`.
    pub fn visitCall(
        self: *const TcbExprTranslator,
        ast: *const AstNode,
        receiver: *const AstNode,
        args: []const *const AstNode,
    ) anyerror!TcbExpr {
        var arg_nodes = std.array_list.Managed(TcbExpr).init(self.allocator);
        defer {
            for (arg_nodes.items) |*n| n.deinit();
            arg_nodes.deinit();
        }
        for (args) |arg| {
            const node = try self.translate(arg);
            try arg_nodes.append(node);
        }

        // Determine the receiver expression.
        var expr: TcbExpr = switch (receiver.data) {
            .PropertyRead => |pr| blk: {
                // First, allow custom resolution.
                if (self.maybe_resolve) |resolve| {
                    if (resolve(receiver)) |resolved| break :blk resolved;
                }
                const property_receiver = (try self.translate(pr.receiver)).wrapForTypeChecker();
                defer property_receiver.deinit();
                const p_p = try property_receiver.print();
                defer self.allocator.free(p_p);
                const s = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ p_p, pr.name });
                var node = TcbExpr.initOwned(self.allocator, s);
                if (receiver.name_span) |ns| {
                    node = try node.addAbsoluteParseSpanInfo(ns);
                }
                break :blk node;
            },
            else => try self.translate(receiver),
        };

        var arg_parts = std.array_list.Managed([]const u8).init(self.allocator);
        defer {
            for (arg_parts.items) |p| self.allocator.free(p);
            arg_parts.deinit();
        }
        for (arg_nodes.items) |n| {
            const p = try n.print();
            try arg_parts.append(p);
        }
        const args_joined = try std.mem.join(self.allocator, ", ", arg_parts.items);
        defer self.allocator.free(args_joined);

        const expr_printed = try expr.print();
        defer self.allocator.free(expr_printed);

        const is_safe = switch (receiver.data) {
            .SafePropertyRead, .SafeKeyedRead => true,
            else => false,
        };

        const s = if (is_safe)
            try self.convertToSafeCall(ast, expr_printed, args_joined)
        else
            try std.fmt.allocPrint(self.allocator, "{s}({s})", .{ expr_printed, args_joined });
        expr.deinit();
        return (TcbExpr.initOwned(self.allocator, s)).addParseSpanInfo(ast.source_span.toSpan());
    }

    /// visitSafeCall — `receiver?.(args)` or fallback per config.
    pub fn visitSafeCall(
        self: *const TcbExprTranslator,
        ast: *const AstNode,
        receiver: *const AstNode,
        args: []const *const AstNode,
    ) anyerror!TcbExpr {
        var arg_nodes = std.array_list.Managed(TcbExpr).init(self.allocator);
        defer {
            for (arg_nodes.items) |*n| n.deinit();
            arg_nodes.deinit();
        }
        for (args) |arg| {
            try arg_nodes.append(try self.translate(arg));
        }
        const expr = (try self.translate(receiver)).wrapForTypeChecker();
        defer expr.deinit();
        const expr_p = try expr.print();
        defer self.allocator.free(expr_p);

        var arg_parts = std.array_list.Managed([]const u8).init(self.allocator);
        defer {
            for (arg_parts.items) |p| self.allocator.free(p);
            arg_parts.deinit();
        }
        for (arg_nodes.items) |n| {
            const p = try n.print();
            try arg_parts.append(p);
        }
        const args_joined = try std.mem.join(self.allocator, ", ", arg_parts.items);
        defer self.allocator.free(args_joined);

        const s = try self.convertToSafeCall(ast, expr_p, args_joined);
        return (TcbExpr.initOwned(self.allocator, s)).addParseSpanInfo(ast.source_span.toSpan());
    }

    /// visitTemplateLiteral — `` `head${expr}tail` ``.
    pub fn visitTemplateLiteral(self: *const TcbExprTranslator, tl: TemplateLiteralData) anyerror!TcbExpr {
        const length = tl.elements.len;
        const head = tl.elements[0];
        if (length == 1) {
            const escaped = try self.escapeTemplateLiteral(head);
            defer self.allocator.free(escaped);
            const s = try std.fmt.allocPrint(self.allocator, "`{s}`", .{escaped});
            return TcbExpr.initOwned(self.allocator, s);
        }

        var parts = std.array_list.Managed([]const u8).init(self.allocator);
        defer {
            for (parts.items) |p| self.allocator.free(p);
            parts.deinit();
        }

        const head_escaped = try self.escapeTemplateLiteral(head);
        const head_part = try std.fmt.allocPrint(self.allocator, "`{s}", .{head_escaped});
        try parts.append(head_part);
        self.allocator.free(head_escaped);

        const tail_index = length - 1;
        var i: usize = 1;
        while (i < tail_index) : (i += 1) {
            const expr_node = try self.translate(tl.expressions[i - 1]);
            defer expr_node.deinit();
            const expr_p = try expr_node.print();
            defer self.allocator.free(expr_p);
            const element_escaped = try self.escapeTemplateLiteral(tl.elements[i]);
            defer self.allocator.free(element_escaped);
            const part = try std.fmt.allocPrint(self.allocator, "${{{s}}}{s}", .{ expr_p, element_escaped });
            try parts.append(part);
        }

        const resolved = try self.translate(tl.expressions[tail_index - 1]);
        defer resolved.deinit();
        const resolved_p = try resolved.print();
        defer self.allocator.free(resolved_p);
        const tail_escaped = try self.escapeTemplateLiteral(tl.elements[tail_index]);
        defer self.allocator.free(tail_escaped);
        const tail_part = try std.fmt.allocPrint(self.allocator, "${{{s}}}{s}`", .{ resolved_p, tail_escaped });
        try parts.append(tail_part);

        const joined = try std.mem.join(self.allocator, "", parts.items);
        return TcbExpr.initOwned(self.allocator, joined);
    }

    /// visitTaggedTemplateLiteral — `tag\`template\``.
    pub fn visitTaggedTemplateLiteral(
        self: *const TcbExprTranslator,
        ast: *const AstNode,
        tag: *const AstNode,
        template: TemplateLiteralData,
    ) anyerror!TcbExpr {
        _ = ast;
        const tag_node = try self.translate(tag);
        defer tag_node.deinit();
        const tmpl_node = try self.visitTemplateLiteral(template);
        defer tmpl_node.deinit();
        const t_p = try tag_node.print();
        defer self.allocator.free(t_p);
        const tm_p = try tmpl_node.print();
        defer self.allocator.free(tm_p);
        const s = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ t_p, tm_p });
        return TcbExpr.initOwned(self.allocator, s);
    }

    /// visitParenthesizedExpression — `(expr)`.
    pub fn visitParenthesizedExpression(
        self: *const TcbExprTranslator,
        ast: *const AstNode,
        expression: *const AstNode,
    ) anyerror!TcbExpr {
        _ = ast;
        const expr = try self.translate(expression);
        defer expr.deinit();
        const p = try expr.print();
        defer self.allocator.free(p);
        const s = try std.fmt.allocPrint(self.allocator, "({s})", .{p});
        return TcbExpr.initOwned(self.allocator, s);
    }

    /// visitSpreadElement — `...expr`.
    pub fn visitSpreadElement(
        self: *const TcbExprTranslator,
        ast: *const AstNode,
        expression: *const AstNode,
    ) anyerror!TcbExpr {
        const expr = try self.translate(expression);
        var wrapped = expr.wrapForTypeChecker();
        const p = try wrapped.print();
        defer self.allocator.free(p);
        const s = try std.fmt.allocPrint(self.allocator, "...{s}", .{p});
        var node = TcbExpr.initOwned(self.allocator, s);
        node = try node.addParseSpanInfo(ast.source_span.toSpan());
        wrapped.deinit();
        return node;
    }

    /// visitEmptyExpr — `undefined`.
    pub fn visitEmptyExpr(self: *const TcbExprTranslator, ast: *const AstNode) anyerror!TcbExpr {
        var node = try TcbExpr.init(self.allocator, "undefined");
        node = try node.addParseSpanInfo(ast.source_span.toSpan());
        return node;
    }

    /// visitArrowFunction — `(p1, p2) => body`.
    pub fn visitArrowFunction(
        self: *const TcbExprTranslator,
        ast: *const AstNode,
        parameters: []const ArrowParam,
        body: *const AstNode,
    ) anyerror!TcbExpr {
        _ = ast;
        // Build parameter list — each param is marked ignore-diagnostics.
        var param_parts = std.array_list.Managed([]const u8).init(self.allocator);
        defer {
            for (param_parts.items) |p| self.allocator.free(p);
            param_parts.deinit();
        }
        for (parameters) |param| {
            var node = try TcbExpr.init(self.allocator, param.name);
            node = node.markIgnoreDiagnostics();
            defer node.deinit();
            const printed = try node.print();
            try param_parts.append(printed);
        }
        const params_joined = try std.mem.join(self.allocator, ", ", param_parts.items);
        defer self.allocator.free(params_joined);

        // Translate the body using the outer translator. In the TS source the
        // translator is re-entered via `astToTcbExpr` so that PropertyRead
        // nodes matching arrow parameters get resolved to the parameter name
        // directly. Here we use the same outer `maybe_resolve` callback for
        // simplicity.
        const body_node = try self.translate(body);
        defer body_node.deinit();
        const body_p = try body_node.print();
        defer self.allocator.free(body_p);

        const params_str = if (parameters.len == 1)
            try self.allocator.dupe(u8, params_joined)
        else
            try std.fmt.allocPrint(self.allocator, "({s})", .{params_joined});
        defer self.allocator.free(params_str);

        const s = try std.fmt.allocPrint(self.allocator, "{s} => {s}", .{ params_str, body_p });
        return TcbExpr.initOwned(self.allocator, s);
    }

    /// convertToSafeCall — emit a safe-call expression per config.
    fn convertToSafeCall(
        self: *const TcbExprTranslator,
        ast: *const AstNode,
        expr: []const u8,
        args: []const u8,
    ) anyerror![]const u8 {
        if (self.config.strict_safe_navigation_types) {
            return std.fmt.allocPrint(self.allocator, "({s}?.({s}))", .{ expr, args });
        }
        if (try VeSafeLhsInferenceBugDetector.veWillInferAnyFor(ast)) {
            return std.fmt.allocPrint(self.allocator, "({s} as any)({s})", .{ expr, args });
        }
        return std.fmt.allocPrint(self.allocator, "({s}!({s}) as any)", .{ expr, args });
    }

    /// escapeTemplateLiteral — escape `\`, `` ` ``, and `${` for template literals.
    fn escapeTemplateLiteral(self: *const TcbExprTranslator, value: []const u8) anyerror![]const u8 {
        var buf = std.array_list.Managed(u8).init(self.allocator);
        errdefer buf.deinit();
        var i: usize = 0;
        while (i < value.len) : (i += 1) {
            const c = value[i];
            if (c == '\\') {
                try buf.appendSlice("\\\\");
            } else if (c == '`') {
                try buf.appendSlice("\\`");
            } else if (c == '$' and i + 1 < value.len and value[i + 1] == '{') {
                try buf.appendSlice("$\\{");
                i += 1; // skip the '{'
            } else {
                try buf.append(c);
            }
        }
        return buf.toOwnedSlice();
    }
};

// ─── Convenience helper: AbsoluteSourceSpan.toSpan() ───────

/// Extension: convert an AbsoluteSourceSpan into a ParseSpan.
/// (Used internally by translator methods to attach parse span info.)
pub fn absToSpan(abs: AbsoluteSourceSpan) ParseSpan {
    return .{ .start = abs.start, .end = abs.end };
}

// Provide a method-style helper on AbsoluteSourceSpan via a public function.
pub fn absSpanToParseSpan(abs: AbsoluteSourceSpan) ParseSpan {
    return absToSpan(abs);
}

// ─── astToTcbExpr ──────────────────────────────────────────

/// Convert an `AstNode` to a `TcbExpr` directly, without going through
/// an intermediate `Expression` AST.
/// Direct port of `astToTcbExpr(ast, maybeResolve, config)` in the TS source.
pub fn astToTcbExpr(
    allocator: std.mem.Allocator,
    ast: *const AstNode,
    maybe_resolve: ?MaybeResolveFn,
    config: TypeCheckingConfig,
) anyerror!TcbExpr {
    const translator = TcbExprTranslator.init(allocator, maybe_resolve, config);
    return translator.translate(ast);
}

// ─── VeSafeLhsInferenceBugDetector ─────────────────────────

/// VeSafeLhsInferenceBugDetector — detects when ViewEngine would infer
/// `any` for the LHS of a safe navigation. Mirrors the singleton visitor
/// in the TS source.
pub const VeSafeLhsInferenceBugDetector = struct {
    /// Determine if VE's safe-LHS inference bug would infer `any` for
    /// the given AST node (Call, SafeCall, SafePropertyRead, or SafeKeyedRead).
    pub fn veWillInferAnyFor(ast: *const AstNode) anyerror!bool {
        return switch (ast.data) {
            .Call => true,
            .SafeCall => false,
            .SafePropertyRead => |spr| try visitReceiver(spr.receiver),
            .SafeKeyedRead => |skr| try visitReceiver(skr.receiver),
            else => false,
        };
    }

    fn visitReceiver(ast: *const AstNode) anyerror!bool {
        return switch (ast.data) {
            .Unary => |u| try visit(u.expr),
            .Binary => |b| (try visit(b.left)) or (try visit(b.right)),
            .Chain => false,
            .Conditional => |c| (try visit(c.condition)) or (try visit(c.true_exp)) or (try visit(c.false_exp)),
            .Call => true,
            .SafeCall => false,
            .ImplicitReceiver => false,
            .ThisReceiver => false,
            .Interpolation => |i| blk: {
                for (i.expressions) |e| {
                    if (try visit(e)) break :blk true;
                }
                break :blk false;
            },
            .KeyedRead => false,
            .LiteralArray => true,
            .LiteralMap => true,
            .LiteralPrimitive => false,
            .BindingPipe => true,
            .PrefixNot => |pn| try visit(pn.expression),
            .TypeofExpr => |te| try visit(te.expression),
            .VoidExpr => |ve| try visit(ve.expression),
            .NonNullAssert => |nna| try visit(nna.expression),
            .PropertyRead => false,
            .SafePropertyRead => false,
            .SafeKeyedRead => false,
            .TemplateLiteral => false,
            .TaggedTemplate => false,
            .Parenthesized => |p| try visit(p.expression),
            .RegexLiteral => false,
            .SpreadElement => |s| try visit(s.expression),
            .ArrowFunction => false,
            .Empty => false,
            .ASTWithSource => |aws| try visitReceiver(aws.ast),
        };
    }

    /// Public recursive visit — used internally and exposed for tests.
    pub fn visit(ast: *const AstNode) anyerror!bool {
        return visitReceiver(ast);
    }
};

// ─── Convenience wrappers (kept from previous version) ─────

/// Convert a template AST expression into a TCB expression.
/// Direct port of `tcbExpression(ast, tcb, scope)` from the original Zig API.
pub fn tcbExpression(
    allocator: std.mem.Allocator,
    ast: *const AstNode,
    config: TypeCheckingConfig,
) anyerror!TcbExpr {
    return astToTcbExpr(allocator, ast, null, config);
}

/// Unwrap a writable signal expression.
/// Direct port of `unwrapWritableSignal(expr)` in the TS source.
pub fn unwrapWritableSignal(allocator: std.mem.Allocator, expr: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}.set", .{expr});
}

/// Add a non-null assertion to an expression.
pub fn nonNullAssert(allocator: std.mem.Allocator, expr: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}!", .{expr});
}

/// Wrap an expression in a safe navigation check.
pub fn safeNavigation(allocator: std.mem.Allocator, expr: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s} != null ? {s} : null", .{ expr, expr });
}

// ─── Extension: helper to attach a parse-span comment to a raw string ─

/// Attach a parse-span comment suffix to an expression string.
pub fn withParseSpanInfo(allocator: std.mem.Allocator, expr: []const u8, span: ParseSpan) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}/*{d},{d}*/", .{ expr, span.start, span.end });
}

// ─── Tests ─────────────────────────────────────────────────

test "TcbExpr.init and print" {
    const allocator = std.testing.allocator;
    var node = try TcbExpr.init(allocator, "hello");
    defer node.deinit();
    const printed = try node.print();
    defer allocator.free(printed);
    try std.testing.expectEqualStrings("hello", printed);
}

test "TcbExpr.addParseSpanInfo" {
    const allocator = std.testing.allocator;
    var node = try TcbExpr.init(allocator, "x");
    defer node.deinit();
    node = try node.addParseSpanInfo(.{ .start = 1, .end = 5 });
    const printed = try node.print();
    defer allocator.free(printed);
    try std.testing.expectEqualStrings("x/*1,5*/", printed);
}

test "TcbExpr.wrapForTypeChecker and markIgnoreDiagnostics" {
    const allocator = std.testing.allocator;
    var node = try TcbExpr.init(allocator, "y");
    defer node.deinit();
    node = node.wrapForTypeChecker();
    node = node.markIgnoreDiagnostics();
    try std.testing.expect(node.wrapped);
    try std.testing.expect(node.ignore_diagnostics);
}

test "TcbExpr.quoteAndEscape basic" {
    const allocator = std.testing.allocator;
    const s = try TcbExpr.quoteAndEscape(allocator, "hello");
    defer allocator.free(s);
    try std.testing.expectEqualStrings("'hello'", s);
}

test "TcbExpr.quoteAndEscape escapes quotes and backslashes" {
    const allocator = std.testing.allocator;
    const s = try TcbExpr.quoteAndEscape(allocator, "it's \\ back");
    defer allocator.free(s);
    try std.testing.expectEqualStrings("'it\\'s \\\\ back'", s);
}

test "TcbExpr.quoteAndEscape escapes newlines" {
    const allocator = std.testing.allocator;
    const s = try TcbExpr.quoteAndEscape(allocator, "line1\nline2");
    defer allocator.free(s);
    try std.testing.expectEqualStrings("'line1\\nline2'", s);
}

test "BinaryOp.symbol" {
    try std.testing.expectEqualStrings("+", BinaryOp.Plus.symbol());
    try std.testing.expectEqualStrings("??", BinaryOp.Nullish.symbol());
    try std.testing.expectEqualStrings("**", BinaryOp.Exponent.symbol());
    try std.testing.expectEqualStrings("&&", BinaryOp.And.symbol());
}

test "UnaryOperator.symbol" {
    try std.testing.expectEqualStrings("+", UnaryOperator.Plus.symbol());
    try std.testing.expectEqualStrings("-", UnaryOperator.Minus.symbol());
}

test "LiteralValue predicates" {
    const s: LiteralValue = .{ .String = "x" };
    const n: LiteralValue = .{ .Number = 1.0 };
    const b: LiteralValue = .{ .Boolean = true };
    try std.testing.expect(s.isString());
    try std.testing.expect(n.isNumber());
    try std.testing.expect(b.isBoolean());
}

test "visitLiteralPrimitive string" {
    const allocator = std.testing.allocator;
    const node = AstNode.literalString(.{ .start = 0, .end = 5 }, .{ .start = 0, .end = 5 }, "hello");
    var result = try astToTcbExpr(allocator, &node, null, .{});
    defer result.deinit();
    const printed = try result.print();
    defer allocator.free(printed);
    try std.testing.expectEqualStrings("'hello'/*0,5*/", printed);
}

test "visitLiteralPrimitive number" {
    const allocator = std.testing.allocator;
    const node = AstNode.literalNumber(.{ .start = 0, .end = 3 }, .{ .start = 0, .end = 3 }, 42.0);
    var result = try astToTcbExpr(allocator, &node, null, .{});
    defer result.deinit();
    const printed = try result.print();
    defer allocator.free(printed);
    try std.testing.expect(std.mem.indexOf(u8, printed, "42") != null);
}

test "visitLiteralPrimitive NaN" {
    const allocator = std.testing.allocator;
    const node = AstNode.literalNumber(.{ .start = 0, .end = 3 }, .{ .start = 0, .end = 3 }, std.math.nan(f64));
    var result = try astToTcbExpr(allocator, &node, null, .{});
    defer result.deinit();
    const printed = try result.print();
    defer allocator.free(printed);
    try std.testing.expect(std.mem.indexOf(u8, printed, "NaN") != null);
}

test "visitLiteralPrimitive Infinity" {
    const allocator = std.testing.allocator;
    const node = AstNode.literalNumber(.{ .start = 0, .end = 3 }, .{ .start = 0, .end = 3 }, std.math.inf(f64));
    var result = try astToTcbExpr(allocator, &node, null, .{});
    defer result.deinit();
    const printed = try result.print();
    defer allocator.free(printed);
    try std.testing.expect(std.mem.indexOf(u8, printed, "Infinity") != null);
}

test "visitLiteralPrimitive null and undefined" {
    const allocator = std.testing.allocator;
    const null_node = AstNode{
        .data = .{ .LiteralPrimitive = .{ .value = .Null } },
    };
    var result = try astToTcbExpr(allocator, &null_node, null, .{});
    defer result.deinit();
    const printed = try result.print();
    defer allocator.free(printed);
    try std.testing.expect(std.mem.indexOf(u8, printed, "null") != null);

    const undef_node = AstNode{
        .data = .{ .LiteralPrimitive = .{ .value = .Undefined } },
    };
    var result2 = try astToTcbExpr(allocator, &undef_node, null, .{});
    defer result2.deinit();
    const printed2 = try result2.print();
    defer allocator.free(printed2);
    try std.testing.expect(std.mem.indexOf(u8, printed2, "undefined") != null);
}

test "visitEmptyExpr returns undefined" {
    const allocator = std.testing.allocator;
    const node = AstNode.emptyExpr(.{ .start = 0, .end = 0 }, .{ .start = 0, .end = 0 });
    var result = try astToTcbExpr(allocator, &node, null, .{});
    defer result.deinit();
    const printed = try result.print();
    defer allocator.free(printed);
    try std.testing.expect(std.mem.indexOf(u8, printed, "undefined") != null);
}

test "visitParenthesizedExpression" {
    const allocator = std.testing.allocator;
    const inner = AstNode.literalNumber(.{ .start = 0, .end = 2 }, .{ .start = 0, .end = 2 }, 1.0);
    const node = AstNode{ .data = .{ .Parenthesized = .{ .expression = &inner } } };
    var result = try astToTcbExpr(allocator, &node, null, .{});
    defer result.deinit();
    const printed = try result.print();
    defer allocator.free(printed);
    try std.testing.expect(std.mem.startsWith(u8, printed, "(1"));
}

test "visitNonNullAssert" {
    const allocator = std.testing.allocator;
    const inner = AstNode.literalString(.{ .start = 0, .end = 1 }, .{ .start = 0, .end = 1 }, "x");
    const node = AstNode{ .data = .{ .NonNullAssert = .{ .expression = &inner } } };
    var result = try astToTcbExpr(allocator, &node, null, .{});
    defer result.deinit();
    const printed = try result.print();
    defer allocator.free(printed);
    try std.testing.expect(std.mem.indexOf(u8, printed, "!") != null);
}

test "visitPrefixNot" {
    const allocator = std.testing.allocator;
    const inner = AstNode.literalString(.{ .start = 0, .end = 1 }, .{ .start = 0, .end = 1 }, "x");
    const node = AstNode{ .data = .{ .PrefixNot = .{ .expression = &inner } } };
    var result = try astToTcbExpr(allocator, &node, null, .{});
    defer result.deinit();
    const printed = try result.print();
    defer allocator.free(printed);
    try std.testing.expect(std.mem.startsWith(u8, printed, "!"));
}

test "visitTypeofExpression" {
    const allocator = std.testing.allocator;
    const inner = AstNode.literalString(.{ .start = 0, .end = 1 }, .{ .start = 0, .end = 1 }, "x");
    const node = AstNode{ .data = .{ .TypeofExpr = .{ .expression = &inner } } };
    var result = try astToTcbExpr(allocator, &node, null, .{});
    defer result.deinit();
    const printed = try result.print();
    defer allocator.free(printed);
    try std.testing.expect(std.mem.indexOf(u8, printed, "typeof ") != null);
}

test "visitVoidExpression" {
    const allocator = std.testing.allocator;
    const inner = AstNode.literalString(.{ .start = 0, .end = 1 }, .{ .start = 0, .end = 1 }, "x");
    const node = AstNode{ .data = .{ .VoidExpr = .{ .expression = &inner } } };
    var result = try astToTcbExpr(allocator, &node, null, .{});
    defer result.deinit();
    const printed = try result.print();
    defer allocator.free(printed);
    try std.testing.expect(std.mem.indexOf(u8, printed, "void ") != null);
}

test "visitLiteralArray empty" {
    const allocator = std.testing.allocator;
    const node = AstNode{ .data = .{ .LiteralArray = .{ .expressions = &.{} } } };
    var result = try astToTcbExpr(allocator, &node, null, .{});
    defer result.deinit();
    const printed = try result.print();
    defer allocator.free(printed);
    try std.testing.expect(std.mem.indexOf(u8, printed, "[]") != null);
}

test "visitLiteralArray strict_literal_types does not cast to any" {
    const allocator = std.testing.allocator;
    const node = AstNode{ .data = .{ .LiteralArray = .{ .expressions = &.{} } } };
    var result = try astToTcbExpr(allocator, &node, null, .{ .strict_literal_types = true });
    defer result.deinit();
    const printed = try result.print();
    defer allocator.free(printed);
    try std.testing.expect(std.mem.indexOf(u8, printed, "as any") == null);
}

test "VeSafeLhsInferenceBugDetector: LiteralArray is true" {
    const node = AstNode{ .data = .{ .LiteralArray = .{ .expressions = &.{} } } };
    try std.testing.expect(try VeSafeLhsInferenceBugDetector.visit(&node));
}

test "VeSafeLhsInferenceBugDetector: LiteralPrimitive is false" {
    const node = AstNode{ .data = .{ .LiteralPrimitive = .{ .value = .{ .Number = 1.0 } } } };
    try std.testing.expect(!try VeSafeLhsInferenceBugDetector.visit(&node));
}

test "VeSafeLhsInferenceBugDetector: Call is true" {
    const inner = AstNode.implicitReceiver(.{ .start = 0, .end = 0 }, .{ .start = 0, .end = 0 });
    const node = AstNode{ .data = .{ .Call = .{ .receiver = &inner, .args = &.{} } } };
    try std.testing.expect(try VeSafeLhsInferenceBugDetector.veWillInferAnyFor(&node));
}

test "unwrapWritableSignal" {
    const allocator = std.testing.allocator;
    const result = try unwrapWritableSignal(allocator, "count");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("count.set", result);
}

test "nonNullAssert" {
    const allocator = std.testing.allocator;
    const result = try nonNullAssert(allocator, "x");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("x!", result);
}

test "safeNavigation" {
    const allocator = std.testing.allocator;
    const result = try safeNavigation(allocator, "x");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "!= null") != null);
}

test "withParseSpanInfo" {
    const allocator = std.testing.allocator;
    const result = try withParseSpanInfo(allocator, "x", .{ .start = 1, .end = 5 });
    defer allocator.free(result);
    try std.testing.expectEqualStrings("x/*1,5*/", result);
}

test "escapeTemplateLiteral via visitTemplateLiteral single element" {
    const allocator = std.testing.allocator;
    const elements = [_][]const u8{"hello"};
    const exprs = [_]*const AstNode{};
    const node = AstNode{ .data = .{ .TemplateLiteral = .{
        .elements = &elements,
        .expressions = &exprs,
    } } };
    var result = try astToTcbExpr(allocator, &node, null, .{});
    defer result.deinit();
    const printed = try result.print();
    defer allocator.free(printed);
    try std.testing.expectEqualStrings("`hello`", printed);
}

test "escapeTemplateLiteral escapes backticks and \\" {
    const allocator = std.testing.allocator;
    const elements = [_][]const u8{ "he`llo\\world" };
    const exprs = [_]*const AstNode{};
    const node = AstNode{ .data = .{ .TemplateLiteral = .{
        .elements = &elements,
        .expressions = &exprs,
    } } };
    var result = try astToTcbExpr(allocator, &node, null, .{});
    defer result.deinit();
    const printed = try result.print();
    defer allocator.free(printed);
    try std.testing.expectEqualStrings("`he\\`llo\\\\world`", printed);
}

test "visitLiteralMap empty" {
    const allocator = std.testing.allocator;
    const keys: []const LiteralMapKey = &.{};
    const values: []const *const AstNode = &.{};
    const node = AstNode{ .data = .{ .LiteralMap = .{ .keys = keys, .values = values } } };
    var result = try astToTcbExpr(allocator, &node, null, .{});
    defer result.deinit();
    const printed = try result.print();
    defer allocator.free(printed);
    try std.testing.expect(std.mem.indexOf(u8, printed, "{  }") != null);
}

test "tcbExpression wrapper" {
    const allocator = std.testing.allocator;
    const node = AstNode.literalString(.{ .start = 0, .end = 3 }, .{ .start = 0, .end = 3 }, "hi");
    var result = try tcbExpression(allocator, &node, .{});
    defer result.deinit();
    const printed = try result.print();
    defer allocator.free(printed);
    try std.testing.expect(std.mem.indexOf(u8, printed, "'hi'") != null);
}

test "AbsoluteSourceSpan contains" {
    const abs = AbsoluteSourceSpan{ .start = 5, .end = 10 };
    try std.testing.expect(abs.contains(5));
    try std.testing.expect(!abs.contains(10));
}

test "ParseSpan empty" {
    const s = ParseSpan.empty();
    try std.testing.expectEqual(@as(u32, 0), s.start);
    try std.testing.expectEqual(@as(u32, 0), s.end);
}

test "AstKind tag values" {
    try std.testing.expect(@intFromEnum(AstKind.Empty) == 0);
    try std.testing.expect(@intFromEnum(AstKind.ASTWithSource) == 28);
}

test "AstNode constructors" {
    const span = ParseSpan{ .start = 0, .end = 5 };
    const abs = AbsoluteSourceSpan{ .start = 0, .end = 5 };
    const e = AstNode.emptyExpr(span, abs);
    try std.testing.expect(e.data == .Empty);
    const s = AstNode.literalString(span, abs, "hi");
    try std.testing.expect(s.data == .LiteralPrimitive);
    const n = AstNode.literalNumber(span, abs, 1.0);
    try std.testing.expect(n.data == .LiteralPrimitive);
    const ir = AstNode.implicitReceiver(span, abs);
    try std.testing.expect(ir.data == .ImplicitReceiver);
    const tr = AstNode.thisReceiver(span, abs);
    try std.testing.expect(tr.data == .ThisReceiver);
}

test "absToSpan and absSpanToParseSpan" {
    const abs = AbsoluteSourceSpan{ .start = 3, .end = 7 };
    const s1 = absToSpan(abs);
    try std.testing.expectEqual(@as(u32, 3), s1.start);
    try std.testing.expectEqual(@as(u32, 7), s1.end);
    const s2 = absSpanToParseSpan(abs);
    try std.testing.expectEqual(@as(u32, 3), s2.start);
}
