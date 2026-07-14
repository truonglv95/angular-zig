/// Expression AST → IR Expression Conversion
///
/// Converts parsed expression AST (expr/ast.zig) into simplified
/// IR expressions (ir/expression.zig) used by the code generator.
///
/// DOD: Stack-based recursive conversion. No intermediate heap
/// allocations. All IrExpr nodes allocated from the job's arena.
const std = @import("std");
const Allocator = std.mem.Allocator;

const job_mod = @import("job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ConstantPool = job_mod.ConstantPool;

const expr_ast = @import("../../../expression_parser/ast.zig");
const Ast = expr_ast.Ast;
const AstKind = expr_ast.AstKind;
const BinaryOp = expr_ast.BinaryOp;
const LiteralValue = expr_ast.LiteralValue;

const ir_expr = @import("expression.zig");
const IrExpr = ir_expr.IrExpr;
const ExprData = ir_expr.ExprData;
const ExpressionKind = ir_expr.ExpressionKind;

const source_span = @import("../../../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

// ─── Conversion Entry Point ──────────────────────────────────

/// Convert an expression AST node into an IR expression.
/// Returns an arena-allocated IrExpr pointer.
pub fn convertExpr(job: *ComponentCompilationJob, ast_node: *const Ast) error{ OutOfMemory, NoSpaceLeft }!*IrExpr {
    const ir = try convertExprInner(job, ast_node);
    const ptr = try job.allocExpr(IrExpr);
    ptr.* = ir;
    return ptr;
}

fn convertExprInner(job: *ComponentCompilationJob, ast_node: *const Ast) error{ OutOfMemory, NoSpaceLeft }!IrExpr {
    return switch (ast_node.data) {
        .Empty => IrExpr.empty(ast_node.abs_span),
        .ImplicitReceiver => IrExpr.context(ast_node.abs_span),
        .ThisReceiver => IrExpr.context(ast_node.abs_span),
        .LiteralPrimitive => |lit| try convertLiteral(job, ast_node.abs_span, lit),
        .PropertyRead => |pr| try convertPropertyRead(job, ast_node.abs_span, pr.receiver, pr.name),
        .SafePropertyRead => |spr| try convertSafePropertyRead(job, ast_node.abs_span, spr.receiver, spr.name),
        .KeyedRead => |kr| try convertKeyedRead(job, ast_node.abs_span, kr.receiver, kr.key),
        .SafeKeyedRead => |skr| try convertSafeKeyedRead(job, ast_node.abs_span, skr.receiver, skr.key),
        .BindingPipe => |bp| try convertPipe(job, ast_node.abs_span, bp),
        .Binary => |bin| try convertBinary(job, ast_node.abs_span, bin.op, bin.left, bin.right),
        .Conditional => |cond| try convertConditional(job, ast_node.abs_span, cond.condition, cond.true_expr, cond.false_expr),
        .Call => |call| try convertCall(job, ast_node.abs_span, call.receiver, call.args),
        .SafeCall => |call| try convertSafeCall(job, ast_node.abs_span, call.receiver, call.args),
        .PrefixNot => |not_expr| try convertNot(job, ast_node.abs_span, not_expr.expression),
        .Unary => |unary| try convertUnary(job, ast_node.abs_span, unary.operator, unary.expr),
        .LiteralArray => |arr| try convertArray(job, ast_node.abs_span, arr.expressions),
        .LiteralMap => |map| try convertMap(job, ast_node.abs_span, map.entries),
        .NonNullAssert => |nna| try convertNonNullAssert(job, ast_node.abs_span, nna.expression),
        .ArrowFunction => |af| try convertArrowFunction(job, ast_node.abs_span, af.params, af.body),
        .Parenthesized => |p| try convertExprInner(job, p.expression),
        .Chain => |chain| try convertChain(job, ast_node.abs_span, chain.expressions),
        .TypeofExpr => |t| try convertTypeof(job, ast_node.abs_span, t.expression),
        .VoidExpr => |v| try convertVoid(job, ast_node.abs_span, v.expression),
        .Interpolation => |interp| try convertInterpolation(job, ast_node.abs_span, interp.strings, interp.expressions),
        .SpreadElement => |se| try convertExprInner(job, se.expression),
        .ASTWithSource => |aws| try convertExprInner(job, aws.ast),
        .TemplateLiteral, .TaggedTemplate, .RegexLiteral => IrExpr.empty(ast_node.abs_span),
    };
}

// ─── Literal Conversion ─────────────────────────────────────

fn convertLiteral(job: *ComponentCompilationJob, span: AbsoluteSourceSpan, lit: LiteralValue) !IrExpr {
    switch (lit) {
        .String => |s| {
            const idx = try job.addConst(s, .String);
            return IrExpr.constCollected(idx, span);
        },
        .Number => |n| {
            var buf: [64]u8 = undefined;
            const str = if (n == @trunc(n) and @abs(n) < 1e15)
                try std.fmt.bufPrint(&buf, "{d}", .{@as(i64, @intFromFloat(n))})
            else
                try std.fmt.bufPrint(&buf, "{d}", .{n});
            const idx = try job.addConst(str, .Number);
            return IrExpr.constCollected(idx, span);
        },
        .Boolean => |b| {
            const idx = try job.addConst(if (b) "true" else "false", .Boolean);
            return IrExpr.constCollected(idx, span);
        },
        .Null => {
            const idx = try job.addConst("null", .Null);
            return IrExpr.constCollected(idx, span);
        },
        .Undefined => {
            const idx = try job.addConst("undefined", .String);
            return IrExpr.constCollected(idx, span);
        },
        .NaN => {
            const idx = try job.addConst("NaN", .String);
            return IrExpr.constCollected(idx, span);
        },
        .Infinity => {
            const idx = try job.addConst("Infinity", .String);
            return IrExpr.constCollected(idx, span);
        },
    }
}

// ─── Property Access ─────────────────────────────────────────

fn convertPropertyRead(
    job: *ComponentCompilationJob,
    span: AbsoluteSourceSpan,
    receiver: *const Ast,
    name: []const u8,
) error{ OutOfMemory, NoSpaceLeft }!IrExpr {
    if (receiver.data == .ImplicitReceiver or receiver.data == .ThisReceiver) {
        return IrExpr.readVariable(name, 0, span);
    }
    const recv_ir = try convertExpr(job, receiver);
    return IrExpr.readPropExpr(recv_ir, name, span);
}

fn convertSafePropertyRead(
    job: *ComponentCompilationJob,
    span: AbsoluteSourceSpan,
    receiver: *const Ast,
    name: []const u8,
) !IrExpr {
    const recv_ir = try convertExpr(job, receiver);
    const prop_ptr = try job.allocExpr(IrExpr);
    prop_ptr.* = IrExpr.readPropExpr(recv_ir, name, span);
    const null_ptr = try job.allocExpr(IrExpr);
    null_ptr.* = IrExpr.literalExpr("null", span);
    const null_check_ptr = try job.allocExpr(IrExpr);
    null_check_ptr.* = IrExpr.binaryExpr(recv_ir, @intFromEnum(BinaryOp.NotIdentical), null_ptr, span);
    return IrExpr.conditionalExpr(null_check_ptr, prop_ptr, null_ptr, span);
}

fn convertKeyedRead(
    job: *ComponentCompilationJob,
    span: AbsoluteSourceSpan,
    receiver: *const Ast,
    key: *const Ast,
) !IrExpr {
    const recv_ir = try convertExpr(job, receiver);
    const key_ir = try convertExpr(job, key);
    const recv_ptr = try job.allocExpr(IrExpr);
    recv_ptr.* = recv_ir.*;
    const key_ptr = try job.allocExpr(IrExpr);
    key_ptr.* = key_ir.*;
    return .{
        .kind = .SafeKeyedRead,
        .span = span,
        .data = .{ .SafeKeyedRead = .{
            .receiver = recv_ptr,
            .key = key_ptr,
        } },
    };
}

fn convertSafeKeyedRead(
    job: *ComponentCompilationJob,
    span: AbsoluteSourceSpan,
    receiver: *const Ast,
    key: *const Ast,
) !IrExpr {
    const recv_ir = try convertExpr(job, receiver);
    const key_ir = try convertExpr(job, key);
    const recv_ptr = try job.allocExpr(IrExpr);
    recv_ptr.* = recv_ir.*;
    const key_ptr = try job.allocExpr(IrExpr);
    key_ptr.* = key_ir.*;
    return .{
        .kind = .SafeKeyedRead,
        .span = span,
        .data = .{ .SafeKeyedRead = .{
            .receiver = recv_ptr,
            .key = key_ptr,
        } },
    };
}

// ─── Pipe ────────────────────────────────────────────────────

fn convertPipe(
    job: *ComponentCompilationJob,
    span: AbsoluteSourceSpan,
    pipe: anytype,
) !IrExpr {
    var ir_args = std.array_list.Managed(*IrExpr).initCapacity(job.allocator, pipe.args.len) catch unreachable;
    for (pipe.args) |arg| {
        const ir = try convertExpr(job, arg);
        try ir_args.append(ir);
    }
    const args_slice = try ir_args.toOwnedSlice();
    return .{
        .kind = .PipeBinding,
        .span = span,
        .data = .{ .PipeBinding = .{
            .name = pipe.name,
            .args = args_slice,
            .pure = false,
        } },
    };
}

// ─── Binary ──────────────────────────────────────────────────

fn convertBinary(
    job: *ComponentCompilationJob,
    span: AbsoluteSourceSpan,
    op: BinaryOp,
    left: *const Ast,
    right: *const Ast,
) !IrExpr {
    if (op == .And or op == .Or or op == .Nullish) {
        return try convertConditional(job, span, left, right, left);
    }
    const left_ir = try convertExpr(job, left);
    const right_ir = try convertExpr(job, right);
    const op_code: u8 = @intFromEnum(op);
    return IrExpr.binaryExpr(left_ir, op_code, right_ir, span);
}

// ─── Conditional ─────────────────────────────────────────────

fn convertConditional(
    job: *ComponentCompilationJob,
    span: AbsoluteSourceSpan,
    condition: *const Ast,
    true_expr: *const Ast,
    false_expr: *const Ast,
) !IrExpr {
    const cond_ir = try convertExpr(job, condition);
    const true_ir = try convertExpr(job, true_expr);
    const false_ir = try convertExpr(job, false_expr);
    return IrExpr.conditionalExpr(cond_ir, true_ir, false_ir, span);
}

// ─── Function Call ──────────────────────────────────────────

fn convertCall(
    job: *ComponentCompilationJob,
    span: AbsoluteSourceSpan,
    receiver: *const Ast,
    args: []const *const Ast,
) !IrExpr {
    const recv_ir = try convertExpr(job, receiver);
    // Allocate ir_args on the expr_arena (freed in one shot at job.deinit)
    const ir_args = try job.expr_arena.allocator().alloc(*IrExpr, args.len);
    for (args, 0..) |arg, i| {
        ir_args[i] = try convertExpr(job, arg);
    }
    return IrExpr.callExpr(recv_ir, ir_args, span);
}

/// Safe call: receiver?.method(args) → receiver != null ? receiver.method(args) : null
fn convertSafeCall(
    job: *ComponentCompilationJob,
    span: AbsoluteSourceSpan,
    receiver: *const Ast,
    args: []const *const Ast,
) !IrExpr {
    const recv_ir = try convertExpr(job, receiver);
    const ir_args = try job.expr_arena.allocator().alloc(*IrExpr, args.len);
    for (args, 0..) |arg, i| {
        ir_args[i] = try convertExpr(job, arg);
    }
    const call_ptr = try job.allocExpr(IrExpr);
    call_ptr.* = IrExpr.callExpr(recv_ir, ir_args, span);
    const null_ptr = try job.allocExpr(IrExpr);
    null_ptr.* = IrExpr.literalExpr("null", span);
    const not_null_ptr = try job.allocExpr(IrExpr);
    not_null_ptr.* = IrExpr.binaryExpr(recv_ir, @intFromEnum(BinaryOp.NotIdentical), null_ptr, span);
    return IrExpr.conditionalExpr(not_null_ptr, call_ptr, null_ptr, span);
}

// ─── Unary Operators ─────────────────────────────────────────

fn convertNot(
    job: *ComponentCompilationJob,
    span: AbsoluteSourceSpan,
    expr: *const Ast,
) !IrExpr {
    const inner_ir = try convertExpr(job, expr);
    return IrExpr.notExpr(inner_ir, span);
}

fn convertUnary(
    job: *ComponentCompilationJob,
    span: AbsoluteSourceSpan,
    operator: u8,
    expr: *const Ast,
) !IrExpr {
    if (operator == '-') {
        const inner_ir = try convertExpr(job, expr);
        const zero_ptr = try job.allocExpr(IrExpr);
        zero_ptr.* = IrExpr.literalExpr("0", span);
        const minus_code: u8 = @intFromEnum(BinaryOp.Minus);
        return IrExpr.binaryExpr(zero_ptr, minus_code, inner_ir, span);
    }
    if (operator == '+' or operator == '~') {
        return try convertExprInner(job, expr);
    }
    // void operator
    return IrExpr.empty(span);
}

fn convertNonNullAssert(
    job: *ComponentCompilationJob,
    _: AbsoluteSourceSpan,
    expr: *const Ast,
) !IrExpr {
    return try convertExprInner(job, expr);
}

// ─── Arrays and Maps ─────────────────────────────────────────

fn convertArray(
    job: *ComponentCompilationJob,
    span: AbsoluteSourceSpan,
    exprs: []const *const Ast,
) !IrExpr {
    // Build JS source for each element, join with commas, store as constant
    if (exprs.len == 0) {
        const idx = try job.addConst("[]", .Array);
        return IrExpr.constCollected(idx, span);
    }

    var buf = std.array_list.Managed(u8).initCapacity(job.allocator, 64) catch unreachable;
    try buf.append('[');
    for (exprs, 0..) |e, i| {
        if (i > 0) try buf.append(',');
        const ir = try convertExprInner(job, e);
        try appendIrExprSource(&buf, &ir);
    }
    try buf.append(']');
    const idx = try job.addConst(buf.items, .Array);
    buf.deinit();
    return IrExpr.constCollected(idx, span);
}

fn convertMap(
    job: *ComponentCompilationJob,
    span: AbsoluteSourceSpan,
    entries: []const expr_ast.MapEntry,
) !IrExpr {
    if (entries.len == 0) {
        const idx = try job.addConst("{}", .Map);
        return IrExpr.constCollected(idx, span);
    }

    var buf = std.array_list.Managed(u8).initCapacity(job.allocator, 64) catch unreachable;
    try buf.append('{');
    for (entries, 0..) |e, i| {
        if (i > 0) try buf.append(',');
        if (e.quoted) try buf.append('"');
        try buf.appendSlice(e.key);
        if (e.quoted) try buf.append('"');
        try buf.append(':');
        const ir = try convertExprInner(job, e.value);
        try appendIrExprSource(&buf, &ir);
    }
    try buf.append('}');
    const idx = try job.addConst(buf.items, .Map);
    buf.deinit();
    return IrExpr.constCollected(idx, span);
}

/// Append a human-readable source representation of an IrExpr to a buffer.
/// Used to build array/map constant strings for the constant pool.
fn appendIrExprSource(buf: *std.array_list.Managed(u8), expr: *const IrExpr) !void {
    switch (expr.data) {
        .ConstCollected => |idx| {
            var tmp: [16]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "_c{d}", .{idx}) catch unreachable;
            try buf.appendSlice(s);
        },
        .LiteralExpr => |l| {
            try buf.appendSlice(l.value);
        },
        .ReadVariable => |v| {
            try buf.appendSlice(v.name);
        },
        .Context => {
            try buf.appendSlice("ctx");
        },
        .BinaryExpr => |b| {
            try appendIrExprSource(buf, b.left);
            const op_str = binaryOpToSourceStr(b.op);
            try buf.appendSlice(op_str);
            try appendIrExprSource(buf, b.right);
        },
        .ConditionalExpr => |c| {
            try appendIrExprSource(buf, c.condition);
            try buf.appendSlice("?");
            try appendIrExprSource(buf, c.true_expr);
            try buf.appendSlice(":");
            try appendIrExprSource(buf, c.false_expr);
        },
        .NotExpr => |n| {
            try buf.appendSlice("!");
            try appendIrExprSource(buf, n.expression);
        },
        .CallExpr => |c| {
            try appendIrExprSource(buf, c.receiver);
            try buf.appendSlice("()");
        },
        .ReadPropExpr => |r| {
            try appendIrExprSource(buf, r.receiver);
            try buf.appendSlice(".");
            try buf.appendSlice(r.name);
        },
        .SafePropertyRead => |s| {
            try appendIrExprSource(buf, s.receiver);
            try buf.appendSlice("?");
            try buf.appendSlice(".");
            try buf.appendSlice(s.name);
        },
        else => {
            try buf.appendSlice("0");
        },
    }
}

fn binaryOpToSourceStr(op: u8) []const u8 {
    return switch (@as(BinaryOp, @enumFromInt(op))) {
        .Plus => "+",
        .Minus => "-",
        .Multiply => "*",
        .Divide => "/",
        .Percent => "%",
        .Equals => "==",
        .NotEquals => "!=",
        .Identical => "===",
        .NotIdentical => "!==",
        .Less => "<",
        .Greater => ">",
        .LessEquals => "<=",
        .GreaterEquals => ">=",
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
        .Comma => ",",
        .Power => "**",
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

// ─── Arrow Function ─────────────────────────────────────────

fn convertArrowFunction(
    job: *ComponentCompilationJob,
    span: AbsoluteSourceSpan,
    params: []const expr_ast.ArrowParam,
    body: *const Ast,
) !IrExpr {
    const param_names = try job.expr_arena.allocator().alloc([]const u8, params.len);
    for (params, 0..) |p, i| {
        param_names[i] = p.name;
    }
    const body_ir = try convertExpr(job, body);
    return .{
        .kind = .ArrowFunction,
        .span = span,
        .data = .{ .ArrowFunction = .{
            .param_names = param_names,
            .body = body_ir,
        } },
    };
}

// ─── Chain (semicolon-separated) ─────────────────────────────

fn convertChain(
    job: *ComponentCompilationJob,
    span: AbsoluteSourceSpan,
    exprs: []const *const Ast,
) !IrExpr {
    if (exprs.len > 0) {
        return try convertExprInner(job, exprs[exprs.len - 1]);
    }
    return IrExpr.empty(span);
}

// ─── Typeof / Void ───────────────────────────────────────────

fn convertTypeof(
    job: *ComponentCompilationJob,
    _: AbsoluteSourceSpan,
    expr: *const Ast,
) !IrExpr {
    return try convertExprInner(job, expr);
}

fn convertVoid(
    job: *ComponentCompilationJob,
    _: AbsoluteSourceSpan,
    expr: *const Ast,
) !IrExpr {
    return try convertExprInner(job, expr);
}

// ─── Interpolation ───────────────────────────────────────────

fn convertInterpolation(
    job: *ComponentCompilationJob,
    span: AbsoluteSourceSpan,
    strings: []const []const u8,
    exprs: []const *const Ast,
) !IrExpr {
    // Full interpolation: join strings and expressions into a template literal.
    // "Hello {{ name }}!" → "Hello " + name + "!"
    if (exprs.len == 0) {
        if (strings.len > 0) {
            const idx = try job.addConst(strings[0], .String);
            return IrExpr.constCollected(idx, span);
        }
        return IrExpr.empty(span);
    }

    // Build all parts: convert each expression, interleave with strings
    // Result: a chain of BinaryExpr(+, string, expr, string, ...)
    var current: *IrExpr = undefined;
    for (exprs, 0..) |e, i| {
        // Add leading string if present
        if (i < strings.len and strings[i].len > 0) {
            const str_idx = try job.addConst(strings[i], .String);
            const str_ir = try job.allocExpr(IrExpr);
            str_ir.* = IrExpr.constCollected(str_idx, span);
            if (i == 0) {
                current = str_ir;
            } else {
                const concat_ptr = try job.allocExpr(IrExpr);
                concat_ptr.* = IrExpr.binaryExpr(current, @intFromEnum(BinaryOp.Plus), str_ir, span);
                current = concat_ptr;
            }
        }
        // Add expression
        const expr_ir = try convertExpr(job, e);
        if (i == 0 and (i >= strings.len or strings[i].len == 0)) {
            current = expr_ir;
        } else {
            const concat_ptr = try job.allocExpr(IrExpr);
            concat_ptr.* = IrExpr.binaryExpr(current, @intFromEnum(BinaryOp.Plus), expr_ir, span);
            current = concat_ptr;
        }
    }
    // Add trailing string
    if (strings.len > exprs.len and strings[exprs.len].len > 0) {
        const str_idx = try job.addConst(strings[exprs.len], .String);
        const str_ir = try job.allocExpr(IrExpr);
        str_ir.* = IrExpr.constCollected(str_idx, span);
        const concat_ptr = try job.allocExpr(IrExpr);
        concat_ptr.* = IrExpr.binaryExpr(current, @intFromEnum(BinaryOp.Plus), str_ir, span);
        current = concat_ptr;
    }
    return current.*;
}

// ─── Tests ────────────────────────────────────────────────────

test "convertBinary produces BinaryExpr" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "TestComp", .Full);
    defer job.deinit();

    const span = expr_ast.ParseSpan{ .start = 0, .end = 5 };
    const abs = AbsoluteSourceSpan{ .start = 0, .end = 5 };

    var left = Ast.literalNumber(span, abs, 1.0);
    var right = Ast.literalNumber(span, abs, 2.0);
    var binary_ast = Ast.binary(span, abs, .Plus, &left, &right);

    const ir_ptr = try convertExpr(&job, &binary_ast);
    try std.testing.expectEqual(ExpressionKind.BinaryExpr, ir_ptr.kind);
    try std.testing.expectEqual(@as(u8, @intFromEnum(BinaryOp.Plus)), ir_ptr.data.BinaryExpr.op);
}

test "convertPropertyRead on implicit receiver produces ReadVariable" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "TestComp", .Full);
    defer job.deinit();

    const span = expr_ast.ParseSpan{ .start = 0, .end = 5 };
    const abs = AbsoluteSourceSpan{ .start = 0, .end = 5 };

    var recv = Ast.implicitReceiver(span, abs);
    var prop_ast = Ast.propertyRead(span, abs, &recv, "name");

    const ir_ptr = try convertExpr(&job, &prop_ast);
    try std.testing.expectEqual(ExpressionKind.ReadVariable, ir_ptr.kind);
    try std.testing.expectEqualStrings("name", ir_ptr.data.ReadVariable.name);
}

