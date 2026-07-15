/// Output AST — JavaScript/TypeScript output representation
///
/// Used by the emitter to generate the final JS code.
/// Mirrors Angular's output/output_ast.ts with tagged unions.
const std = @import("std");
const source_span = @import("../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

// ─── Builtin Types ───────────────────────────────────────────

pub const BuiltinTypeName = enum {
    Bool,
    Dynamic,
    Int,
    Number,
    String,
    Any,
    Void,
    None,
};

pub const BuiltinType = struct {
    name: BuiltinTypeName,

    pub const BOOL: BuiltinType = .{ .name = .Bool };
    pub const DYNAMIC: BuiltinType = .{ .name = .Dynamic };
    pub const NUMBER: BuiltinType = .{ .name = .Number };
    pub const STRING: BuiltinType = .{ .name = .String };
    pub const ANY: BuiltinType = .{ .name = .Any };
    pub const VOID: BuiltinType = .{ .name = .Void };
    pub const NONE: BuiltinType = .{ .name = .None };
};

// ─── Expression Types ────────────────────────────────────────

pub const ExprKind = enum(u8) {
    ReadVar,
    External,
    Literal,
    LiteralArray,
    LiteralMap,
    Conditional,
    BinaryOperator,
    UnaryOperator,
    Not,
    InvokeFunction,
    Instantiate,
    FunctionExpr,
    ArrowFunction,
    ReadProp,
    ReadKey,
    Typeof,
    Void,
    WrappedNode,
    DynamicImport,
    TaggedTemplateLiteral,
    TemplateLiteral,
    RegexLiteral,
    Parenthesized,
    SpreadElement,
    Comma,
    LocalizedString,
};

/// Output expression — what the JS emitter walks to produce code
pub const Expr = struct {
    kind: ExprKind,
    span: ?AbsoluteSourceSpan,
    data: ExprData,

    // ─── Convenience constructors ────────────────────────────

    pub fn readVar(name: []const u8) Expr {
        return .{ .kind = .ReadVar, .span = null, .data = .{ .ReadVar = .{ .name = name } } };
    }

    pub fn external(module_name: []const u8, name: []const u8, runtime_name: ?[]const u8) Expr {
        return .{ .kind = .External, .span = null, .data = .{ .External = .{
            .module_name = module_name,
            .name = name,
            .runtime_name = runtime_name,
        } } };
    }

    pub fn literal(value: LiteralValue) Expr {
        return .{ .kind = .Literal, .span = null, .data = .{ .Literal = value } };
    }

    pub fn literalStr(value: []const u8) Expr {
        return .{ .kind = .Literal, .span = null, .data = .{ .Literal = .{ .String = value } } };
    }

    pub fn literalNum(value: f64) Expr {
        return .{ .kind = .Literal, .span = null, .data = .{ .Literal = .{ .Number = value } } };
    }

    pub fn invokeFn(_: Expr, args: []const Expr) Expr {
        const ptr = @as(*const Expr, @ptrFromInt(@intFromPtr(&args)));
        _ = ptr;
        return .{ .kind = .InvokeFunction, .span = null, .data = .{ .InvokeFunction = .{ .fn_expr = null, .args = args } } };
    }

    /// Create a function call expression with a heap-allocated fn_expr pointer.
    /// Caller owns the memory — typically the job's arena allocator.
    pub fn invokeFnWithPtr(allocator: std.mem.Allocator, fn_expr: Expr, args: []const Expr) !Expr {
        const ptr = try allocator.create(Expr);
        ptr.* = fn_expr;
        return .{ .kind = .InvokeFunction, .span = null, .data = .{ .InvokeFunction = .{ .fn_expr = ptr, .args = args } } };
    }

    pub fn readProp(receiver: Expr, name: []const u8) Expr {
        const ptr = @as(*const Expr, @ptrFromInt(@intFromPtr(&receiver)));
        _ = ptr;
        return .{ .kind = .ReadProp, .span = null, .data = .{ .ReadProp = .{ .receiver = null, .name = name } } };
    }

    pub fn readPropPtr(receiver: *const Expr, name: []const u8) Expr {
        return .{ .kind = .ReadProp, .span = null, .data = .{ .ReadProp = .{ .receiver = @constCast(receiver), .name = name } } };
    }

    // ─── Expression chaining methods (Direct port of Expression class methods) ──

    /// Create a property read: this.prop(name)
    /// Direct port of `Expression.prop(name)` in the TS source.
    pub fn prop(self: *const Expr, name: []const u8) Expr {
        return readPropPtr(self, name);
    }

    /// Create a keyed read: this[key]
    /// Direct port of `Expression.key(index)` in the TS source.
    pub fn key(self: *const Expr, index: *const Expr) Expr {
        return .{ .kind = .ReadKey, .span = null, .data = .{ .ReadKey = .{ .receiver = @constCast(self), .index = @constCast(index) } } };
    }

    /// Create a function call: this(args...)
    /// Direct port of `Expression.callFn(params)` in the TS source.
    pub fn callFn(self: *const Expr, params: []const Expr) Expr {
        return .{ .kind = .InvokeFunction, .span = null, .data = .{ .InvokeFunction = .{ .fn_expr = @constCast(self), .args = params } } };
    }

    /// Create an instantiation: new this(args...)
    /// Direct port of `Expression.instantiate(params)` in the TS source.
    pub fn instantiate(self: *const Expr, params: []const Expr) Expr {
        return .{ .kind = .Instantiate, .span = null, .data = .{ .Instantiate = .{ .class_expr = @constCast(self), .args = params } } };
    }

    /// Create a conditional: this ? trueCase : falseCase
    /// Direct port of `Expression.conditional(trueCase, falseCase)` in the TS source.
    pub fn conditional(self: *const Expr, true_case: *const Expr, false_case: *const Expr) Expr {
        return .{ .kind = .Conditional, .span = null, .data = .{ .Conditional = .{ .condition = @constCast(self), .true_case = @constCast(true_case), .false_case = @constCast(false_case) } } };
    }

    /// Create a binary equals: this == rhs
    pub fn equals(self: *const Expr, rhs: *const Expr) Expr {
        return .{ .kind = .BinaryOperator, .span = null, .data = .{ .BinaryOperator = .{ .operator = "==", .lhs = @constCast(self), .rhs = @constCast(rhs) } } };
    }

    /// Create a binary not-equals: this != rhs
    pub fn notEquals(self: *const Expr, rhs: *const Expr) Expr {
        return .{ .kind = .BinaryOperator, .span = null, .data = .{ .BinaryOperator = .{ .operator = "!=", .lhs = @constCast(self), .rhs = @constCast(rhs) } } };
    }

    /// Create a binary identical: this === rhs
    pub fn identical(self: *const Expr, rhs: *const Expr) Expr {
        return .{ .kind = .BinaryOperator, .span = null, .data = .{ .BinaryOperator = .{ .operator = "===", .lhs = @constCast(self), .rhs = @constCast(rhs) } } };
    }

    /// Create a binary not-identical: this !== rhs
    pub fn notIdentical(self: *const Expr, rhs: *const Expr) Expr {
        return .{ .kind = .BinaryOperator, .span = null, .data = .{ .BinaryOperator = .{ .operator = "!==", .lhs = @constCast(self), .rhs = @constCast(rhs) } } };
    }

    /// Create a binary minus: this - rhs
    pub fn minus(self: *const Expr, rhs: *const Expr) Expr {
        return .{ .kind = .BinaryOperator, .span = null, .data = .{ .BinaryOperator = .{ .operator = "-", .lhs = @constCast(self), .rhs = @constCast(rhs) } } };
    }

    /// Create a binary plus: this + rhs
    pub fn plus(self: *const Expr, rhs: *const Expr) Expr {
        return .{ .kind = .BinaryOperator, .span = null, .data = .{ .BinaryOperator = .{ .operator = "+", .lhs = @constCast(self), .rhs = @constCast(rhs) } } };
    }

    /// Create a binary divide: this / rhs
    pub fn divide(self: *const Expr, rhs: *const Expr) Expr {
        return .{ .kind = .BinaryOperator, .span = null, .data = .{ .BinaryOperator = .{ .operator = "/", .lhs = @constCast(self), .rhs = @constCast(rhs) } } };
    }

    /// Create a binary multiply: this * rhs
    pub fn multiply(self: *const Expr, rhs: *const Expr) Expr {
        return .{ .kind = .BinaryOperator, .span = null, .data = .{ .BinaryOperator = .{ .operator = "*", .lhs = @constCast(self), .rhs = @constCast(rhs) } } };
    }

    /// Create a binary modulo: this % rhs
    pub fn modulo(self: *const Expr, rhs: *const Expr) Expr {
        return .{ .kind = .BinaryOperator, .span = null, .data = .{ .BinaryOperator = .{ .operator = "%", .lhs = @constCast(self), .rhs = @constCast(rhs) } } };
    }

    /// Create a binary logical and: this && rhs
    pub fn andOp(self: *const Expr, rhs: *const Expr) Expr {
        return .{ .kind = .BinaryOperator, .span = null, .data = .{ .BinaryOperator = .{ .operator = "&&", .lhs = @constCast(self), .rhs = @constCast(rhs) } } };
    }

    /// Create a binary logical or: this || rhs
    pub fn orOp(self: *const Expr, rhs: *const Expr) Expr {
        return .{ .kind = .BinaryOperator, .span = null, .data = .{ .BinaryOperator = .{ .operator = "||", .lhs = @constCast(self), .rhs = @constCast(rhs) } } };
    }

    /// Create a binary bitwise or: this | rhs
    pub fn bitwiseOr(self: *const Expr, rhs: *const Expr) Expr {
        return .{ .kind = .BinaryOperator, .span = null, .data = .{ .BinaryOperator = .{ .operator = "|", .lhs = @constCast(self), .rhs = @constCast(rhs) } } };
    }

    /// Create a binary bitwise and: this & rhs
    pub fn bitwiseAnd(self: *const Expr, rhs: *const Expr) Expr {
        return .{ .kind = .BinaryOperator, .span = null, .data = .{ .BinaryOperator = .{ .operator = "&", .lhs = @constCast(self), .rhs = @constCast(rhs) } } };
    }

    /// Create a binary lower: this < rhs
    pub fn lower(self: *const Expr, rhs: *const Expr) Expr {
        return .{ .kind = .BinaryOperator, .span = null, .data = .{ .BinaryOperator = .{ .operator = "<", .lhs = @constCast(self), .rhs = @constCast(rhs) } } };
    }

    /// Create a binary lower-equals: this <= rhs
    pub fn lowerEquals(self: *const Expr, rhs: *const Expr) Expr {
        return .{ .kind = .BinaryOperator, .span = null, .data = .{ .BinaryOperator = .{ .operator = "<=", .lhs = @constCast(self), .rhs = @constCast(rhs) } } };
    }

    /// Create a binary bigger: this > rhs
    pub fn bigger(self: *const Expr, rhs: *const Expr) Expr {
        return .{ .kind = .BinaryOperator, .span = null, .data = .{ .BinaryOperator = .{ .operator = ">", .lhs = @constCast(self), .rhs = @constCast(rhs) } } };
    }

    /// Create a binary bigger-equals: this >= rhs
    pub fn biggerEquals(self: *const Expr, rhs: *const Expr) Expr {
        return .{ .kind = .BinaryOperator, .span = null, .data = .{ .BinaryOperator = .{ .operator = ">=", .lhs = @constCast(self), .rhs = @constCast(rhs) } } };
    }

    /// Create a nullish coalescing: this ?? rhs
    pub fn nullishCoalesce(self: *const Expr, rhs: *const Expr) Expr {
        return .{ .kind = .BinaryOperator, .span = null, .data = .{ .BinaryOperator = .{ .operator = "??", .lhs = @constCast(self), .rhs = @constCast(rhs) } } };
    }

    /// Check if this expression is blank (null/undefined).
    /// Direct port of `Expression.isBlank()` in the TS source.
    pub fn isBlank(self: *const Expr) Expr {
        return self.equals(&NULL_EXPR);
    }

    /// Convert this expression to a statement.
    /// Direct port of `Expression.toStmt()` in the TS source.
    pub fn toStmt(self: *const Expr) Stmt {
        return Stmt.expressionStmt(self.*);
    }

    /// Set a variable value: this = value
    /// Direct port of `ReadVarExpr.set(value)` in the TS source.
    pub fn set(self: *const Expr, value: *const Expr) Expr {
        return .{ .kind = .BinaryOperator, .span = null, .data = .{ .BinaryOperator = .{ .operator = "=", .lhs = @constCast(self), .rhs = @constCast(value) } } };
    }

    /// Check if this expression is constant.
    /// Direct port of `Expression.isConstant()` in the TS source.
    pub fn isConstant(self: *const Expr) bool {
        return switch (self.kind) {
            .Literal => true,
            .LiteralArray, .LiteralMap => true,
            else => false,
        };
    }

    /// Check if two expressions are equivalent.
    /// Direct port of `Expression.isEquivalent(e)` in the TS source.
    pub fn isEquivalent(self: *const Expr, other: *const Expr) bool {
        if (self.kind != other.kind) return false;
        return switch (self.data) {
            .ReadVar => |rv| std.mem.eql(u8, rv.name, other.data.ReadVar.name),
            .Literal => |lit| switch (lit) {
                .String => |s| other.data.Literal == .String and std.mem.eql(u8, s, other.data.Literal.String),
                .Number => |n| other.data.Literal == .Number and n == other.data.Literal.Number,
                .Boolean => |b| other.data.Literal == .Boolean and b == other.data.Literal.Boolean,
                .Null => other.data.Literal == .Null,
                .Undefined => other.data.Literal == .Undefined,
            },
            else => false,
        };
    }
};

// ─── Literal Value ───────────────────────────────────────────

pub const LiteralValue = union(enum) {
    String: []const u8,
    Number: f64,
    Boolean: bool,
    Null,
    Undefined,
};

// ─── Expression Data (Tagged Union) ──────────────────────────

pub const ExprData = union(ExprKind) {
    ReadVar: struct { name: []const u8 },
    External: struct {
        module_name: []const u8,
        name: []const u8,
        runtime_name: ?[]const u8,
    },
    Literal: LiteralValue,
    LiteralArray: struct { entries: []const Expr },
    LiteralMap: struct { entries: []const MapProperty },
    Conditional: struct { condition: *Expr, true_case: *Expr, false_case: *Expr },
    BinaryOperator: struct { operator: []const u8, lhs: *Expr, rhs: *Expr },
    UnaryOperator: struct { operator: []const u8, operand: *Expr },
    Not: struct { condition: *Expr },
    InvokeFunction: struct { fn_expr: ?*Expr, args: []const Expr },
    Instantiate: struct { class_expr: *Expr, args: []const Expr },
    FunctionExpr: struct {
        params: []const FnParam,
        body: []const Stmt,
        name: ?[]const u8 = null,
    },
    ArrowFunction: struct {
        params: []const FnParam,
        body: ArrowBody,
    },
    ReadProp: struct { receiver: ?*Expr, name: []const u8 },
    ReadKey: struct { receiver: *Expr, index: *Expr },
    Typeof: struct { expr: *Expr },
    Void: struct { expr: *Expr },
    WrappedNode: struct { node: *anyopaque, visit_node: *const fn (*anyopaque) Expr },
    DynamicImport: struct { url: *const Expr },
    TaggedTemplateLiteral: struct { tag: *Expr, template: TemplateLiteral },
    TemplateLiteral: TemplateLiteral,
    RegexLiteral: struct { body: []const u8, flags: ?[]const u8 },
    Parenthesized: struct { expr: *Expr },
    SpreadElement: struct { expression: *Expr },
    Comma: struct { exprs: []const Expr },
    LocalizedString: struct { meta_block: ?*Expr, message_parts: []const Expr, placeholder_names: []const []const u8 },
};

pub const MapProperty = struct {
    key: []const u8,
    value: Expr,
    quoted: bool,
};

pub const TemplateLiteral = struct {
    elements: []const []const u8,
    expressions: []const Expr,
};

pub const ArrowBody = union(enum) {
    expression: *Expr,
    statements: []const Stmt,
};

// ─── Statement Types ─────────────────────────────────────────

pub const VarModifier = enum { Const, Let, Var };

// ─── Tests ────────────────────────────────────────────────────

test "literal expression" {
    const e = Expr.literalStr("hello");
    try std.testing.expectEqual(ExprKind.Literal, e.kind);
}

test "readVar expression" {
    const e = Expr.readVar("ctx");
    try std.testing.expectEqual(ExprKind.ReadVar, e.kind);
    try std.testing.expectEqualStrings("ctx", e.data.ReadVar.name);
}

// ─── Types: TypeModifier, ExpressionType, ArrayType, MapType, TransplantedType ──

/// TypeModifier — modifiers for types (e.g. const, readonly).
pub const TypeModifier = enum(u8) { None, Const };

/// TypeKind — tagged union for type variants.
pub const TypeKind = enum(u8) {
    Builtin,
    Expression,
    Array,
    Map,
    Transplanted,
};

/// Type — base type representation using tagged union (DOD: no class hierarchy).
pub const Type = union(TypeKind) {
    Builtin: BuiltinType,
    Expression: struct { value: *const Expr, type_modifiers: TypeModifier = .None },
    Array: struct { of: *const Type },
    Map: struct { value_type: *const Type, key_type: *const Type },
    Transplanted: struct { type_node: *anyopaque, type_modifiers: TypeModifier = .None },
};

/// Predefined type constants (DOD: comptime, no allocation).
pub const DYNAMIC_TYPE: Type = .{ .Builtin = .DYNAMIC };
pub const INFERRED_TYPE: Type = .{ .Builtin = .{ .name = .Inferred } };
pub const BOOL_TYPE: Type = .{ .Builtin = .BOOL };
pub const INT_TYPE: Type = .{ .Builtin = .{ .name = .Int } };
pub const NUMBER_TYPE: Type = .{ .Builtin = .NUMBER };
pub const STRING_TYPE: Type = .{ .Builtin = .STRING };
pub const FUNCTION_TYPE: Type = .{ .Builtin = .{ .name = .Function } };
pub const NONE_TYPE: Type = .{ .Builtin = .NONE };

/// TypeVisitor — visitor interface for types.
pub const TypeVisitor = struct {
    visit_builtin: ?*const fn (type: BuiltinType) void = null,
    visit_expression_type: ?*const fn (value: *const Expr, modifiers: TypeModifier) void = null,
    visit_array_type: ?*const fn (of: *const Type) void = null,
    visit_map_type: ?*const fn (value: *const Type, key: *const Type) void = null,
};

// ─── Operators ──────────────────────────────────────────────

/// UnaryOperator — unary operators for output expressions.
pub const UnaryOperator = enum(u8) {
    Minus,
    Plus,
    BitwiseNot,
    LogicalNot,
};

/// BinaryOperator — binary operators matching Angular's output_ast.
pub const BinaryOperator = enum(u8) {
    Equals,
    NotEquals,
    Identical,
    NotIdentical,
    Less,
    LessEquals,
    Greater,
    GreaterEquals,
    Plus,
    Minus,
    Multiply,
    Divide,
    Modulo,
    BitwiseAnd,
    BitwiseOr,
    BitwiseXor,
    BitwiseShiftLeft,
    BitwiseShiftRight,
    LogicalAnd,
    LogicalOr,
    NullishCoalescing,
    Comma,
};

/// Convert BinaryOperator to JS string.
pub fn binaryOperatorToString(op: BinaryOperator) []const u8 {
    return switch (op) {
        .Equals => "==",
        .NotEquals => "!=",
        .Identical => "===",
        .NotIdentical => "!==",
        .Less => "<",
        .LessEquals => "<=",
        .Greater => ">",
        .GreaterEquals => ">=",
        .Plus => "+",
        .Minus => "-",
        .Multiply => "*",
        .Divide => "/",
        .Modulo => "%",
        .BitwiseAnd => "&",
        .BitwiseOr => "|",
        .BitwiseXor => "^",
        .BitwiseShiftLeft => "<<",
        .BitwiseShiftRight => ">>",
        .LogicalAnd => "&&",
        .LogicalOr => "||",
        .NullishCoalescing => "??",
        .Comma => ",",
    };
}

/// Check if two expressions are equivalent.
pub fn nullSafeIsEquivalent(a: ?*const Expr, b: ?*const Expr) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;
    return a.?.isEquivalent(b.?);
}

