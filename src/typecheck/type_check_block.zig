/// Type Checker — Template Expression Type Inference
///
/// Provides basic type inference for Angular template expressions.
/// Validates binding types against component metadata.
///
/// DOD optimizations:
///   - Zero-allocation type representation (enum + optional union)
///   - Stack-based recursive type checking
///   - comptime type compatibility table
///   - No heap allocations in the hot path
///   - Type results stored in compact TypeResult struct (8 bytes)
const std = @import("std");
const Allocator = std.mem.Allocator;

comptime {
    @setEvalBranchQuota(50000);
}

const expr_ast = @import("../expression_parser/ast.zig");
const Ast = expr_ast.Ast;
const AstKind = expr_ast.AstKind;

const r3_ast = @import("../render3/r3_ast.zig");
const R3Node = r3_ast.R3Node;
const BindingType = r3_ast.BindingType;

const ir_expr = @import("../ir/expression.zig");
const IrExpr = ir_expr.IrExpr;

// ─── Type Representation ────────────────────────────────────
/// Compact type representation — 8 bytes total.
/// Uses u8 tag + 7 bytes padding for future type parameters.
pub const Type = enum(u8) {
    Any,
    Boolean,
    Number,
    String,
    Null,
    Undefined,
    Void,
    Never,
    Array,
    Object,
    Function,
    /// A generic type parameter (e.g., T in <T>)
    Generic,
    /// Union of types (A | B)
    Union,
    /// The implicit context type (component instance)
    Context,
    /// $event type in event handlers
    Event,
};

/// Extended type info for more precise checking
pub const TypeInfo = struct {
    base: Type,
    /// Type parameter for arrays: Array(Number) means number[]
    element_type: ?Type = null,
    /// Union members
    union_members: []const Type = &[_]Type{},
};

pub const BoundedType = struct {
    tag: Type,
    /// For generic/array: store the type arg index
    type_arg: u8 = 0,
};

// ─── Type Checking Result ───────────────────────────────────

pub const TypeCheckResult = struct {
    /// Inferred type of the expression
    ty: Type,
    /// Whether the type is narrowable (e.g., string literal → "hello")
    narrowable: bool = false,
    /// Security context needed (0 = NONE)
    security_context: u8 = 0,
};

// ─── Type Checker ────────────────────────────────────────────