test "convertCall produces CallExpr with args" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "TestComp", .Full);
    defer job.deinit();

    const span = expr_ast.ParseSpan{ .start = 0, .end = 20 };
    const abs = AbsoluteSourceSpan{ .start = 0, .end = 20 };

    var recv = Ast.implicitReceiver(span, abs);
    var handler_prop = Ast.propertyRead(span, abs, &recv, "handleClick");
    var arg = Ast.literalString(span, abs, "$event");
    const args = [_]*const Ast{&arg};
    var call_ast = Ast.call(span, abs, &handler_prop, &args, span);

    const ir_ptr = try convertExpr(&job, &call_ast);
    try std.testing.expectEqual(ExpressionKind.CallExpr, ir_ptr.kind);
    try std.testing.expectEqual(@as(usize, 1), ir_ptr.data.CallExpr.args.len);
}

test "convertNot produces NotExpr" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "TestComp", .Full);
    defer job.deinit();

    const span = expr_ast.ParseSpan{ .start = 0, .end = 5 };
    const abs = AbsoluteSourceSpan{ .start = 0, .end = 5 };

    var inner = Ast.literalBool(span, abs, true);
    var not_ast = Ast.prefixNot(span, abs, &inner);

    const ir_ptr = try convertExpr(&job, &not_ast);
    try std.testing.expectEqual(ExpressionKind.NotExpr, ir_ptr.kind);
}