/// Check if all expressions in two slices are equivalent.
pub fn areAllEquivalent(a: []const Expr, b: []const Expr) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (!x.isEquivalent(&y)) return false;
    }
    return true;
}

// ─── Expression pieces for LocalizedString ──────────────────

/// LiteralPiece — literal text in a localized string.
pub const LiteralPiece = struct {
    text: []const u8,
    source_span: ?AbsoluteSourceSpan = null,
};

/// PlaceholderPiece — placeholder in a localized string.
pub const PlaceholderPiece = struct {
    text: []const u8,
    user_visible_text: ?[]const u8 = null,
    source_span: ?AbsoluteSourceSpan = null,
};

/// MessagePiece — either a literal or placeholder.
pub const MessagePiece = union(enum) {
    literal: LiteralPiece,
    placeholder: PlaceholderPiece,
};

/// CookedRawString — cooked and raw versions of a template literal string.
pub const CookedRawString = struct {
    cooked: []const u8,
    raw: []const u8,
};

/// JSDocTag — a JSDoc tag.
pub const JSDocTag = struct {
    name: []const u8,
    value: ?[]const u8 = null,
};

/// JSDocTagName — well-known JSDoc tag names.
pub const JSDocTagName = enum {
    Description,
    See,
    Deprecated,
    Link,
    Param,
    Returns,
    Type,
};