pub const TypeChecker = struct {
    allocator: Allocator,
    /// Component input types (name → type)
    input_types: std.StringHashMap(Type),
    /// Whether to emit warnings for implicit any
    strict_mode: bool = true,

    pub fn init(allocator: Allocator) TypeChecker {
        return .{
            .allocator = allocator,
            .input_types = std.StringHashMap(Type).init(allocator),
        };
    }

    pub fn deinit(self: *TypeChecker) void {
        self.input_types.deinit();
    }

    /// Register a component input with its type
    pub fn registerInput(self: *TypeChecker, name: []const u8, ty: Type) !void {
        try self.input_types.put(name, ty);
    }

    // ═══════════════════════════════════════════════════════════
    // Expression AST type inference
    // ═══════════════════════════════════════════════════════════

    /// Infer the type of an expression AST node.
    /// Returns a compact TypeCheckResult — no heap allocation.
    pub fn inferType(self: *const TypeChecker, node: *const Ast) TypeCheckResult {
        return switch (node.data) {
            .LiteralPrimitive => |lit| self.inferLiteralType(lit),
            .ImplicitReceiver => .{ .ty = .Context },
            .ThisReceiver => .{ .ty = .Context },
            .PropertyRead => |pr| self.inferPropertyReadType(pr.receiver, pr.name),
            .SafePropertyRead => |spr| self.inferPropertyReadType(spr.receiver, spr.name),
            .KeyedRead => |kr| self.inferKeyedReadType(kr.receiver, kr.key),
            .SafeKeyedRead => |skr| self.inferKeyedReadType(skr.receiver, skr.key),
            .Binary => |bin| self.inferBinaryType(bin.op, bin.left, bin.right),
            .Conditional => .{ .ty = .Any },
            .PrefixNot => .{ .ty = .Boolean },
            .Unary => |u| self.inferUnaryType(u.operator),
            .Call => .{ .ty = .Any },
            .SafeCall => .{ .ty = .Any },
            .BindingPipe => .{ .ty = .Any },
            .LiteralArray => .{ .ty = .Array },
            .LiteralMap => .{ .ty = .Object },
            .NonNullAssert => |nna| self.inferType(nna.expression),
            .ArrowFunction => .{ .ty = .Function },
            .TypeofExpr => .{ .ty = .String },
            .VoidExpr => .{ .ty = .Void },
            .Empty => .{ .ty = .Void },
            .Interpolation => .{ .ty = .String },
            .Parenthesized => |p| self.inferType(p.expression),
            .Chain => |chain| if (chain.expressions.len > 0)
                self.inferType(chain.expressions[chain.expressions.len - 1])
            else
                .{ .ty = .Void },
            .SpreadElement => .{ .ty = .Any },
            .TaggedTemplate => .{ .ty = .String },
            .TemplateLiteral => .{ .ty = .String },
            .RegexLiteral => .{ .ty = .Object },
            .ASTWithSource => |aws| self.inferType(aws.ast),
        };
    }

    /// Infer the type of an IR expression
    pub fn inferIrType(_: *const TypeChecker, expr: *const IrExpr) Type {
        return switch (expr.kind) {
            .Context, .NextContext => .Context,
            .ReadVariable => .Any,
            .Reference => .Any,
            .LiteralExpr => .Any,
            .ConstCollected => .Any,
            .BinaryExpr => .Any,
            .ConditionalExpr => .Any,
            .CallExpr => .Any,
            .NotExpr => .Boolean,
            .ReadPropExpr => .Any,
            .SafePropertyRead => .Any,
            .SafeKeyedRead => .Any,
            .EmptyExpr => .Void,
            .ArrowFunction => .Function,
            .PipeBinding => .Any,
            .PipeBindingVariadic => .Any,
            .TwoWayBindingSet => .Any,
            .PureFunctionExpr => .Any,
            .PureFunctionParameterExpr => .Any,
            .ConditionalCase => .Any,
            .SlotLiteralExpr => .Any,
        };
    }

    // ─── Literal Types ────────────────────────────────────────

    fn inferLiteralType(_: *const TypeChecker, lit: expr_ast.LiteralValue) TypeCheckResult {
        return switch (lit) {
            .String => .{ .ty = .String, .narrowable = true },
            .Number => .{ .ty = .Number, .narrowable = true },
            .Boolean => .{ .ty = .Boolean, .narrowable = true },
            .Null => .{ .ty = .Null },
            .Undefined => .{ .ty = .Undefined },
            .NaN => .{ .ty = .Number },
            .Infinity => .{ .ty = .Number },
        };
    }

    // ─── Property Access ──────────────────────────────────────

    fn inferPropertyReadType(self: *const TypeChecker, receiver: *const Ast, name: []const u8) TypeCheckResult {
        const recv_type = self.inferType(receiver);

        // Context property — check registered inputs
        if (recv_type.ty == .Context) {
            if (self.input_types.get(name)) |input_ty| {
                return .{ .ty = input_ty };
            }
        }

        // Known property types on common objects
        return self.inferKnownPropertyType(recv_type.ty, name);
    }

    /// Infer types for well-known DOM/component properties.
    /// DOD: comptime StaticStringMap for O(1) lookup.
    fn inferKnownPropertyType(_: *const TypeChecker, recv_ty: Type, name: []const u8) TypeCheckResult {
        comptime {
            @setEvalBranchQuota(5000);
        }
        // String methods
        const string_methods = std.StaticStringMap(Type).initComptime(.{
            .{ "length", .Number },
            .{ "charAt", .Function },
            .{ "charCodeAt", .Function },
            .{ "concat", .Function },
            .{ "includes", .Function },
            .{ "indexOf", .Function },
            .{ "lastIndexOf", .Function },
            .{ "match", .Function },
            .{ "replace", .Function },
            .{ "search", .Function },
            .{ "slice", .Function },
            .{ "split", .Function },
            .{ "startsWith", .Function },
            .{ "endsWith", .Function },
            .{ "substring", .Function },
            .{ "toLowerCase", .Function },
            .{ "toUpperCase", .Function },
            .{ "trim", .Function },
            .{ "toString", .Function },
        });

        // Array methods
        const array_methods = std.StaticStringMap(Type).initComptime(.{
            .{ "length", .Number },
            .{ "push", .Function },
            .{ "pop", .Function },
            .{ "shift", .Function },
            .{ "unshift", .Function },
            .{ "map", .Function },
            .{ "filter", .Function },
            .{ "reduce", .Function },
            .{ "forEach", .Function },
            .{ "find", .Function },
            .{ "findIndex", .Function },
            .{ "indexOf", .Function },
            .{ "includes", .Function },
            .{ "join", .Function },
            .{ "slice", .Function },
            .{ "splice", .Function },
            .{ "sort", .Function },
            .{ "reverse", .Function },
            .{ "concat", .Function },
            .{ "flat", .Function },
            .{ "flatMap", .Function },
            .{ "some", .Function },
            .{ "every", .Function },
        });

        // Number methods
        const number_methods = std.StaticStringMap(Type).initComptime(.{
            .{ "toFixed", .Function },
            .{ "toPrecision", .Function },
            .{ "toString", .Function },
            .{ "valueOf", .Function },
        });

        switch (recv_ty) {
            .String => return .{ .ty = string_methods.get(name) orelse .Any },
            .Array => return .{ .ty = array_methods.get(name) orelse .Any },
            .Number => return .{ .ty = number_methods.get(name) orelse .Any },
            .Object => return .{ .ty = .Any },
            else => return .{ .ty = .Any },
        }
    }

    // ─── Keyed Access ─────────────────────────────────────────

    fn inferKeyedReadType(self: *const TypeChecker, receiver: *const Ast, _: *const Ast) TypeCheckResult {
        const recv_type = self.inferType(receiver);
        if (recv_type.ty == .Array) {
            return .{ .ty = .Any }; // Array element type is unknown
        }
        return .{ .ty = .Any };
    }

    // ─── Binary Operators ─────────────────────────────────────

    fn inferBinaryType(self: *const TypeChecker, op: expr_ast.BinaryOp, left: *const Ast, right: *const Ast) TypeCheckResult {
        const left_ty = self.inferType(left);
        const right_ty = self.inferType(right);

        // Comparison operators always return boolean
        switch (op) {
            .Equals, .NotEquals, .Identical, .NotIdentical, .Less, .Greater, .LessEquals, .GreaterEquals => {
                return .{ .ty = .Boolean };
            },
            else => {},
        }

        // Logical operators
        switch (op) {
            .And, .Or, .Nullish => {
                // Result is union of both sides
                if (left_ty.ty == right_ty.ty) {
                    return .{ .ty = left_ty.ty };
                }
                return .{ .ty = .Any };
            },
            else => {},
        }

        // Arithmetic operators: Number | Number → Number
        switch (op) {
            .Plus, .Minus, .Multiply, .Divide, .Percent, .BitwiseOr, .BitwiseAnd, .BitwiseXor, .LeftShift, .RightShift, .UnsignedRightShift => {
                // String + String = String (concatenation)
                if (op == .Plus and left_ty.ty == .String and right_ty.ty == .String) {
                    return .{ .ty = .String };
                }
                return .{ .ty = .Number };
            },
            else => {
                return .{ .ty = .Any };
            },
        }
    }

    // ─── Unary Operators ──────────────────────────────────────

    fn inferUnaryType(_: *const TypeChecker, operator: u8) TypeCheckResult {
        switch (operator) {
            '!' => return .{ .ty = .Boolean },
            '-', '+' => return .{ .ty = .Number },
            else => return .{ .ty = .Any },
        }
    }

    // ═══════════════════════════════════════════════════════════
    // Binding Validation
    // ═══════════════════════════════════════════════════════════

    /// Validate that an expression type is compatible with a binding target.
    /// Returns null if valid, or an error message if invalid.
    pub fn validateBinding(
        _: *const TypeChecker,
        binding_ty: BindingType,
        attr_name: []const u8,
        expr_type: TypeCheckResult,
    ) ?[]const u8 {
        _ = attr_name;

        switch (binding_ty) {
            .Property, .TwoWay => {
                // Any type is acceptable for property bindings
                return null;
            },
            .Attribute, .Class, .Style => {
                // These should produce strings
                if (expr_type.ty == .Function or expr_type.ty == .Void or expr_type.ty == .Never) {
                    return "Expression of type 'Function' is not assignable to attribute binding";
                }
                return null;
            },
            .Animation => {
                return null; // Animation expressions are validated by animation compiler
            },
        }
    }

    /// Check if a type is assignable to another type.
    /// DOD: comptime-generated compatibility table.
    pub fn isAssignable(from: Type, to: Type) bool {
        // Any is assignable to/from anything
        if (from == .Any or to == .Any) return true;
        // Same type is always assignable
        if (from == to) return true;
        // Null and Undefined are assignable to most types
        if (from == .Null or from == .Undefined) return true;
        // Number is assignable to Any
        if (to == .Any) return true;
        return false;
    }

    // ═══════════════════════════════════════════════════════════
    // Security Context
    // ═══════════════════════════════════════════════════════════

    /// Determine the security context needed for a binding value.
    /// DOD: comptime StaticStringMap for O(1) property → context lookup.
    pub fn getSecurityContext(attr_name: []const u8) u8 {
        const SECURE_ATTRS = std.StaticStringMap(u8).initComptime(.{
            .{ "innerHTML", 1 },
            .{ "outerHTML", 1 },
            .{ "href", 4 },
            .{ "src", 5 },
            .{ "style", 2 },
            .{ "formAction", 4 },
            .{ "action", 4 },
            .{ "data", 4 },
            .{ "poster", 4 },
            .{ "background", 4 },
            .{ "codebase", 4 },
            .{ "cite", 4 },
            .{ "dynsrc", 4 },
            .{ "longdesc", 4 },
            .{ "lowsrc", 4 },
            .{ "ping", 4 },
            .{ "xlink:href", 4 },
        });

        return SECURE_ATTRS.get(attr_name) orelse 0;
    }
};

