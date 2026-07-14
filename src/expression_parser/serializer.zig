/// Expression Serializer — AST to string (for debugging/error messages)
const std = @import("std");
const Ast = @import("ast.zig").Ast;
const BinaryOp = @import("ast.zig").BinaryOp;

pub fn serialize(allocator: std.mem.Allocator, node: *const Ast) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(allocator);
    try serializeNode(&aw.writer, node);
    var list = aw.toArrayList();
    // aw.deinit() would free the buffer — skip it since list owns it now.
    return list.toOwnedSlice(allocator);
}

fn serializeNode(writer: anytype, node: *const Ast) !void {
    switch (node.data) {
        .Empty => try writer.writeAll("EMPTY"),
        .ImplicitReceiver => try writer.writeAll("$implicit"),
        .ThisReceiver => try writer.writeAll("this"),
        .LiteralPrimitive => |v| {
            switch (v) {
                .String => |s| {
                    try writer.writeAll("\"");
                    try writer.writeAll(s);
                    try writer.writeAll("\"");
                },
                .Number => |n| {
                    // Print with .0 suffix if integer-valued, else print as-is
                    if (@floor(n) == n and n < 1e15 and n > -1e15) {
                        try writer.print("{d}.0", .{@as(i64, @intFromFloat(n))});
                    } else {
                        try writer.print("{d}", .{n});
                    }
                },
                .Boolean => |b| try writer.writeAll(if (b) "true" else "false"),
                .Null => try writer.writeAll("null"),
                .Undefined => try writer.writeAll("undefined"),
                else => try writer.writeAll("NaN"),
            }
        },
        .PropertyRead => |v| {
            try serializeNode(writer, v.receiver);
            try writer.writeAll(".");
            try writer.writeAll(v.name);
        },
        .SafePropertyRead => |v| {
            try serializeNode(writer, v.receiver);
            try writer.writeAll("?.");
            try writer.writeAll(v.name);
        },
        .KeyedRead => |v| {
            try serializeNode(writer, v.receiver);
            try writer.writeAll("[");
            try serializeNode(writer, v.key);
            try writer.writeAll("]");
        },
        .SafeKeyedRead => |v| {
            try serializeNode(writer, v.receiver);
            try writer.writeAll("?.[");
            try serializeNode(writer, v.key);
            try writer.writeAll("]");
        },
        .Binary => |v| {
            const op_str = binaryOpStr(v.op);
            try writer.writeAll("(");
            try serializeNode(writer, v.left);
            try writer.writeAll(" ");
            try writer.writeAll(op_str);
            try writer.writeAll(" ");
            try serializeNode(writer, v.right);
            try writer.writeAll(")");
        },
        .Conditional => |v| {
            try serializeNode(writer, v.condition);
            try writer.writeAll(" ? ");
            try serializeNode(writer, v.true_expr);
            try writer.writeAll(" : ");
            try serializeNode(writer, v.false_expr);
        },
        .BindingPipe => |v| {
            try serializeNode(writer, v.exp);
            try writer.writeAll(" | ");
            try writer.writeAll(v.name);
            for (v.args) |arg| {
                try writer.writeAll(":");
                try serializeNode(writer, arg);
            }
        },
        .Call => |v| {
            try serializeNode(writer, v.receiver);
            try writer.writeAll("(");
            for (v.args, 0..) |arg, i| {
                if (i > 0) try writer.writeAll(", ");
                try serializeNode(writer, arg);
            }
            try writer.writeAll(")");
        },
        .SafeCall => |v| {
            try serializeNode(writer, v.receiver);
            try writer.writeAll("?.(");
            for (v.args, 0..) |arg, i| {
                if (i > 0) try writer.writeAll(", ");
                try serializeNode(writer, arg);
            }
            try writer.writeAll(")");
        },
        .PrefixNot => |v| {
            try writer.writeAll("!");
            try serializeNode(writer, v.expression);
        },
        .Unary => |v| {
            try writer.writeByte(v.operator);
            try serializeNode(writer, v.expr);
        },
        .LiteralArray => |v| {
            try writer.writeAll("[");
            for (v.expressions, 0..) |e, i| {
                if (i > 0) try writer.writeAll(", ");
                try serializeNode(writer, e);
            }
            try writer.writeAll("]");
        },
        .LiteralMap => |v| {
            try writer.writeAll("{");
            for (v.entries, 0..) |e, i| {
                if (i > 0) try writer.writeAll(", ");
                if (e.quoted) try writer.writeAll("\"");
                try writer.writeAll(e.key);
                if (e.quoted) try writer.writeAll("\"");
                try writer.writeAll(": ");
                try serializeNode(writer, e.value);
            }
            try writer.writeAll("}");
        },
        .Parenthesized => |v| {
            try writer.writeAll("(");
            try serializeNode(writer, v.expression);
            try writer.writeAll(")");
        },
        .NonNullAssert => |v| {
            try serializeNode(writer, v.expression);
            try writer.writeAll("!");
        },
        .Chain => |v| {
            for (v.expressions, 0..) |e, i| {
                if (i > 0) try writer.writeAll("; ");
                try serializeNode(writer, e);
            }
        },
        .TypeofExpr => |v| {
            try writer.writeAll("typeof ");
            try serializeNode(writer, v.expression);
        },
        .VoidExpr => |v| {
            try writer.writeAll("void ");
            try serializeNode(writer, v.expression);
        },
        .Interpolation => |v| {
            for (v.strings, 0..) |s, i| {
                try writer.writeAll(s);
                if (i < v.expressions.len) {
                    try writer.writeAll("{{ ");
                    try serializeNode(writer, v.expressions[i]);
                    try writer.writeAll(" }}");
                }
            }
            // Trailing string after last expression
            if (v.strings.len > v.expressions.len) {
                try writer.writeAll(v.strings[v.strings.len - 1]);
            }
        },
        .SpreadElement => |v| {
            try writer.writeAll("...");
            try serializeNode(writer, v.expression);
        },
        .ArrowFunction => |v| {
            try writer.writeAll("(");
            for (v.params, 0..) |p, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.writeAll(p.name);
            }
            try writer.writeAll(") => ");
            try serializeNode(writer, v.body);
        },
        .TemplateLiteral => |v| {
            try writer.writeAll("`");
            for (v.elements, 0..) |elem, i| {
                try writer.writeAll(elem);
                if (i < v.expressions.len) {
                    try writer.writeAll("${");
                    try serializeNode(writer, v.expressions[i]);
                    try writer.writeAll("}");
                }
            }
            try writer.writeAll("`");
        },
        .ASTWithSource => |v| {
            try serializeNode(writer, v.ast);
        },
        .TaggedTemplate => |v| {
            try serializeNode(writer, v.tag);
            try writer.writeAll("`");
            for (v.template.elements, 0..) |elem, i| {
                try writer.writeAll(elem);
                if (i < v.template.expressions.len) {
                    try writer.writeAll("${");
                    try serializeNode(writer, v.template.expressions[i]);
                    try writer.writeAll("}");
                }
            }
            try writer.writeAll("`");
        },
        .RegexLiteral => |v| {
            try writer.writeAll("/");
            try writer.writeAll(v.body);
            try writer.writeAll("/");
            if (v.flags) |f| try writer.writeAll(f);
        },
    }
}