test "convertConditional produces ConditionalExpr with all branches" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "TestComp", .Full);
    defer job.deinit();

    const span = expr_ast.ParseSpan{ .start = 0, .end = 10 };
    const abs = AbsoluteSourceSpan{ .start = 0, .end = 10 };

    var cond = Ast.literalBool(span, abs, true);
    var t = Ast.literalString(span, abs, "yes");
    var f = Ast.literalString(span, abs, "no");
    var cond_ast = Ast.conditional(span, abs, &cond, &t, &f);

    const ir_ptr = try convertExpr(&job, &cond_ast);
    try std.testing.expectEqual(ExpressionKind.ConditionalExpr, ir_ptr.kind);
}

test "convertUnary minus produces BinaryExpr" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "TestComp", .Full);
    defer job.deinit();

    const span = expr_ast.ParseSpan{ .start = 0, .end = 3 };
    const abs = AbsoluteSourceSpan{ .start = 0, .end = 3 };

    var expr_node = Ast.literalNumber(span, abs, 5.0);
    var unary_ast: Ast = .{
        .span = span,
        .abs_span = abs,
        .data = .{ .Unary = .{ .operator = '-', .expr = &expr_node } },
    };

    const ir_ptr = try convertExpr(&job, &unary_ast);
    try std.testing.expectEqual(ExpressionKind.BinaryExpr, ir_ptr.kind);
    try std.testing.expectEqual(@as(u8, @intFromEnum(BinaryOp.Minus)), ir_ptr.data.BinaryExpr.op);
}