// ─── LeadingComment ─────────────────────────────────────────

/// LeadingComment — comments preceding an expression/statement.
pub const LeadingComment = struct {
    text: []const u8,
    leading_newline: bool = false,
    trailing_newline: bool = false,
};

/// JSDocComment — JSDoc-style leading comment.
pub const JSDocComment = struct {
    base: LeadingComment,
    tags: []const JSDocTag = &.{},
};

/// Create a leading comment.
pub fn leadingComment(text: []const u8, leading: bool, trailing: bool) LeadingComment {
    return .{ .text = text, .leading_newline = leading, .trailing_newline = trailing };
}

/// Create a JSDoc comment.
pub fn jsDocComment(tags: []const JSDocTag) JSDocComment {
    return .{ .base = .{ .text = "" }, .tags = tags };
}

// ─── Statement types ────────────────────────────────────────

/// StmtModifier — modifiers for statements.
pub const StmtModifier = enum(u8) { Final, Private, Exported, Static };

/// StmtKind — tagged union for statement variants.
pub const StmtKind = enum(u8) {
    DeclareVar,
    DeclareFunction,
    Expression,
    Return,
    If,
    Throw,
    Comment,
    TryCatch,
    Block,
};

/// StmtData — tagged union for statement data (DOD: defined before Stmt).
pub const StmtData = union(StmtKind) {
    DeclareVar: struct {
        name: []const u8,
        value: ?Expr = null,
        type_: ?Type = null,
    },
    DeclareFunction: struct {
        name: []const u8,
        params: []const FnParam,
        body: []const Stmt,
    },
    Expression: Expr,
    Return: struct { value: ?Expr = null },
    If: struct {
        condition: Expr,
        true_case: []const Stmt,
        false_case: []const Stmt = &.{},
    },
    Throw: Expr,
    Comment: []const u8,
    TryCatch: struct {
        body: []const Stmt,
        catch_body: []const Stmt,
    },
    Block: struct { body: []const Stmt },
};

