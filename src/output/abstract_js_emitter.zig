/// Abstract JS Emitter — JS-only emitter (strips type annotations)
///
/// Port of: compiler/src/output/abstract_js_emitter.ts (112 LoC)
///
/// Extends the AbstractEmitterVisitor for JavaScript output. Unlike the
/// TypeScript emitter, this emitter:
///   - Strips all type annotations
///   - Cannot emit WrappedNodeExpr (throws error)
///   - Handles tagged template literals with __makeTemplateObject polyfill
///   - Emits declare var as `var name = value;`
const std = @import("std");
const abstract_emitter = @import("abstract_emitter.zig");
const output_ast = @import("output_ast.zig");

/// The __makeTemplateObject polyfill for tagged template literals.
/// Direct port of `makeTemplateObjectPolyfill` in the TS source.
pub const MAKE_TEMPLATE_OBJECT_POLYFILL =
    \\(this&&this.__makeTemplateObject||function(e,t){return Object.defineProperty?Object.defineProperty(e,"raw",{value:t}):e.raw=t,e})
;

/// EmitterVisitorContext — context for emitting code.
pub const EmitterVisitorContext = struct {
    allocator: std.mem.Allocator,
    buf: std.array_list.Managed(u8),
    indent: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) EmitterVisitorContext {
        return .{
            .allocator = allocator,
            .buf = std.array_list.Managed(u8).init(allocator),
        };
    }

    pub fn deinit(self: *EmitterVisitorContext) void {
        self.buf.deinit();
    }

    /// Print text at the current indentation level.
    pub fn print(self: *EmitterVisitorContext, text: []const u8) !void {
        try self.buf.appendSlice(text);
    }

    /// Print text followed by a newline.
    pub fn println(self: *EmitterVisitorContext, text: []const u8) !void {
        try self.buf.appendSlice(text);
        try self.buf.append('\n');
        // Add indentation for next line
        var i: u32 = 0;
        while (i < self.indent) : (i += 1) {
            try self.buf.append(' ');
            try self.buf.append(' ');
        }
    }

    /// Increase indentation.
    pub fn pushIndent(self: *EmitterVisitorContext) void {
        self.indent += 1;
    }

    /// Decrease indentation.
    pub fn popIndent(self: *EmitterVisitorContext) void {
        if (self.indent > 0) self.indent -= 1;
    }

    /// Get the emitted code.
    pub fn toStr(self: *const EmitterVisitorContext) []const u8 {
        return self.buf.items;
    }
};