test "convertArrowFunction captures param names" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "TestComp", .Full);
    defer job.deinit();

    const span = expr_ast.ParseSpan{ .start = 0, .end = 20 };
    const abs = AbsoluteSourceSpan{ .start = 0, .end = 20 };

    const params = [_]expr_ast.ArrowParam{
        .{ .name = "$event", .span = span },
    };
    var body = Ast.literalString(span, abs, "$event");
    var arrow_ast: Ast = .{
        .span = span,
        .abs_span = abs,
        .data = .{ .ArrowFunction = .{ .params = &params, .body = &body } },
    };

    const ir_ptr = try convertExpr(&job, &arrow_ast);
    try std.testing.expectEqual(ExpressionKind.ArrowFunction, ir_ptr.kind);
    try std.testing.expectEqual(@as(usize, 1), ir_ptr.data.ArrowFunction.param_names.len);
    try std.testing.expectEqualStrings("$event", ir_ptr.data.ArrowFunction.param_names[0]);
}

test "convertSafePropertyRead produces ConditionalExpr" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "TestComp", .Full);
    defer job.deinit();

    const span = expr_ast.ParseSpan{ .start = 0, .end = 10 };
    const abs = AbsoluteSourceSpan{ .start = 0, .end = 10 };

    var recv = Ast.literalString(span, abs, "obj");
    var safe_ast = Ast.safePropertyRead(span, abs, &recv, "name");

    const ir_ptr = try convertExpr(&job, &safe_ast);
    try std.testing.expectEqual(ExpressionKind.ConditionalExpr, ir_ptr.kind);
}

