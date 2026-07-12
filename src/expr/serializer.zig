/// Expression Serializer — AST to string (for debugging/error messages)
const std = @import("std");
const Ast = @import("ast.zig").Ast;
const BinaryOp = @import("ast.zig").BinaryOp;

pub fn serialize(allocator: std.mem.Allocator, node: *const Ast) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();
    try serializeNode(&aw.writer, node);
    var list = aw.toArrayList();
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
                .Number => |n| try writer.print("{d}", .{n}),
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