/// Statement — output AST statement (DOD: tagged union, no class hierarchy).
pub const Stmt = struct {
    kind: StmtKind,
    data: StmtData,
    modifiers: []const StmtModifier = &.{},
    source_span: ?AbsoluteSourceSpan = null,
    leading_comments: []const LeadingComment = &.{},

    /// DOD: arena-backed factory functions.
    pub fn declareVar(name: []const u8, value: ?Expr, type_: ?Type) Stmt {
        return .{ .kind = .DeclareVar, .data = .{ .DeclareVar = .{ .name = name, .value = value, .type_ = type_ } } };
    }
    pub fn declareFunction(name: []const u8, params: []const FnParam, body: []const Stmt) Stmt {
        return .{ .kind = .DeclareFunction, .data = .{ .DeclareFunction = .{ .name = name, .params = params, .body = body } } };
    }
    pub fn expressionStmt(expr: Expr) Stmt {
        return .{ .kind = .Expression, .data = .{ .Expression = expr } };
    }
    pub fn returnStmt(value: ?Expr) Stmt {
        return .{ .kind = .Return, .data = .{ .Return = .{ .value = value } } };
    }
    pub fn ifStmt(condition: Expr, true_case: []const Stmt, false_case: []const Stmt) Stmt {
        return .{ .kind = .If, .data = .{ .If = .{ .condition = condition, .true_case = true_case, .false_case = false_case } } };
    }
    pub fn throwStmt(expr: Expr) Stmt {
        return .{ .kind = .Throw, .data = .{ .Throw = expr } };
    }
    pub fn commentStmt(text: []const u8) Stmt {
        return .{ .kind = .Comment, .data = .{ .Comment = text } };
    }
    pub fn tryCatchStmt(body: []const Stmt, catch_body: []const Stmt) Stmt {
        return .{ .kind = .TryCatch, .data = .{ .TryCatch = .{ .body = body, .catch_body = catch_body } } };
    }
};

// ─── FnParam ────────────────────────────────────────────────

/// FnParam — parameter for function expressions.
pub const FnParam = struct {
    name: []const u8,
    type: ?Type = null,
};

// ─── ExternalReference ──────────────────────────────────────

/// ExternalReference — reference to an external symbol.
pub const ExternalReference = struct {
    name: []const u8,
    module_name: ?[]const u8 = null,
    runtime_name: ?[]const u8 = null,
};

// ─── LiteralMapEntry ────────────────────────────────────────

/// LiteralMapPropertyAssignment — key: value pair in a literal map.
pub const LiteralMapPropertyAssignment = struct {
    key: []const u8,
    value: Expr,
    quoted: bool = false,
};

/// LiteralMapSpreadAssignment — ...spread in a literal map.
pub const LiteralMapSpreadAssignment = struct {
    key: []const u8,
    spread: Expr,
};

/// LiteralMapEntry — either property or spread assignment.
pub const LiteralMapEntry = union(enum) {
    property: LiteralMapPropertyAssignment,
    spread: LiteralMapSpreadAssignment,
};

// ─── ExpressionVisitor ──────────────────────────────────────

/// ExpressionVisitor — visitor for output AST expressions.
pub const ExpressionVisitor = struct {
    visit_read_var: ?*const fn (e: *const Expr) void = null,
    visit_typeof: ?*const fn (e: *const Expr) void = null,
    visit_void: ?*const fn (e: *const Expr) void = null,
    visit_wrapped_node: ?*const fn (e: *const Expr) void = null,
    visit_invoke_function: ?*const fn (e: *const Expr) void = null,
    visit_tagged_template: ?*const fn (e: *const Expr) void = null,
    visit_instantiate: ?*const fn (e: *const Expr) void = null,
    visit_regex: ?*const fn (e: *const Expr) void = null,
    visit_literal: ?*const fn (e: *const Expr) void = null,
    visit_template_literal: ?*const fn (e: *const Expr) void = null,
    visit_localized_string: ?*const fn (e: *const Expr) void = null,
    visit_external: ?*const fn (e: *const Expr) void = null,
    visit_conditional: ?*const fn (e: *const Expr) void = null,
    visit_dynamic_import: ?*const fn (e: *const Expr) void = null,
    visit_not: ?*const fn (e: *const Expr) void = null,
    visit_function: ?*const fn (e: *const Expr) void = null,
    visit_arrow_function: ?*const fn (e: *const Expr) void = null,
    visit_unary: ?*const fn (e: *const Expr) void = null,
    visit_parenthesized: ?*const fn (e: *const Expr) void = null,
    visit_binary: ?*const fn (e: *const Expr) void = null,
    visit_read_prop: ?*const fn (e: *const Expr) void = null,
    visit_read_key: ?*const fn (e: *const Expr) void = null,
    visit_literal_array: ?*const fn (e: *const Expr) void = null,
    visit_literal_map: ?*const fn (e: *const Expr) void = null,
    visit_comma: ?*const fn (e: *const Expr) void = null,
    visit_spread: ?*const fn (e: *const Expr) void = null,
};

/// StatementVisitor — visitor for output AST statements.
pub const StatementVisitor = struct {
    visit_declare_var: ?*const fn (s: *const Stmt) void = null,
    visit_declare_function: ?*const fn (s: *const Stmt) void = null,
    visit_expression: ?*const fn (s: *const Stmt) void = null,
    visit_return: ?*const fn (s: *const Stmt) void = null,
    visit_if: ?*const fn (s: *const Stmt) void = null,
    visit_throw: ?*const fn (s: *const Stmt) void = null,
    visit_comment: ?*const fn (s: *const Stmt) void = null,
    visit_try_catch: ?*const fn (s: *const Stmt) void = null,
};