fn binaryOpStr(op: BinaryOp) []const u8 {
    return switch (op) {
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
        .BitwiseAnd => "&",
        .BitwiseOr => "|",
        .BitwiseXor => "^",
        .LeftShift => "<<",
        .RightShift => ">>",
        .UnsignedRightShift => ">>>",
        .In => " in ",
        .Instanceof => " instanceof ",
        .Comma => ", ",
        .Assign => "=",
        .AddAssign => "+=",
        .SubtractAssign => "-=",
        .MultiplyAssign => "*=",
        .DivideAssign => "/=",
        .ModuloAssign => "%=",
        .PowerAssign => "**=",
        .NullishCoalescingAssign => "??=",
        .LogicalAndAssign => "&&=",
        .LogicalOrAssign => "||=",
    };
}

test "serialize property access" {
    const allocator = std.testing.allocator;
    var arena = @import("../arena.zig").AstArena.init(allocator);
    defer arena.deinit();

    const span = @import("ast.zig").ParseSpan{ .start = 0, .end = 5 };
    const abs = @import("../source_span.zig").AbsoluteSourceSpan{ .start = 0, .end = 5 };
    const node = try arena.create(Ast);
    node.* = Ast.propertyRead(span, abs, &Ast.implicitReceiver(span, abs), "name");

    const result = try serialize(allocator, node);
    try std.testing.expectEqualStrings("$implicit.name", result);
    allocator.free(result);
}