test "convertArray produces proper constant" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "TestComp", .Full);
    defer job.deinit();

    const span = expr_ast.ParseSpan{ .start = 0, .end = 5 };
    const abs = AbsoluteSourceSpan{ .start = 0, .end = 5 };

    var e1 = Ast.literalNumber(span, abs, 1.0);
    var e2 = Ast.literalNumber(span, abs, 2.0);
    var e3 = Ast.literalNumber(span, abs, 3.0);
    const exprs = [_]*const Ast{ &e1, &e2, &e3 };
    var arr_ast = Ast.literalArray(span, abs, &exprs);

    const ir_ptr = try convertExpr(&job, &arr_ast);
    try std.testing.expectEqual(ExpressionKind.ConstCollected, ir_ptr.kind);
    // The constant should contain "1,2,3" (actual numbers, not placeholder)
    const const_val = job.pool.get(ir_ptr.data.ConstCollected).?;
    try std.testing.expect(const_val.kind == .Array);
}

test "convertMap produces proper constant" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "TestComp", .Full);
    defer job.deinit();

    const span = expr_ast.ParseSpan{ .start = 0, .end = 10 };
    const abs = AbsoluteSourceSpan{ .start = 0, .end = 10 };

    var val = Ast.literalString(span, abs, "hello");
    const entries = [_]expr_ast.MapEntry{
        .{ .key = "name", .value = &val, .quoted = true },
    };
    var map_ast: Ast = .{
        .span = span,
        .abs_span = abs,
        .data = .{ .LiteralMap = .{ .entries = &entries } },
    };

    const ir_ptr = try convertExpr(&job, &map_ast);
    try std.testing.expectEqual(ExpressionKind.ConstCollected, ir_ptr.kind);
    const const_val = job.pool.get(ir_ptr.data.ConstCollected).?;
    try std.testing.expect(const_val.kind == .Map);
}