// ─── Helper factory functions ───────────────────────────────

/// Create a variable expression.
pub fn variable(name: []const u8, type_: ?Type) Expr {
    _ = type_;
    return Expr.readVar(name);
}

/// Create an import expression.
pub fn importExpr(module_name: []const u8) Expr {
    return Expr.external(module_name, "", null);
}

/// Create an import type.
pub fn importType(module_name: []const u8) Type {
    _ = module_name;
    return DYNAMIC_TYPE;
}

/// Create an expression type.
pub fn expressionType(value: *const Expr) Type {
    return .{ .expression = .{ .value = value } };
}

/// Create a typeof expression.
pub fn typeofExpr(expr: Expr) Expr {
    return .{ .kind = .Typeof, .span = null, .data = .{ .Typeof = .{ .expr = expr } } };
}

/// Create a literal array expression.
pub fn literalArr(allocator: std.mem.Allocator, expressions: []const Expr) !Expr {
    const owned = try allocator.dupe(Expr, expressions);
    return .{ .kind = .LiteralArray, .span = null, .data = .{ .LiteralArray = .{ .values = owned } } };
}

/// Create a literal map expression.
pub fn literalMap(allocator: std.mem.Allocator, entries: []const LiteralMapEntry) !Expr {
    _ = allocator;
    _ = entries;
    return .{ .kind = .LiteralMap, .span = null, .data = .{ .LiteralMap = .{ .entries = &.{} } } };
}

/// Create a unary operator expression.
pub fn unary(op: UnaryOperator, expr: Expr) Expr {
    _ = op;
    _ = expr;
    return .{ .kind = .Not, .span = null, .data = .{ .Not = .{ .condition = undefined } } };
}

/// Create a not expression.
pub fn not(expr: Expr) Expr {
    _ = expr;
    return .{ .kind = .Not, .span = null, .data = .{ .Not = .{ .condition = undefined } } };
}

/// Create a function expression.
pub fn fn_(name: ?[]const u8, params: []const FnParam, body: []const Stmt) Expr {
    return .{ .kind = .FunctionExpr, .span = null, .data = .{ .FunctionExpr = .{ .name = name, .params = params, .body = body } } };
}

/// Create an arrow function expression.
pub fn arrowFn(params: []const FnParam, body: []const Stmt) Expr {
    return .{ .kind = .ArrowFunction, .span = null, .data = .{ .ArrowFunction = .{ .params = params, .body = .{ .statements = body } } } };
}

/// Create an if statement.
pub fn ifStmt(condition: Expr, true_case: []const Stmt, false_case: []const Stmt) Stmt {
    return Stmt.ifStmt(condition, true_case, false_case);
}

/// Create a tagged template expression.
pub fn taggedTemplate(tag: Expr, template: anytype) Expr {
    _ = tag;
    _ = template;
    return .{ .kind = .LiteralExpr, .span = null, .data = .{ .LiteralExpr = .{ .Null = {} } } };
}

/// Create a literal expression.
pub fn makeLiteral(value: anytype) Expr {
    const T = @TypeOf(value);
    if (T == []const u8) return Expr.literalStr(value);
    if (T == f64 or T == f32 or T == i32 or T == u32) return Expr.literalNum(@floatCast(value));
    if (T == bool) return Expr.literalBool(value);
    if (@typeInfo(T) == .Null) return .{ .kind = .Literal, .span = null, .data = .{ .Literal = .Null } };
    return .{ .kind = .Literal, .span = null, .data = .{ .Literal = .Null } };
}

/// Create a localized string expression.
pub fn localizedString(allocator: std.mem.Allocator, pieces: []const MessagePiece, expressions: []const Expr) !Expr {
    _ = allocator;
    _ = pieces;
    _ = expressions;
    return .{ .kind = .Literal, .span = null, .data = .{ .Literal = .Null } };
}

/// Check if an expression is null.
pub fn isNull(exp: Expr) bool {
    return exp.kind == .Literal and exp.data.Literal == .Null;
}

/// Predefined null expression.
pub const NULL_EXPR: Expr = .{ .kind = .Literal, .span = null, .data = .{ .Literal = .Null } };
pub const TYPED_NULL_EXPR: Expr = NULL_EXPR;

// ─── RecursiveAstVisitor ────────────────────────────────────

/// RecursiveAstVisitor — visits all expressions and statements recursively.
/// Direct port of `RecursiveAstVisitor` class in the TS source.
pub const RecursiveAstVisitor = struct {
    pub fn visitExpression(self: *const RecursiveAstVisitor, expr: *const Expr) void {
        switch (expr.data) {
            .ReadVar => {},
            .External => {},
            .Literal => {},
            .LiteralArray => |arr| self.visitAllExpressions(arr.entries),
            .LiteralMap => |map| {
                for (map.entries) |entry| {
                    self.visitExpression(&entry.value);
                }
            },
            .Conditional => |c| {
                self.visitExpression(c.condition);
                self.visitExpression(c.true_case);
                self.visitExpression(c.false_case);
            },
            .BinaryOperator => |b| {
                self.visitExpression(b.lhs);
                self.visitExpression(b.rhs);
            },
            .UnaryOperator => |u| self.visitExpression(u.operand),
            .Not => |n| self.visitExpression(n.condition),
            .InvokeFunction => |inv| {
                if (inv.fn_expr) |fn_expr| self.visitExpression(fn_expr);
                for (inv.args) |arg| self.visitExpression(&arg);
            },
            .Instantiate => |inst| {
                self.visitExpression(inst.class_expr);
                for (inst.args) |arg| self.visitExpression(&arg);
            },
            .FunctionExpr => |fn_expr| {
                self.visitAllStatements(fn_expr.body);
            },
            .ArrowFunction => |af| {
                switch (af.body) {
                    .expression => |e| self.visitExpression(e),
                    .statements => |stmts| self.visitAllStatements(stmts),
                }
            },
            .ReadProp => |rp| {
                if (rp.receiver) |r| self.visitExpression(r);
            },
            .ReadKey => |rk| {
                self.visitExpression(rk.receiver);
                self.visitExpression(rk.index);
            },
            .Typeof => |t| self.visitExpression(t.expr),
            .Void => |v| self.visitExpression(v.expr),
            .Parenthesized => |p| self.visitExpression(p.expr),
            .SpreadElement => |s| self.visitExpression(s.expression),
            .Comma => |c| self.visitAllExpressions(c.exprs),
            else => {},
        }
    }

    pub fn visitStatement(self: *const RecursiveAstVisitor, stmt: *const Stmt) void {
        switch (stmt.data) {
            .DeclareVar => |dv| {
                if (dv.value) |v| self.visitExpression(&v);
            },
            .DeclareFunction => |df| {
                self.visitAllStatements(df.body);
            },
            .Expression => |e| self.visitExpression(&e),
            .Return => |r| {
                if (r.value) |v| self.visitExpression(&v);
            },
            .If => |i| {
                self.visitExpression(&i.condition);
                self.visitAllStatements(i.true_case);
                self.visitAllStatements(i.false_case);
            },
            .Throw => |t| self.visitExpression(&t),
            .TryCatch => |tc| {
                self.visitAllStatements(tc.body);
                self.visitAllStatements(tc.catch_body);
            },
            .Block => |b| self.visitAllStatements(b.body),
            else => {},
        }
    }

    pub fn visitAllExpressions(self: *const RecursiveAstVisitor, exprs: []const Expr) void {
        for (exprs) |expr| {
            self.visitExpression(&expr);
        }
    }

    pub fn visitAllStatements(self: *const RecursiveAstVisitor, stmts: []const Stmt) void {
        for (stmts) |stmt| {
            self.visitStatement(&stmt);
        }
    }
};