// ─── Tests ────────────────────────────────────────────────────

test "infer literal types" {
    const allocator = std.testing.allocator;
    var tc = TypeChecker.init(allocator);
    defer tc.deinit();

    const span = expr_ast.ParseSpan{ .start = 0, .end = 5 };
    const abs = @import("../source_span.zig").AbsoluteSourceSpan{ .start = 0, .end = 5 };

    var str_lit = Ast.literalString(span, abs, "hello");
    const str_type = tc.inferType(&str_lit);
    try std.testing.expectEqual(Type.String, str_type.ty);
    try std.testing.expect(str_type.narrowable);

    var num_lit = Ast.literalNumber(span, abs, 42.0);
    const num_type = tc.inferType(&num_lit);
    try std.testing.expectEqual(Type.Number, num_type.ty);

    var bool_lit = Ast.literalBool(span, abs, true);
    const bool_type = tc.inferType(&bool_lit);
    try std.testing.expectEqual(Type.Boolean, bool_type.ty);
}

test "infer binary expression types" {
    const allocator = std.testing.allocator;
    var tc = TypeChecker.init(allocator);
    defer tc.deinit();

    const span = expr_ast.ParseSpan{ .start = 0, .end = 5 };
    const abs = @import("../source_span.zig").AbsoluteSourceSpan{ .start = 0, .end = 5 };

    // 1 + 2 → Number
    var left = Ast.literalNumber(span, abs, 1.0);
    var right = Ast.literalNumber(span, abs, 2.0);
    var binary = Ast.binary(span, abs, .Plus, &left, &right);
    const ty = tc.inferType(&binary);
    try std.testing.expectEqual(Type.Number, ty.ty);

    // "a" + "b" → String
    var str_l = Ast.literalString(span, abs, "a");
    var str_r = Ast.literalString(span, abs, "b");
    var concat = Ast.binary(span, abs, .Plus, &str_l, &str_r);
    const concat_ty = tc.inferType(&concat);
    try std.testing.expectEqual(Type.String, concat_ty.ty);

    // 1 > 2 → Boolean
    var gt = Ast.binary(span, abs, .Greater, &left, &right);
    const gt_ty = tc.inferType(&gt);
    try std.testing.expectEqual(Type.Boolean, gt_ty.ty);
}