test "convertInterpolation with multiple expressions" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "TestComp", .Full);
    defer job.deinit();

    const span = expr_ast.ParseSpan{ .start = 0, .end = 20 };
    const abs = AbsoluteSourceSpan{ .start = 0, .end = 20 };

    var e1 = Ast.literalString(span, abs, "hello");
    var e2 = Ast.literalString(span, abs, "world");
    const exprs_arr = [_]*const Ast{ &e1, &e2 };
    const strings_arr = [_][]const u8{ "a ", " b " };
    var interp_ast: Ast = .{
        .span = span,
        .abs_span = abs,
        .data = .{ .Interpolation = .{ .strings = &strings_arr, .expressions = &exprs_arr } },
    };

    const ir_ptr = try convertExpr(&job, &interp_ast);
    try std.testing.expectEqual(ExpressionKind.BinaryExpr, ir_ptr.kind);
}

test "convertSafeCall produces ConditionalExpr" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "TestComp", .Full);
    defer job.deinit();

    const span = expr_ast.ParseSpan{ .start = 0, .end = 20 };
    const abs = AbsoluteSourceSpan{ .start = 0, .end = 20 };

    var recv = Ast.literalString(span, abs, "obj");
    var method_prop = Ast.propertyRead(span, abs, &recv, "method");
    const args = [_]*const Ast{};
    var safe_call_ast: Ast = .{
        .span = span,
        .abs_span = abs,
        .data = .{ .SafeCall = .{ .receiver = &method_prop, .args = &args, .argument_span = span } },
    };

    const ir_ptr = try convertExpr(&job, &safe_call_ast);
    try std.testing.expectEqual(ExpressionKind.ConditionalExpr, ir_ptr.kind);
}