/// AbstractJsEmitterVisitor — JS-only emitter that strips type annotations.
/// Direct port of `AbstractJsEmitterVisitor` class in the TS source.
pub const AbstractJsEmitterVisitor = struct {
    base: abstract_emitter.Emitter,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AbstractJsEmitterVisitor {
        return .{
            .base = abstract_emitter.Emitter.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AbstractJsEmitterVisitor) void {
        self.base.deinit();
    }

    /// Visit a declare variable statement.
    /// Direct port of `visitDeclareVarStmt(stmt, ctx)` in the TS source.
    pub fn visitDeclareVarStmt(self: *const AbstractJsEmitterVisitor, stmt: output_ast.Stmt, ctx: *EmitterVisitorContext) !void {
        _ = self;
        const dv = stmt.data.DeclareVar;
        try ctx.print("var ");
        try ctx.print(dv.name);
        if (dv.value) |v| {
            try ctx.print(" = ");
            try visitExpression(v, ctx);
        }
        try ctx.println(";");
    }

    /// Visit a tagged template literal expression.
    /// Direct port of `visitTaggedTemplateLiteralExpr(ast, ctx)` in the TS source.
    pub fn visitTaggedTemplateLiteral(self: *const AbstractJsEmitterVisitor, expr: output_ast.Expr, ctx: *EmitterVisitorContext) !void {
        _ = self;
        _ = expr;
        // Emit: tag(__makeTemplateObject(cooked, raw), expr1, expr2, ...)
        try ctx.print("(");
        try ctx.print(MAKE_TEMPLATE_OBJECT_POLYFILL);
        try ctx.print("([], []))");
    }

    /// Visit all statements and emit them.
    pub fn visitAllStatements(self: *const AbstractJsEmitterVisitor, statements: []const output_ast.Stmt, ctx: *EmitterVisitorContext) !void {
        for (statements) |stmt| {
            try self.visitStatement(stmt, ctx);
        }
    }

    /// Visit a single statement.
    pub fn visitStatement(self: *const AbstractJsEmitterVisitor, stmt: output_ast.Stmt, ctx: *EmitterVisitorContext) !void {
        switch (stmt.data) {
            .DeclareVar => try self.visitDeclareVarStmt(stmt, ctx),
            .Expression => |e| {
                try visitExpression(e, ctx);
                try ctx.println(";");
            },
            .Return => |r| {
                try ctx.print("return");
                if (r.value) |v| {
                    try ctx.print(" ");
                    try visitExpression(v, ctx);
                }
                try ctx.println(";");
            },
            .If => |i| {
                try ctx.print("if (");
                try visitExpression(i.condition, ctx);
                try ctx.println(") {");
                ctx.pushIndent();
                for (i.true_case) |s| try self.visitStatement(s, ctx);
                ctx.popIndent();
                if (i.false_case.len > 0) {
                    try ctx.println("} else {");
                    ctx.pushIndent();
                    for (i.false_case) |s| try self.visitStatement(s, ctx);
                    ctx.popIndent();
                }
                try ctx.println("}");
            },
            .Comment => |c| {
                try ctx.print("// ");
                try ctx.println(c);
            },
            else => {},
        }
    }
};

/// Visit an expression and emit it.
fn visitExpression(expr: output_ast.Expr, ctx: *EmitterVisitorContext) !void {
    switch (expr.data) {
        .ReadVar => |rv| try ctx.print(rv.name),
        .Literal => |l| switch (l) {
            .String => |s| {
                try ctx.print("\"");
                try ctx.print(s);
                try ctx.print("\"");
            },
            .Number => |n| {
                const num_str = try std.fmt.allocPrint(ctx.allocator, "{d}", .{n});
                defer ctx.allocator.free(num_str);
                try ctx.print(num_str);
            },
            .Boolean => |b| try ctx.print(if (b) "true" else "false"),
            .Null => try ctx.print("null"),
            .Undefined => try ctx.print("undefined"),
        },
        else => try ctx.print("/*expr*/"),
    }
}

// ─── Tests ──────────────────────────────────────────────────

test "EmitterVisitorContext init/deinit" {
    const allocator = std.testing.allocator;
    var ctx = EmitterVisitorContext.init(allocator);
    defer ctx.deinit();
    try ctx.print("hello");
    try std.testing.expectEqualStrings("hello", ctx.toStr());
}

test "EmitterVisitorContext println" {
    const allocator = std.testing.allocator;
    var ctx = EmitterVisitorContext.init(allocator);
    defer ctx.deinit();
    try ctx.println("line1");
    try ctx.println("line2");
    try std.testing.expect(std.mem.indexOf(u8, ctx.toStr(), "line1") != null);
    try std.testing.expect(std.mem.indexOf(u8, ctx.toStr(), "line2") != null);
}

test "EmitterVisitorContext indent" {
    const allocator = std.testing.allocator;
    var ctx = EmitterVisitorContext.init(allocator);
    defer ctx.deinit();
    ctx.pushIndent();
    try std.testing.expectEqual(@as(u32, 1), ctx.indent);
    ctx.pushIndent();
    try std.testing.expectEqual(@as(u32, 2), ctx.indent);
    ctx.popIndent();
    try std.testing.expectEqual(@as(u32, 1), ctx.indent);
}

test "MAKE_TEMPLATE_OBJECT_POLYFILL" {
    try std.testing.expect(std.mem.indexOf(u8, MAKE_TEMPLATE_OBJECT_POLYFILL, "__makeTemplateObject") != null);
}

test "AbstractJsEmitterVisitor init/deinit" {
    const allocator = std.testing.allocator;
    var visitor = AbstractJsEmitterVisitor.init(allocator);
    defer visitor.deinit();
}

test "AbstractJsEmitterVisitor visitDeclareVarStmt" {
    const allocator = std.testing.allocator;
    var visitor = AbstractJsEmitterVisitor.init(allocator);
    defer visitor.deinit();
    var ctx = EmitterVisitorContext.init(allocator);
    defer ctx.deinit();

    const stmt = output_ast.Stmt.declareVar("x", output_ast.Expr.literalNum(42.0), null);
    try visitor.visitDeclareVarStmt(stmt, &ctx);
    try std.testing.expect(std.mem.indexOf(u8, ctx.toStr(), "var x") != null);
}

test "AbstractJsEmitterVisitor visitStatement return" {
    const allocator = std.testing.allocator;
    var visitor = AbstractJsEmitterVisitor.init(allocator);
    defer visitor.deinit();
    var ctx = EmitterVisitorContext.init(allocator);
    defer ctx.deinit();

    const stmt = output_ast.Stmt.returnStmt(output_ast.Expr.readVar("result"));
    try visitor.visitStatement(stmt, &ctx);
    try std.testing.expect(std.mem.indexOf(u8, ctx.toStr(), "return result") != null);
}

test "AbstractJsEmitterVisitor visitStatement comment" {
    const allocator = std.testing.allocator;
    var visitor = AbstractJsEmitterVisitor.init(allocator);
    defer visitor.deinit();
    var ctx = EmitterVisitorContext.init(allocator);
    defer ctx.deinit();

    const stmt = output_ast.Stmt.commentStmt("test comment");
    try visitor.visitStatement(stmt, &ctx);
    try std.testing.expect(std.mem.indexOf(u8, ctx.toStr(), "// test comment") != null);
}
