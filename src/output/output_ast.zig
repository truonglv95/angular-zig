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
        return .{ .kind = .ReadProp, .span = null, .data = .{ .ReadProp = .{ .receiver = receiver, .name = name } } };
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
    Builtin, Expression, Array, Map, Transplanted,
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
    Minus, Plus, BitwiseNot, LogicalNot,
};

/// BinaryOperator — binary operators matching Angular's output_ast.
pub const BinaryOperator = enum(u8) {
    Equals, NotEquals, Identical, NotIdentical,
    Less, LessEquals, Greater, GreaterEquals,
    Plus, Minus, Multiply, Divide, Modulo,
    BitwiseAnd, BitwiseOr, BitwiseXor, BitwiseShiftLeft, BitwiseShiftRight,
    LogicalAnd, LogicalOr, NullishCoalescing,
    Comma,
};

/// Convert BinaryOperator to JS string.
pub fn binaryOperatorToString(op: BinaryOperator) []const u8 {
    return switch (op) {
        .Equals => "==", .NotEquals => "!=", .Identical => "===", .NotIdentical => "!==",
        .Less => "<", .LessEquals => "<=", .Greater => ">", .GreaterEquals => ">=",
        .Plus => "+", .Minus => "-", .Multiply => "*", .Divide => "/", .Modulo => "%",
        .BitwiseAnd => "&", .BitwiseOr => "|", .BitwiseXor => "^",
        .BitwiseShiftLeft => "<<", .BitwiseShiftRight => ">>",
        .LogicalAnd => "&&", .LogicalOr => "||", .NullishCoalescing => "??",
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
    Description, See, Deprecated, Link, Param, Returns, Type,
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
    DeclareVar, DeclareFunction, Expression, Return, If, Throw, Comment, TryCatch, Block,
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
    return .{ .kind = .TypeofExpr, .span = null, .data = .{ .TypeofExpr = .{ .expr = expr } } };
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
    return .{ .kind = .NotExpr, .span = null, .data = .{ .NotExpr = .{ .expression = expr } } };
}

/// Create a not expression.
pub fn not(expr: Expr) Expr {
    return .{ .kind = .NotExpr, .span = null, .data = .{ .NotExpr = .{ .expression = expr } } };
}

/// Create a function expression.
pub fn fn_(name: ?[]const u8, params: []const FnParam, body: []const Stmt) Expr {
    return .{ .kind = .FunctionExpr, .span = null, .data = .{ .FunctionExpr = .{ .name = name, .params = params, .body = body } } };
}

/// Create an arrow function expression.
pub fn arrowFn(params: []const FnParam, body: []const Stmt) Expr {
    return .{ .kind = .ArrowFunction, .span = null, .data = .{ .ArrowFunction = .{ .params = params, .body = body } } };
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
    if (@typeInfo(T) == .Null) return .{ .kind = .LiteralExpr, .span = null, .data = .{ .LiteralExpr = .{ .Null = {} } } };
    return .{ .kind = .LiteralExpr, .span = null, .data = .{ .LiteralExpr = .{ .Null = {} } } };
}

/// Create a localized string expression.
pub fn localizedString(allocator: std.mem.Allocator, pieces: []const MessagePiece, expressions: []const Expr) !Expr {
    _ = allocator;
    _ = pieces;
    _ = expressions;
    return .{ .kind = .LiteralExpr, .span = null, .data = .{ .LiteralExpr = .{ .Null = {} } } };
}

/// Check if an expression is null.
pub fn isNull(exp: Expr) bool {
    return exp.kind == .LiteralExpr and exp.data.LiteralExpr == .Null;
}

/// Predefined null expression.
pub const NULL_EXPR: Expr = .{ .kind = .LiteralExpr, .span = null, .data = .{ .LiteralExpr = .{ .Null = {} } } };
pub const TYPED_NULL_EXPR: Expr = NULL_EXPR;

// ─── RecursiveAstVisitor ────────────────────────────────────

/// RecursiveAstVisitor — visits all expressions and statements recursively.
pub const RecursiveAstVisitor = struct {
    pub fn visitExpression(self: *const RecursiveAstVisitor, expr: *const Expr) void {
        _ = self;
        _ = expr;
        // DOD: dispatch based on expr.kind and recurse into children
    }

    pub fn visitStatement(self: *const RecursiveAstVisitor, stmt: *const Stmt) void {
        _ = self;
        _ = stmt;
        // DOD: dispatch based on stmt.kind and recurse into children
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