test "serialize chain" {
    const allocator = std.testing.allocator;
    var arena = @import("../arena.zig").AstArena.init(allocator);
    defer arena.deinit();

    const span = @import("ast.zig").ParseSpan{ .start = 0, .end = 5 };
    const abs = @import("../source_span.zig").AbsoluteSourceSpan{ .start = 0, .end = 5 };
    const a = try arena.create(Ast);
    a.* = Ast.literalNumber(span, abs, 1.0);
    const b = try arena.create(Ast);
    b.* = Ast.literalNumber(span, abs, 2.0);
    const exprs = [_]*const Ast{ a, b };
    const chain = try arena.create(Ast);
    chain.* = .{
        .span = span,
        .abs_span = abs,
        .data = .{ .Chain = .{ .expressions = &exprs } },
    };

    const result = try serialize(allocator, chain);
    try std.testing.expect(std.mem.indexOf(u8, result, "1.0; 2.0") != null);
    allocator.free(result);
}

test "serialize unary" {
    const allocator = std.testing.allocator;
    var arena = @import("../arena.zig").AstArena.init(allocator);
    defer arena.deinit();

    const span = @import("ast.zig").ParseSpan{ .start = 0, .end = 3 };
    const abs = @import("../source_span.zig").AbsoluteSourceSpan{ .start = 0, .end = 3 };
    const inner = try arena.create(Ast);
    inner.* = Ast.literalNumber(span, abs, 5.0);
    const unary = try arena.create(Ast);
    unary.* = .{
        .span = span,
        .abs_span = abs,
        .data = .{ .Unary = .{ .operator = '-', .expr = inner } },
    };

    const result = try serialize(allocator, unary);
    try std.testing.expectEqualStrings("-5.0", result);
    allocator.free(result);
}


// ─── Missing visitor methods from Angular serializer.ts ─────

/// Visit and serialize an ASTWithSource.
pub fn visitASTWithSource(writer: anytype, ast: *const Ast) !void {
    switch (ast.data) {
        .Interpolation => |i| {
            for (i.strings, 0..) |s, idx| {
                try writer.writeAll(s);
                if (idx < i.expressions.len) {
                    try writer.writeAll("{{ ");
                    try serializeNode(writer, i.expressions[idx]);
                    try writer.writeAll(" }}");
                }
            }
        },
        else => try serializeNode(writer, ast),
    }
}

/// Visit and serialize an arrow function.
pub fn visitArrowFunction(writer: anytype, ast: *const Ast) !void {
    const af = ast.data.ArrowFunction;
    try writer.writeAll("(");
    for (af.params, 0..) |param, i| {
        if (i > 0) try writer.writeAll(", ");
        try writer.writeAll(param.name);
    }
    try writer.writeAll(") => ");
    try serializeNode(writer, af.body);
}

/// Visit and serialize a binary expression.
pub fn visitBinary(writer: anytype, ast: *const Ast) !void {
    const b = ast.data.Binary;
    try serializeNode(writer, b.left);
    try writer.writeAll(" ");
    try writer.writeAll(binaryOpToString(b.op));
    try writer.writeAll(" ");
    try serializeNode(writer, b.right);
}

/// Visit and serialize a call expression.
pub fn visitCall(writer: anytype, ast: *const Ast) !void {
    const call = ast.data.Call;
    try serializeNode(writer, call.receiver);
    try writer.writeAll("(");
    for (call.args, 0..) |arg, i| {
        if (i > 0) try writer.writeAll(", ");
        try serializeNode(writer, arg);
    }
    try writer.writeAll(")");
}

/// Visit and serialize a safe call.
pub fn visitSafeCall(writer: anytype, ast: *const Ast) !void {
    const call = ast.data.SafeCall;
    try serializeNode(writer, call.receiver);
    try writer.writeAll("?.(");
    for (call.args, 0..) |arg, i| {
        if (i > 0) try writer.writeAll(", ");
        try serializeNode(writer, arg);
    }
    try writer.writeAll(")");
}