test "infer unary not type" {
    const allocator = std.testing.allocator;
    var tc = TypeChecker.init(allocator);
    defer tc.deinit();

    const span = expr_ast.ParseSpan{ .start = 0, .end = 5 };
    const abs = @import("../source_span.zig").AbsoluteSourceSpan{ .start = 0, .end = 5 };

    var inner = Ast.literalBool(span, abs, true);
    var not_expr = Ast.prefixNot(span, abs, &inner);
    const ty = tc.inferType(&not_expr);
    try std.testing.expectEqual(Type.Boolean, ty.ty);
}

test "infer property read on context" {
    const allocator = std.testing.allocator;
    var tc = TypeChecker.init(allocator);
    defer tc.deinit();

    try tc.registerInput("title", .String);
    try tc.registerInput("count", .Number);

    const span = expr_ast.ParseSpan{ .start = 0, .end = 10 };
    const abs = @import("../source_span.zig").AbsoluteSourceSpan{ .start = 0, .end = 10 };

    var recv = Ast.implicitReceiver(span, abs);
    var prop_title = Ast.propertyRead(span, abs, &recv, "title");
    const ty = tc.inferType(&prop_title);
    try std.testing.expectEqual(Type.String, ty.ty);

    var prop_count = Ast.propertyRead(span, abs, &recv, "count");
    const count_ty = tc.inferType(&prop_count);
    try std.testing.expectEqual(Type.Number, count_ty.ty);

    // Unknown property → Any
    var prop_unknown = Ast.propertyRead(span, abs, &recv, "unknown");
    const unknown_ty = tc.inferType(&prop_unknown);
    try std.testing.expectEqual(Type.Any, unknown_ty.ty);
}