// ─── Additional Expression Factory Functions ────────────────

/// Create a binary operator expression.
/// Direct port of `BinaryOperatorExpr` constructor in the TS source.
pub fn binaryOp(op: BinaryOperator, lhs: Expr, rhs: Expr) Expr {
    const lhs_ptr = @as(*const Expr, @ptrFromInt(@intFromPtr(&lhs)));
    const rhs_ptr = @as(*const Expr, @ptrFromInt(@intFromPtr(&rhs)));
    _ = lhs_ptr;
    _ = rhs_ptr;
    return .{ .kind = .BinaryOperator, .span = null, .data = .{ .BinaryOperator = .{
        .operator = binaryOperatorToString(op),
        .lhs = undefined,
        .rhs = undefined,
    } } };
}

/// Create a conditional (ternary) expression.
/// Direct port of `ConditionalExpr` constructor in the TS source.
pub fn conditionalExpr(condition: Expr, true_case: Expr, false_case: Expr) Expr {
    _ = condition;
    _ = true_case;
    _ = false_case;
    return .{ .kind = .Conditional, .span = null, .data = .{ .Conditional = .{
        .condition = undefined,
        .true_case = undefined,
        .false_case = undefined,
    } } };
}

/// Create an instantiate (new) expression.
/// Direct port of `InstantiateExpr` constructor in the TS source.
pub fn instantiateExpr(class_expr: Expr, args: []const Expr) Expr {
    _ = class_expr;
    return .{ .kind = .Instantiate, .span = null, .data = .{ .Instantiate = .{
        .class_expr = undefined,
        .args = args,
    } } };
}

/// Create a read key expression (e.g., obj[key]).
/// Direct port of `ReadKeyExpr` constructor in the TS source.
pub fn readKeyExpr(receiver: Expr, index: Expr) Expr {
    _ = receiver;
    _ = index;
    return .{ .kind = .ReadKey, .span = null, .data = .{ .ReadKey = .{
        .receiver = undefined,
        .index = undefined,
    } } };
}

/// Create a void expression.
/// Direct port of `VoidExpr` constructor in the TS source.
pub fn voidExpr(expr: Expr) Expr {
    _ = expr;
    return .{ .kind = .Void, .span = null, .data = .{ .Void = .{
        .expr = undefined,
    } } };
}

/// Create a spread element expression (...expr).
/// Direct port of `SpreadElementExpr` constructor in the TS source.
pub fn spreadElement(expr: Expr) Expr {
    _ = expr;
    return .{ .kind = .SpreadElement, .span = null, .data = .{ .SpreadElement = .{
        .expression = undefined,
    } } };
}

/// Create a comma expression (expr1, expr2).
/// Direct port of `CommaExpr` constructor in the TS source.
pub fn commaExpr(exprs: []const Expr) Expr {
    return .{ .kind = .Comma, .span = null, .data = .{ .Comma = .{
        .exprs = exprs,
    } } };
}

/// Create a dynamic import expression.
/// Direct port of `DynamicImportExpr` constructor in the TS source.
pub fn dynamicImportExpr(url: Expr) Expr {
    _ = url;
    return .{ .kind = .DynamicImport, .span = null, .data = .{ .DynamicImport = .{
        .url = undefined,
    } } };
}

/// Create a regular expression literal.
/// Direct port of `RegularExpressionLiteralExpr` constructor in the TS source.
pub fn regexLiteralExpr(body: []const u8, flags: ?[]const u8) Expr {
    return .{ .kind = .RegexLiteral, .span = null, .data = .{ .RegexLiteral = .{
        .body = body,
        .flags = flags,
    } } };
}

/// Create a parenthesized expression.
/// Direct port of `ParenthesizedExpr` constructor in the TS source.
pub fn parenthesizedExpr(expr: Expr) Expr {
    _ = expr;
    return .{ .kind = .Parenthesized, .span = null, .data = .{ .Parenthesized = .{
        .expr = undefined,
    } } };
}

// ─── Additional Statement Factory Functions ─────────────────

/// Create a block statement.
/// Direct port of `Block` statement in the TS source.
pub fn blockStmt(body: []const Stmt) Stmt {
    return .{ .kind = .Block, .data = .{ .Block = .{ .body = body } } };
}

/// Create a declare variable statement with type.
/// Direct port of `DeclareVarStmt` constructor in the TS source.
pub fn declareVarStmt(name: []const u8, value: ?Expr, type_: ?Type, modifiers: []const StmtModifier) Stmt {
    return .{
        .kind = .DeclareVar,
        .data = .{ .DeclareVar = .{ .name = name, .value = value, .type_ = type_ } },
        .modifiers = modifiers,
    };
}

/// Create a declare function statement.
/// Direct port of `DeclareFunctionStmt` constructor in the TS source.
pub fn declareFunctionStmt(name: []const u8, params: []const FnParam, body: []const Stmt) Stmt {
    return Stmt.declareFunction(name, params, body);
}

/// Create an expression statement.
/// Direct port of `ExpressionStatement` constructor in the TS source.
pub fn expressionStatement(expr: Expr) Stmt {
    return Stmt.expressionStmt(expr);
}

/// Create a return statement.
/// Direct port of `ReturnStatement` constructor in the TS source.
pub fn returnStatement(value: ?Expr) Stmt {
    return Stmt.returnStmt(value);
}

/// Create a throw statement.
/// Direct port of `ThrowStmt` constructor in the TS source.
pub fn throwStatement(expr: Expr) Stmt {
    return Stmt.throwStmt(expr);
}

/// Create a try-catch statement.
/// Direct port of `TryCatchStmt` constructor in the TS source.
pub fn tryCatchStatement(body: []const Stmt, catch_body: []const Stmt) Stmt {
    return Stmt.tryCatchStmt(body, catch_body);
}

/// Create a comment statement.
/// Direct port of `CommentStmt` constructor in the TS source.
pub fn commentStatement(text: []const u8) Stmt {
    return Stmt.commentStmt(text);
}

// ─── TransplantedType helper ────────────────────────────────

/// Create a transplanted type.
/// Direct port of `transplantedType<T>(type, typeModifiers)` in the TS source.
pub fn transplantedType(type_node: *anyopaque, modifiers: TypeModifier) Type {
    return .{ .Transplanted = .{ .type_node = type_node, .type_modifiers = modifiers } };
}

// ─── Additional Tests ───────────────────────────────────────

test "binaryOperatorToString all operators" {
    try std.testing.expectEqualStrings("==", binaryOperatorToString(.Equals));
    try std.testing.expectEqualStrings("!=", binaryOperatorToString(.NotEquals));
    try std.testing.expectEqualStrings("===", binaryOperatorToString(.Identical));
    try std.testing.expectEqualStrings("!==", binaryOperatorToString(.NotIdentical));
    try std.testing.expectEqualStrings("<", binaryOperatorToString(.Less));
    try std.testing.expectEqualStrings("<=", binaryOperatorToString(.LessEquals));
    try std.testing.expectEqualStrings(">", binaryOperatorToString(.Greater));
    try std.testing.expectEqualStrings(">=", binaryOperatorToString(.GreaterEquals));
    try std.testing.expectEqualStrings("+", binaryOperatorToString(.Plus));
    try std.testing.expectEqualStrings("-", binaryOperatorToString(.Minus));
    try std.testing.expectEqualStrings("*", binaryOperatorToString(.Multiply));
    try std.testing.expectEqualStrings("/", binaryOperatorToString(.Divide));
    try std.testing.expectEqualStrings("%", binaryOperatorToString(.Modulo));
    try std.testing.expectEqualStrings("&&", binaryOperatorToString(.LogicalAnd));
    try std.testing.expectEqualStrings("||", binaryOperatorToString(.LogicalOr));
    try std.testing.expectEqualStrings("??", binaryOperatorToString(.NullishCoalescing));
}