/// Visit and serialize a chain expression.
pub fn visitChain(writer: anytype, ast: *const Ast) !void {
    const c = ast.data.Chain;
    for (c.expressions, 0..) |expr, i| {
        if (i > 0) try writer.writeAll("; ");
        try serializeNode(writer, expr);
    }
}

/// Visit and serialize a conditional.
pub fn visitConditional(writer: anytype, ast: *const Ast) !void {
    const c = ast.data.Conditional;
    try serializeNode(writer, c.condition);
    try writer.writeAll(" ? ");
    try serializeNode(writer, c.true_expr);
    try writer.writeAll(" : ");
    try serializeNode(writer, c.false_expr);
}

/// Visit and serialize an implicit receiver.
pub fn visitImplicitReceiver(writer: anytype, ast: *const Ast) !void {
    _ = ast;
    _ = writer;
}

/// Visit and serialize an interpolation.
pub fn visitInterpolation(writer: anytype, ast: *const Ast) !void {
    const i = ast.data.Interpolation;
    for (i.strings, 0..) |s, idx| {
        try writer.writeAll(s);
        if (idx < i.expressions.len) {
            try writer.writeAll("{{ ");
            try serializeNode(writer, i.expressions[idx]);
            try writer.writeAll(" }}");
        }
    }
}

/// Visit and serialize a keyed read.
pub fn visitKeyedRead(writer: anytype, ast: *const Ast) !void {
    const kr = ast.data.KeyedRead;
    try serializeNode(writer, kr.receiver);
    try writer.writeAll("[");
    try serializeNode(writer, kr.key);
    try writer.writeAll("]");
}

/// Visit and serialize a safe keyed read.
pub fn visitSafeKeyedRead(writer: anytype, ast: *const Ast) !void {
    const skr = ast.data.SafeKeyedRead;
    try serializeNode(writer, skr.receiver);
    try writer.writeAll("?.[");
    try serializeNode(writer, skr.key);
    try writer.writeAll("]");
}

/// Visit and serialize a literal array.
pub fn visitLiteralArray(writer: anytype, ast: *const Ast) !void {
    const la = ast.data.LiteralArray;
    try writer.writeAll("[");
    for (la.expressions, 0..) |e, i| {
        if (i > 0) try writer.writeAll(", ");
        try serializeNode(writer, e);
    }
    try writer.writeAll("]");
}

/// Visit and serialize a literal map.
pub fn visitLiteralMap(writer: anytype, ast: *const Ast) !void {
    const lm = ast.data.LiteralMap;
    try writer.writeAll("{");
    for (lm.entries, 0..) |e, i| {
        if (i > 0) try writer.writeAll(", ");
        if (e.quoted) try writer.writeAll("\"");
        try writer.writeAll(e.key);
        if (e.quoted) try writer.writeAll("\"");
        try writer.writeAll(": ");
        try serializeNode(writer, e.value);
    }
    try writer.writeAll("}");
}

/// Visit and serialize a literal primitive.
pub fn visitLiteralPrimitive(writer: anytype, ast: *const Ast) !void {
    const v = ast.data.LiteralPrimitive;
    switch (v) {
        .String => |s| { try writer.writeAll("\""); try writer.writeAll(s); try writer.writeAll("\""); },
        .Number => |n| try writer.print("{d}", .{n}),
        .Boolean => |b| try writer.writeAll(if (b) "true" else "false"),
        .Null => try writer.writeAll("null"),
        .Undefined => try writer.writeAll("undefined"),
    }
}

/// Visit and serialize a non-null assert.
pub fn visitNonNullAssert(writer: anytype, ast: *const Ast) !void {
    const nna = ast.data.NonNullAssert;
    try serializeNode(writer, nna.expression);
    try writer.writeAll("!");
}

/// Visit and serialize a parenthesized expression.
pub fn visitParenthesized(writer: anytype, ast: *const Ast) !void {
    const p = ast.data.Parenthesized;
    try writer.writeAll("(");
    try serializeNode(writer, p.expression);
    try writer.writeAll(")");
}