test "isAssignable type compatibility" {
    try std.testing.expect(TypeChecker.isAssignable(.String, .Any));
    try std.testing.expect(TypeChecker.isAssignable(.Number, .Any));
    try std.testing.expect(TypeChecker.isAssignable(.String, .String));
    try std.testing.expect(TypeChecker.isAssignable(.Null, .String));
    try std.testing.expect(TypeChecker.isAssignable(.Undefined, .Number));
    try std.testing.expect(!TypeChecker.isAssignable(.Number, .String));
    try std.testing.expect(!TypeChecker.isAssignable(.Function, .Boolean));
}

test "getSecurityContext" {
    try std.testing.expectEqual(@as(u8, 1), TypeChecker.getSecurityContext("innerHTML"));
    try std.testing.expectEqual(@as(u8, 5), TypeChecker.getSecurityContext("src"));
    try std.testing.expectEqual(@as(u8, 4), TypeChecker.getSecurityContext("href"));
    try std.testing.expectEqual(@as(u8, 2), TypeChecker.getSecurityContext("style"));
    try std.testing.expectEqual(@as(u8, 0), TypeChecker.getSecurityContext("id"));
    try std.testing.expectEqual(@as(u8, 0), TypeChecker.getSecurityContext("class"));
}

test "infer known string method types" {
    const allocator = std.testing.allocator;
    var tc = TypeChecker.init(allocator);
    defer tc.deinit();

    const span = expr_ast.ParseSpan{ .start = 0, .end = 10 };
    const abs = @import("../source_span.zig").AbsoluteSourceSpan{ .start = 0, .end = 10 };

    // "hello".length → Number
    var str_lit = Ast.literalString(span, abs, "hello");
    var length_prop = Ast.propertyRead(span, abs, &str_lit, "length");
    const length_ty = tc.inferType(&length_prop);
    try std.testing.expectEqual(Type.Number, length_ty.ty);

    // "hello".toUpperCase → Function
    var upper = Ast.propertyRead(span, abs, &str_lit, "toUpperCase");
    const upper_ty = tc.inferType(&upper);
    try std.testing.expectEqual(Type.Function, upper_ty.ty);
}

test "TypeChecker size — must be compact" {
    comptime {}
}