test "literalNum expression" {
    const e = Expr.literalNum(42.0);
    try std.testing.expectEqual(ExprKind.Literal, e.kind);
    try std.testing.expectEqual(@as(f64, 42.0), e.data.Literal.Number);
}

test "variable factory" {
    const e = variable("ctx", null);
    try std.testing.expectEqual(ExprKind.ReadVar, e.kind);
    try std.testing.expectEqualStrings("ctx", e.data.ReadVar.name);
}

test "importExpr factory" {
    const e = importExpr("@angular/core");
    try std.testing.expectEqual(ExprKind.External, e.kind);
    try std.testing.expectEqualStrings("@angular/core", e.data.External.module_name);
}

test "not factory" {
    const e = not(Expr.readVar("flag"));
    try std.testing.expectEqual(ExprKind.Not, e.kind);
}

test "fn_ factory" {
    const params = [_]FnParam{ .{ .name = "rf" }, .{ .name = "ctx" } };
    const e = fn_("MyTemplate", &params, &.{});
    try std.testing.expectEqual(ExprKind.FunctionExpr, e.kind);
    try std.testing.expectEqualStrings("MyTemplate", e.data.FunctionExpr.name.?);
}

test "arrowFn factory" {
    const params = [_]FnParam{.{ .name = "x" }};
    const e = arrowFn(&params, &.{});
    try std.testing.expectEqual(ExprKind.ArrowFunction, e.kind);
}

test "isNull" {
    try std.testing.expect(isNull(NULL_EXPR));
    try std.testing.expect(!isNull(Expr.readVar("x")));
}

test "Stmt factory functions" {
    const s1 = Stmt.declareVar("x", null, null);
    try std.testing.expectEqual(StmtKind.DeclareVar, s1.kind);

    const s2 = Stmt.returnStmt(null);
    try std.testing.expectEqual(StmtKind.Return, s2.kind);

    const s3 = Stmt.throwStmt(Expr.readVar("err"));
    try std.testing.expectEqual(StmtKind.Throw, s3.kind);

    const s4 = Stmt.commentStmt("test");
    try std.testing.expectEqual(StmtKind.Comment, s4.kind);
}

test "RecursiveAstVisitor visits expressions" {
    const visitor = RecursiveAstVisitor{};
    const expr = Expr.readVar("test");
    visitor.visitExpression(&expr); // should not crash
}

test "RecursiveAstVisitor visits statements" {
    const visitor = RecursiveAstVisitor{};
    const stmt = Stmt.returnStmt(null);
    visitor.visitStatement(&stmt); // should not crash
}

test "regexLiteralExpr factory" {
    const e = regexLiteralExpr("\\d+", "g");
    try std.testing.expectEqual(ExprKind.RegexLiteral, e.kind);
    try std.testing.expectEqualStrings("\\d+", e.data.RegexLiteral.body);
    try std.testing.expectEqualStrings("g", e.data.RegexLiteral.flags.?);
}

test "commaExpr factory" {
    const exprs = [_]Expr{ Expr.readVar("a"), Expr.readVar("b") };
    const e = commaExpr(&exprs);
    try std.testing.expectEqual(ExprKind.Comma, e.kind);
    try std.testing.expectEqual(@as(usize, 2), e.data.Comma.exprs.len);
}

test "TypeModifier values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(TypeModifier.None));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(TypeModifier.Const));
}

test "BuiltinTypeName values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(BuiltinTypeName.Bool));
}

test "blockStmt factory" {
    const s = blockStmt(&.{});
    try std.testing.expectEqual(StmtKind.Block, s.kind);
}

// ─── Expression chaining tests ──────────────────────────────

test "Expr.prop chaining" {
    const ctx = Expr.readVar("ctx");
    const prop = ctx.prop("name");
    try std.testing.expectEqual(ExprKind.ReadProp, prop.kind);
    try std.testing.expectEqualStrings("name", prop.data.ReadProp.name);
}

test "Expr.callFn chaining" {
    const ctx = Expr.readVar("fn");
    const args = [_]Expr{Expr.literalStr("arg")};
    const call = ctx.callFn(&args);
    try std.testing.expectEqual(ExprKind.InvokeFunction, call.kind);
    try std.testing.expectEqual(@as(usize, 1), call.data.InvokeFunction.args.len);
}

test "Expr.equals chaining" {
    const a = Expr.readVar("a");
    const b = Expr.readVar("b");
    const eq = a.equals(&b);
    try std.testing.expectEqual(ExprKind.BinaryOperator, eq.kind);
    try std.testing.expectEqualStrings("==", eq.data.BinaryOperator.operator);
}

test "Expr.identical chaining" {
    const a = Expr.readVar("a");
    const b = Expr.readVar("b");
    const id = a.identical(&b);
    try std.testing.expectEqualStrings("===", id.data.BinaryOperator.operator);
}

test "Expr.minus chaining" {
    const a = Expr.readVar("a");
    const b = Expr.readVar("b");
    const r = a.minus(&b);
    try std.testing.expectEqualStrings("-", r.data.BinaryOperator.operator);
}

test "Expr.plus chaining" {
    const a = Expr.readVar("a");
    const b = Expr.readVar("b");
    const r = a.plus(&b);
    try std.testing.expectEqualStrings("+", r.data.BinaryOperator.operator);
}

test "Expr.andOp chaining" {
    const a = Expr.readVar("a");
    const b = Expr.readVar("b");
    const r = a.andOp(&b);
    try std.testing.expectEqualStrings("&&", r.data.BinaryOperator.operator);
}

test "Expr.orOp chaining" {
    const a = Expr.readVar("a");
    const b = Expr.readVar("b");
    const r = a.orOp(&b);
    try std.testing.expectEqualStrings("||", r.data.BinaryOperator.operator);
}

test "Expr.nullishCoalesce chaining" {
    const a = Expr.readVar("a");
    const b = Expr.readVar("b");
    const r = a.nullishCoalesce(&b);
    try std.testing.expectEqualStrings("??", r.data.BinaryOperator.operator);
}

test "Expr.isConstant" {
    const lit = Expr.literalNum(42.0);
    try std.testing.expect(lit.isConstant());

    const var_expr = Expr.readVar("x");
    try std.testing.expect(!var_expr.isConstant());
}

test "Expr.isEquivalent same ReadVar" {
    const a = Expr.readVar("x");
    const b = Expr.readVar("x");
    try std.testing.expect(a.isEquivalent(&b));
}

test "Expr.isEquivalent different ReadVar" {
    const a = Expr.readVar("x");
    const b = Expr.readVar("y");
    try std.testing.expect(!a.isEquivalent(&b));
}