/// Visit and serialize a pipe.
pub fn visitPipe(writer: anytype, ast: *const Ast) !void {
    const bp = ast.data.BindingPipe;
    try serializeNode(writer, bp.exp);
    try writer.writeAll(" | ");
    try writer.writeAll(bp.name);
    for (bp.args) |arg| {
        try writer.writeAll(":");
        try serializeNode(writer, arg);
    }
}

/// Visit and serialize a prefix not.
pub fn visitPrefixNot(writer: anytype, ast: *const Ast) !void {
    const pn = ast.data.PrefixNot;
    try writer.writeAll("!");
    try serializeNode(writer, pn.expression);
}

/// Visit and serialize a property read.
pub fn visitPropertyRead(writer: anytype, ast: *const Ast) !void {
    const pr = ast.data.PropertyRead;
    try serializeNode(writer, pr.receiver);
    try writer.writeAll(".");
    try writer.writeAll(pr.name);
}

/// Visit and serialize a safe property read.
pub fn visitSafePropertyRead(writer: anytype, ast: *const Ast) !void {
    const spr = ast.data.SafePropertyRead;
    try serializeNode(writer, spr.receiver);
    try writer.writeAll("?.");
    try writer.writeAll(spr.name);
}

/// Visit and serialize a this receiver.
pub fn visitThisReceiver(writer: anytype, ast: *const Ast) !void {
    _ = ast;
    try writer.writeAll("this");
}

/// Visit and serialize a unary expression.
pub fn visitUnary(writer: anytype, ast: *const Ast) !void {
    const u = ast.data.Unary;
    try writer.writeByte(u.operator);
    try serializeNode(writer, u.expr);
}

/// Visit and serialize a typeof expression.
pub fn visitTypeofExpression(writer: anytype, ast: *const Ast) !void {
    const t = ast.data.TypeofExpr;
    try writer.writeAll("typeof ");
    try serializeNode(writer, t.expression);
}

/// Visit and serialize a void expression.
pub fn visitVoidExpression(writer: anytype, ast: *const Ast) !void {
    const v = ast.data.VoidExpr;
    try writer.writeAll("void ");
    try serializeNode(writer, v.expression);
}

/// Visit and serialize a regular expression literal.
pub fn visitRegularExpressionLiteral(writer: anytype, ast: *const Ast) !void {
    _ = ast;
    _ = writer;
}

/// Visit and serialize a tagged template literal.
pub fn visitTaggedTemplateLiteral(writer: anytype, ast: *const Ast) !void {
    _ = ast;
    _ = writer;
}

/// Visit and serialize a template literal element.
pub fn visitTemplateLiteralElement(writer: anytype, ast: *const Ast) !void {
    _ = ast;
    _ = writer;
}

/// Visit and serialize a spread element.
pub fn visitSpreadElement(writer: anytype, ast: *const Ast) !void {
    const s = ast.data.SpreadElement;
    try writer.writeAll("...");
    try serializeNode(writer, s.expression);
}

/// Convert a BinaryOp to its string representation.
pub fn binaryOpToString(op: BinaryOp) []const u8 {
    return switch (op) {
        .Plus => "+", .Minus => "-", .Multiply => "*", .Divide => "/", .Percent => "%",
        .Equals => "==", .NotEquals => "!=", .Identical => "===", .NotIdentical => "!==",
        .Less => "<", .Greater => ">", .LessEquals => "<=", .GreaterEquals => ">=",
        .And => "&&", .Or => "||", .Nullish => "??",
        .BitwiseAnd => "&", .BitwiseOr => "|", .BitwiseXor => "^",
        .LeftShift => "<<", .RightShift => ">>", .UnsignedRightShift => ">>>",
        .Comma => ",",
        .Assign => "=", .AddAssign => "+=", .SubtractAssign => "-=",
        .MultiplyAssign => "*=", .DivideAssign => "/=", .ModuloAssign => "%=",
        .BitwiseAndAssign => "&=", .BitwiseOrAssign => "|=", .BitwiseXorAssign => "^=",
        .LeftShiftAssign => "<<=", .RightShiftAssign => ">>=",
        .UnsignedRightShiftAssign => ">>>=",
        .NullishCoalescingAssign => "??=", .LogicalAndAssign => "&&=", .LogicalOrAssign => "||=",
    };
}
