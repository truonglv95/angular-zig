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
        return literal(.{ .String = value });
    }

    pub fn literalNum(value: f64) Expr {
        return literal(.{ .Number = value });
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

pub const FnParam = struct {
    name: []const u8,
    type_: ?BuiltinType = null,
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

pub const StmtKind = enum(u8) {
    Expression,
    Return,
    DeclareVar,
    DeclareFunction,
    If,
    Block,
};

pub const Stmt = struct {
    kind: StmtKind,
    data: StmtData,

    pub fn expressionStmt(expr: Expr) Stmt {
        return .{ .kind = .Expression, .data = .{ .Expression = expr } };
    }

    pub fn returnStmt(expr: Expr) Stmt {
        return .{ .kind = .Return, .data = .{ .Return = .{ .value = expr } } };
    }

    pub fn declareVar(name: []const u8, value: ?Expr) Stmt {
        return .{ .kind = .DeclareVar, .data = .{ .DeclareVar = .{ .name = name, .value = value, .modifier = .Const } } };
    }
};

pub const StmtData = union(StmtKind) {
    Expression: Expr,
    Return: struct { value: ?Expr },
    DeclareVar: struct {
        name: []const u8,
        value: ?Expr,
        type_: ?BuiltinType = null,
        modifier: VarModifier = .Const,
    },
    DeclareFunction: struct {
        name: []const u8,
        params: []const FnParam,
        body: []const Stmt,
    },
    If: struct {
        condition: Expr,
        then_case: []const Stmt,
        else_case: ?[]const Stmt,
    },
    Block: struct { statements: []const Stmt },
};

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