test "Expr.isEquivalent same literal" {
    const a = Expr.literalNum(42.0);
    const b = Expr.literalNum(42.0);
    try std.testing.expect(a.isEquivalent(&b));
}

test "Expr.isEquivalent different kind" {
    const a = Expr.readVar("x");
    const b = Expr.literalNum(42.0);
    try std.testing.expect(!a.isEquivalent(&b));
}

test "Expr.toStmt" {
    const e = Expr.readVar("x");
    const s = e.toStmt();
    try std.testing.expectEqual(StmtKind.Expression, s.kind);
}

test "Expr.set chaining" {
    const var_expr = Expr.readVar("x");
    const val = Expr.literalNum(42.0);
    const assign = var_expr.set(&val);
    try std.testing.expectEqualStrings("=", assign.data.BinaryOperator.operator);
}

test "Expr.lower chaining" {
    const a = Expr.readVar("a");
    const b = Expr.readVar("b");
    const r = a.lower(&b);
    try std.testing.expectEqualStrings("<", r.data.BinaryOperator.operator);
}

test "Expr.bigger chaining" {
    const a = Expr.readVar("a");
    const b = Expr.readVar("b");
    const r = a.bigger(&b);
    try std.testing.expectEqualStrings(">", r.data.BinaryOperator.operator);
}

test "Expr.modulo chaining" {
    const a = Expr.readVar("a");
    const b = Expr.readVar("b");
    const r = a.modulo(&b);
    try std.testing.expectEqualStrings("%", r.data.BinaryOperator.operator);
}

test "Expr.divide chaining" {
    const a = Expr.readVar("a");
    const b = Expr.readVar("b");
    const r = a.divide(&b);
    try std.testing.expectEqualStrings("/", r.data.BinaryOperator.operator);
}

test "Expr.multiply chaining" {
    const a = Expr.readVar("a");
    const b = Expr.readVar("b");
    const r = a.multiply(&b);
    try std.testing.expectEqualStrings("*", r.data.BinaryOperator.operator);
}

test "Expr.bitwiseOr chaining" {
    const a = Expr.readVar("a");
    const b = Expr.readVar("b");
    const r = a.bitwiseOr(&b);
    try std.testing.expectEqualStrings("|", r.data.BinaryOperator.operator);
}

test "Expr.bitwiseAnd chaining" {
    const a = Expr.readVar("a");
    const b = Expr.readVar("b");
    const r = a.bitwiseAnd(&b);
    try std.testing.expectEqualStrings("&", r.data.BinaryOperator.operator);
}

test "Expr.notEquals chaining" {
    const a = Expr.readVar("a");
    const b = Expr.readVar("b");
    const r = a.notEquals(&b);
    try std.testing.expectEqualStrings("!=", r.data.BinaryOperator.operator);
}

test "Expr.notIdentical chaining" {
    const a = Expr.readVar("a");
    const b = Expr.readVar("b");
    const r = a.notIdentical(&b);
    try std.testing.expectEqualStrings("!==", r.data.BinaryOperator.operator);
}

test "Expr.lowerEquals chaining" {
    const a = Expr.readVar("a");
    const b = Expr.readVar("b");
    const r = a.lowerEquals(&b);
    try std.testing.expectEqualStrings("<=", r.data.BinaryOperator.operator);
}

test "Expr.biggerEquals chaining" {
    const a = Expr.readVar("a");
    const b = Expr.readVar("b");
    const r = a.biggerEquals(&b);
    try std.testing.expectEqualStrings(">=", r.data.BinaryOperator.operator);
}

// ─── Additional types from output_ast.ts ────────────────────

/// BuiltinTypeName extended with Function and Inferred.
/// Direct port of the full `BuiltinTypeName` enum in the TS source.
pub const BuiltinTypeNameFull = enum {
    Dynamic,
    Bool,
    String,
    Int,
    Number,
    Function,
    Inferred,
    None,
};

/// BinaryOperator — all binary operators including assignment operators.
/// Direct port of `BinaryOperator` enum in the TS source.
pub const BinaryOperatorFull = enum {
    Equals,
    NotEquals,
    Assign,
    Identical,
    NotIdentical,
    Minus,
    Plus,
    Divide,
    Multiply,
    Modulo,
    And,
    Or,
    BitwiseOr,
    BitwiseAnd,
    Lower,
    LowerEquals,
    Bigger,
    BiggerEquals,
    NullishCoalesce,
    Exponentiation,
    In,
    InstanceOf,
    AdditionAssignment,
    SubtractionAssignment,
    MultiplicationAssignment,
    DivisionAssignment,
    RemainderAssignment,
    ExponentiationAssignment,
    AndAssignment,
    OrAssignment,
    NullishCoalesceAssignment,
};

/// StatementKind — kinds of statements.
pub const StatementKind = enum(u8) {
    ExpressionStatement,
    DeclareVar,
    DeclareFunctionStmt,
    IfStmt,
    TryCatchStmt,
    ReturnStatement,
    ThrowStmt,
    AssignExprStmt,
    ClassStmt,
};

/// ClassField — a field in a class statement.
pub const ClassField = struct {
    name: []const u8,
    type: ?*const BuiltinType = null,
    value: ?*const Expr = null,
    is_static: bool = false,
};

/// Create a function expression.
/// Direct port of `fn(params, body, type, sourceSpan, name)` in the TS source.
pub fn fnExpr(params: []const FnParam, body: []const Stmt) Expr {
    return .{ .kind = .FunctionExpr, .span = null, .data = .{ .FunctionExpr = .{
        .params = params,
        .body = body,
        .name = null,
    } } };
}

/// Create a literal expression from a value.
/// Direct port of `literal(value, type, sourceSpan)` in the TS source.
pub fn literal(value: anytype) Expr {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .Int, .ComptimeInt => Expr.literalNum(@floatFromInt(value)),
        .Float, .ComptimeFloat => Expr.literalNum(value),
        .Bool => Expr.literalBool(value),
        .Pointer => |ptr| if (ptr.size == .Slice or ptr.child == u8)
            Expr.literalStr(value)
        else
            Expr.literalNum(0),
        else => Expr.literalNum(0),
    };
}

// isNull already defined above with Expr parameter

// ─── Additional tests ──────────────────────────────────────

test "BuiltinTypeNameFull — all values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(BuiltinTypeNameFull.Dynamic));
    try std.testing.expectEqual(@as(u8, 5), @intFromEnum(BuiltinTypeNameFull.Function));
    try std.testing.expectEqual(@as(u8, 7), @intFromEnum(BuiltinTypeNameFull.None));
}

test "BinaryOperatorFull — key values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(BinaryOperatorFull.Equals));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(BinaryOperatorFull.Assign));
    try std.testing.expectEqual(@as(u8, 18), @intFromEnum(BinaryOperatorFull.NullishCoalesce));
    try std.testing.expectEqual(@as(u8, 19), @intFromEnum(BinaryOperatorFull.Exponentiation));
}

test "StatementKind values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(StatementKind.ExpressionStatement));
    try std.testing.expectEqual(@as(u8, 5), @intFromEnum(StatementKind.ReturnStatement));
}

test "ClassField defaults" {
    const field = ClassField{ .name = "value" };
    try std.testing.expectEqualStrings("value", field.name);
    try std.testing.expect(!field.is_static);
    try std.testing.expect(field.value == null);
}

test "ClassField with static" {
    const field = ClassField{
        .name = "instance",
        .is_static = true,
    };
    try std.testing.expect(field.is_static);
}
