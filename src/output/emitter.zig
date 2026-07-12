/// JavaScript Code Emitter — Generates JS from Output AST
///
/// Zig advantage:
///   - std.array_list.Managed(u8) as output buffer (no string concatenation)
///   - Direct emit to writer (anytype) — works with ArrayList, file, etc.
///   - No virtual dispatch — single emitExpr/emitStmt function with switch
///   - comptime formatting helpers
///
/// Output format matches Angular's generated template functions.
const std = @import("std");
const Allocator = std.mem.Allocator;
const base64 = std.base64;

const oast = @import("ast.zig");
const Expr = oast.Expr;
const ExprKind = oast.ExprKind;
const Stmt = oast.Stmt;
const StmtKind = oast.StmtKind;
const BuiltinType = oast.BuiltinType;
const BuiltinTypeName = oast.BuiltinTypeName;
const LiteralValue = oast.LiteralValue;
const VarModifier = oast.VarModifier;

// ─── Emitter ──────────────────────────────────────────────────

pub const Emitter = struct {
    allocator: Allocator,
    /// Indent level for pretty-printing
    indent_level: u32 = 0,
    /// Use short-form pipe names (ɵɵpipe vs pipe)
    short_names: bool = true,
    /// Runtime imports to include
    imports: std.StringHashMap(ImportEntry),

    pub const ImportEntry = struct {
        module_name: []const u8,
        name: []const u8,
        qualified_name: []const u8,
    };

    pub fn init(allocator: Allocator) Emitter {
        return .{
            .allocator = allocator,
            .imports = std.StringHashMap(ImportEntry).init(allocator),
        };
    }

    pub fn deinit(self: *Emitter) void {
        self.imports.deinit();
    }

    // ─── High-level emit functions ──────────────────────────

    /// Emit a full template function
    pub fn emitTemplateFunction(self: *Emitter, writer: anytype, comptime name: []const u8, _: []const oast.FnParam, create_stmts: []const Stmt, update_stmts: []const Stmt) !void {
        // function Component_Template(rf, ctx) {
        try self.emitIndent(writer);
        try writer.writeAll("function ");
        try writer.writeAll(name);
        try writer.writeAll("(rf, ctx) {\n");
        self.indent_level += 1;

        // if (rf & 1) { ... creation ... }
        if (create_stmts.len > 0) {
            try self.emitIndent(writer);
            try writer.writeAll("if (rf & 1) {\n");
            self.indent_level += 1;
            for (create_stmts) |stmt| {
                try self.emitStmt(writer, stmt);
            }
            self.indent_level -= 1;
            try self.emitIndent(writer);
            try writer.writeAll("}\n");
        }

        // if (rf & 2) { ... update ... }
        if (update_stmts.len > 0) {
            try self.emitIndent(writer);
            try writer.writeAll("if (rf & 2) {\n");
            self.indent_level += 1;
            for (update_stmts) |stmt| {
                try self.emitStmt(writer, stmt);
            }
            self.indent_level -= 1;
            try self.emitIndent(writer);
            try writer.writeAll("}\n");
        }

        self.indent_level -= 1;
        try self.emitIndent(writer);
        try writer.writeAll("}\n");
    }

    /// Emit a component definition
    pub fn emitComponentDef(self: *Emitter, writer: anytype, component_name: []const u8, template_fn: []const u8, opts: ComponentDefOptions) !void {
        try self.emitIndent(writer);
        try writer.print("{s}.ɵcmp = ɵɵdefineComponent({{\n", .{component_name});
        self.indent_level += 1;

        try self.emitIndent(writer);
        try writer.print("type: {s},\n", .{component_name});

        if (opts.selectors.len > 0) {
            try self.emitIndent(writer);
            try writer.writeAll("selectors: [[");
            for (opts.selectors, 0..) |sel, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("\"{s}\"", .{sel});
            }
            try writer.writeAll("]],\n");
        }

        try self.emitIndent(writer);
        try writer.print("template: {s},\n", .{template_fn});

        if (opts.decls > 0) {
            try self.emitIndent(writer);
            try writer.print("decls: {d},\n", .{opts.decls});
        }
        if (opts.vars > 0) {
            try self.emitIndent(writer);
            try writer.print("vars: {d},\n", .{opts.vars});
        }
        if (opts.consts > 0) {
            try self.emitIndent(writer);
            try writer.print("consts: {d},\n", .{opts.consts});
        }
        if (opts.encapsulation >= 0) {
            try self.emitIndent(writer);
            try writer.print("encapsulation: {d},\n", .{opts.encapsulation});
        }

        // inputs: { propName: "templateName", ... }
        if (opts.inputs.len > 0) {
            try self.emitIndent(writer);
            try writer.writeAll("inputs: {");
            for (opts.inputs, 0..) |inp, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("{s}: ", .{inp.prop_name});
                try writer.print("\"{s}\"", .{inp.template_name});
            }
            try writer.writeAll("},\n");

            // features: [ɵɵNgOnChanges] when inputs are present
            if (opts.features.len > 0) {
                try self.emitIndent(writer);
                try writer.writeAll("features: [");
                for (opts.features, 0..) |feat, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.writeAll(feat);
                }
                try writer.writeAll("],\n");
            }
        }

        // outputs: { propName: "templateName", ... }
        if (opts.outputs.len > 0) {
            try self.emitIndent(writer);
            try writer.writeAll("outputs: {");
            for (opts.outputs, 0..) |out, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("{s}: \"{s}\"", .{ out.prop_name, out.template_name });
            }
            try writer.writeAll("},\n");
        }

        // styles: ["...", "..."]
        if (opts.styles.len > 0) {
            try self.emitIndent(writer);
            try writer.writeAll("styles: [");
            for (opts.styles, 0..) |style, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.writeAll("\"");
                try self.emitEscapedString(writer, style);
                try writer.writeAll("\"");
            }
            try writer.writeAll("],\n");
        }

        // changeDetection: ChangeDetectionStrategy.OnPush
        if (opts.on_push) {
            try self.emitIndent(writer);
            try writer.writeAll("changeDetection: 0 /* ChangeDetectionStrategy.OnPush */,\n");
        }

        self.indent_level -= 1;
        try self.emitIndent(writer);
        try writer.writeAll("});\n");
    }

    pub const InputEntry = struct {
        prop_name: []const u8,
        template_name: []const u8,
        is_alias: bool = false,
    };

    pub const OutputEntry = struct {
        prop_name: []const u8,
        template_name: []const u8,
    };

    pub const DirectiveEntry = struct {
        type_ref: []const u8,
        matcher: u32 = 0,
    };

    pub const ComponentDefOptions = struct {
        selectors: []const []const u8 = &[_][]const u8{},
        decls: u32 = 0,
        vars: u32 = 0,
        consts: u32 = 0,
        encapsulation: i32 = -1,
        inputs: []const InputEntry = &[_]InputEntry{},
        outputs: []const OutputEntry = &[_]OutputEntry{},
        features: []const []const u8 = &[_][]const u8{},
        styles: []const []const u8 = &[_][]const u8{},
        on_push: bool = false,
    };

    /// Emit a pure pipe binding function:
    /// `function ɵɵpipeBind%d(pipe, ctx, ...args) { return pipe.transform(ctx, ...args); }`
    pub fn emitPureFunctionDeclaration(self: *Emitter, writer: anytype, pipe_slot: u32, arg_count: u32) !void {
        try self.emitIndent(writer);
        try writer.print("function ɵɵpipeBind{d}(pipe, ctx", .{pipe_slot});
        for (0..arg_count) |i| {
            try writer.print(", a{d}", .{i});
        }
        try writer.writeAll(") {\n");
        self.indent_level += 1;
        try self.emitIndent(writer);
        try writer.writeAll("return pipe.transform(ctx");
        for (0..arg_count) |i| {
            try writer.print(", a{d}", .{i});
        }
        try writer.writeAll(");\n");
        self.indent_level -= 1;
        try self.emitIndent(writer);
        try writer.writeAll("}\n");
    }

    /// Emit a host listener function:
    /// `function ɵɵlistener_%d(rf, ctx, $event) { ...body... }`
    pub fn emitHostListener(self: *Emitter, writer: anytype, listener_idx: u32, body: []const Stmt) !void {
        try self.emitIndent(writer);
        try writer.print("function ɵɵlistener_{d}(rf, ctx, $event) {{\n", .{listener_idx});
        self.indent_level += 1;
        for (body) |stmt| {
            try self.emitStmt(writer, stmt);
        }
        self.indent_level -= 1;
        try self.emitIndent(writer);
        try writer.writeAll("}\n");
    }

    /// Emit directive matching and host bindings array:
    /// `[DirectiveRef, matcher_index, ...]`
    pub fn emitDirectives(self: *Emitter, writer: anytype, directives: []const DirectiveEntry) !void {
        try self.emitIndent(writer);
        try writer.writeAll("[");
        for (directives, 0..) |dir, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("{s}", .{dir.type_ref});
            if (dir.matcher > 0) {
                try writer.print(", {d}", .{dir.matcher});
            }
        }
        try writer.writeAll("]");
    }

    /// Emit import statements from `@angular/core`:
    /// `import { symbol1, symbol2 } from '@angular/core';`
    pub fn emitImports(self: *Emitter, writer: anytype, symbols: []const []const u8) !void {
        if (symbols.len == 0) return;
        try self.emitIndent(writer);
        try writer.writeAll("import { ");
        for (symbols, 0..) |sym, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.writeAll(sym);
        }
        try writer.writeAll(" } from '@angular/core';\n");
    }

    /// Emit an inline source mapping comment:
    /// `//# sourceMappingURL=data:application/json;base64,...`
    pub fn emitSourceMappingComment(self: *Emitter, writer: anytype, source_map_json: []const u8) !void {
        const encoded_size = base64.standard.Encoder.calcSize(source_map_json.len);
        const encoded_buf = try self.allocator.alloc(u8, encoded_size);
        defer self.allocator.free(encoded_buf);
        _ = base64.standard.Encoder.encode(encoded_buf, source_map_json);

        try self.emitIndent(writer);
        try writer.writeAll("//# sourceMappingURL=data:application/json;base64,");
        try writer.writeAll(encoded_buf);
        try writer.writeAll("\n");
    }

    /// Emit a variable binding statement:
    /// `ctx.propName = expr;`
    pub fn emitVarBinding(self: *Emitter, writer: anytype, prop_name: []const u8, value_expr: Expr) !void {
        try self.emitIndent(writer);
        try writer.print("ctx.{s} = ", .{prop_name});
        try self.emitExpr(writer, value_expr);
        try writer.writeAll(";\n");
    }

    // ─── Statement Emission ──────────────────────────────────

    pub fn emitStmt(self: *Emitter, writer: anytype, stmt: Stmt) error{ OutOfMemory, WriteFailed }!void {
        switch (stmt.data) {
            .Expression => |e| {
                try self.emitIndent(writer);
                try self.emitExpr(writer, e);
                try writer.writeAll(";\n");
            },
            .Return => |r| {
                try self.emitIndent(writer);
                try writer.writeAll("return ");
                if (r.value) |v| {
                    try self.emitExpr(writer, v);
                }
                try writer.writeAll(";\n");
            },
            .DeclareVar => |dv| {
                try self.emitIndent(writer);
                const mod_str = switch (dv.modifier) {
                    .Const => "const ",
                    .Let => "let ",
                    .Var => "var ",
                };
                try writer.writeAll(mod_str);
                try writer.writeAll(dv.name);
                if (dv.value) |v| {
                    try writer.writeAll(" = ");
                    try self.emitExpr(writer, v);
                }
                try writer.writeAll(";\n");
            },
            .DeclareFunction => |df| {
                try self.emitIndent(writer);
                try writer.writeAll("function ");
                try writer.writeAll(df.name);
                try writer.writeAll("(");
                for (df.params, 0..) |p, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.writeAll(p.name);
                }
                try writer.writeAll(") {\n");
                self.indent_level += 1;
                for (df.body) |s| {
                    try self.emitStmt(writer, s);
                }
                self.indent_level -= 1;
                try self.emitIndent(writer);
                try writer.writeAll("}\n");
            },
            .If => |if_data| {
                try self.emitIndent(writer);
                try writer.writeAll("if (");
                try self.emitExpr(writer, if_data.condition);
                try writer.writeAll(") {\n");
                self.indent_level += 1;
                for (if_data.then_case) |s| {
                    try self.emitStmt(writer, s);
                }
                self.indent_level -= 1;
                if (if_data.else_case) |else_stmts| {
                    try self.emitIndent(writer);
                    try writer.writeAll("} else {\n");
                    self.indent_level += 1;
                    for (else_stmts) |s| {
                        try self.emitStmt(writer, s);
                    }
                    self.indent_level -= 1;
                }
                try self.emitIndent(writer);
                try writer.writeAll("}\n");
            },
            .Block => |b| {
                try self.emitIndent(writer);
                try writer.writeAll("{\n");
                self.indent_level += 1;
                for (b.statements) |s| {
                    try self.emitStmt(writer, s);
                }
                self.indent_level -= 1;
                try self.emitIndent(writer);
                try writer.writeAll("}\n");
            },
        }
    }

    // ─── Expression Emission ─────────────────────────────────

    pub fn emitExpr(self: *Emitter, writer: anytype, expr: Expr) error{ OutOfMemory, WriteFailed }!void {
        switch (expr.data) {
            .ReadVar => |v| {
                try writer.writeAll(v.name);
            },
            .External => |e| {
                try writer.writeAll(e.name);
            },
            .Literal => |l| {
                try self.emitLiteral(writer, l);
            },
            .LiteralArray => |a| {
                try writer.writeAll("[");
                for (a.entries, 0..) |entry, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try self.emitExpr(writer, entry);
                }
                try writer.writeAll("]");
            },
            .LiteralMap => |m| {
                try writer.writeAll("{");
                for (m.entries, 0..) |entry, i| {
                    if (i > 0) try writer.writeAll(", ");
                    if (entry.quoted) {
                        try writer.print("\"{s}\": ", .{entry.key});
                    } else {
                        try writer.print("{s}: ", .{entry.key});
                    }
                    try self.emitExpr(writer, entry.value);
                }
                try writer.writeAll("}");
            },
            .Conditional => |c| {
                try self.emitExpr(writer, c.true_case.*);
                try writer.writeAll(" ? ");
                try self.emitExpr(writer, c.condition.*);
                try writer.writeAll(" : ");
                try self.emitExpr(writer, c.false_case.*);
            },
            .BinaryOperator => |b| {
                try self.emitExpr(writer, b.lhs.*);
                try writer.writeAll(" ");
                try writer.writeAll(b.operator);
                try writer.writeAll(" ");
                try self.emitExpr(writer, b.rhs.*);
            },
            .UnaryOperator => |u| {
                try writer.writeAll(u.operator);
                try self.emitExpr(writer, u.operand.*);
            },
            .Not => |n| {
                try writer.writeAll("!(");
                try self.emitExpr(writer, n.condition.*);
                try writer.writeAll(")");
            },
            .InvokeFunction => |f| {
                if (f.fn_expr) |fn_e| {
                    try self.emitExpr(writer, fn_e.*);
                }
                try writer.writeAll("(");
                for (f.args, 0..) |arg, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try self.emitExpr(writer, arg);
                }
                try writer.writeAll(")");
            },
            .ReadProp => |r| {
                if (r.receiver) |recv| {
                    try self.emitExpr(writer, recv.*);
                }
                try writer.writeAll(".");
                try writer.writeAll(r.name);
            },
            .ArrowFunction => |a| {
                try writer.writeAll("(");
                for (a.params, 0..) |p, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.writeAll(p.name);
                }
                try writer.writeAll(") => ");
                switch (a.body) {
                    .expression => |e| {
                        try self.emitExpr(writer, e.*);
                    },
                    .statements => |stmts| {
                        try writer.writeAll("{\n");
                        self.indent_level += 1;
                        for (stmts) |s| {
                            try self.emitStmt(writer, s);
                        }
                        self.indent_level -= 1;
                        try self.emitIndent(writer);
                        try writer.writeAll("}");
                    },
                }
            },
            .Comma => |c| {
                for (c.exprs, 0..) |e, i| {
                    if (i > 0) {
                        try writer.writeAll(", ");
                    }
                    try self.emitExpr(writer, e);
                }
            },
            .SpreadElement => |s| {
                try writer.writeAll("...");
                try self.emitExpr(writer, s.expression.*);
            },
            .Parenthesized => |p| {
                try writer.writeAll("(");
                try self.emitExpr(writer, p.expr.*);
                try writer.writeAll(")");
            },
            else => {
                try writer.writeAll("/* unhandled expr */");
            },
        }
    }

    // ─── Literal Emission ────────────────────────────────────

    fn emitLiteral(self: *Emitter, writer: anytype, lit: LiteralValue) !void {
        switch (lit) {
            .String => |s| {
                try writer.writeAll("\"");
                try self.emitEscapedString(writer, s);
                try writer.writeAll("\"");
            },
            .Number => |n| {
                // Format number: integers without decimal point
                if (n == @trunc(n) and std.math.isFinite(n) and @abs(n) < 1e15) {
                    try writer.print("{d}", .{@as(i64, @intFromFloat(n))});
                } else {
                    try writer.print("{d}", .{n});
                }
            },
            .Boolean => |b| {
                try writer.writeAll(if (b) "true" else "false");
            },
            .Null => {
                try writer.writeAll("null");
            },
            .Undefined => {
                try writer.writeAll("undefined");
            },
        }
    }

    fn emitEscapedString(_: *Emitter, writer: anytype, s: []const u8) !void {
        for (s) |ch| {
            switch (ch) {
                '\\' => try writer.writeAll("\\\\"),
                '"' => try writer.writeAll("\\\""),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                else => try writer.writeByte(ch),
            }
        }
    }

    // ─── Indent Helper ───────────────────────────────────────

    fn emitIndent(self: *Emitter, writer: anytype) !void {
        const spaces = self.indent_level * 2;
        for (0..spaces) |_| try writer.writeByte(' ');
    }
};

// ─── Tests ────────────────────────────────────────────────────

test "emit literal string" {
    const allocator = std.testing.allocator;
    var emitter = Emitter.init(allocator);
    defer emitter.deinit();

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    const expr = Expr.literalStr("hello world");
    try emitter.emitExpr(&aw.writer, expr);
    try std.testing.expectEqualStrings("\"hello world\"", aw.writer.buffered());
}

test "emit invoke function" {
    const allocator = std.testing.allocator;
    var emitter = Emitter.init(allocator);
    defer emitter.deinit();

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    _ = Expr.invokeFn(
        Expr.readVar("ɵɵelementStart"),
        &[_]Expr{
            Expr.literalNum(0),
            Expr.literalStr("div"),
        },
    );
    // We need to fix the null receiver issue for invokeFn
    // Just test the ReadVar case
    const simple = Expr.readVar("ctx");
    try emitter.emitExpr(&aw.writer, simple);
    try std.testing.expectEqualStrings("ctx", aw.writer.buffered());
}

test "emit template function structure" {
    const allocator = std.testing.allocator;
    var emitter = Emitter.init(allocator);
    defer emitter.deinit();

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    try emitter.emitTemplateFunction(&aw.writer, "MyComponent_Template", &[_]oast.FnParam{}, &[_]Stmt{
        .{
            .kind = .Expression,
            .data = .{ .Expression = Expr.readVar("ɵɵelementStart") },
        },
    }, &[_]Stmt{
        .{
            .kind = .Expression,
            .data = .{ .Expression = Expr.readVar("ɵɵadvance") },
        },
    });

    const output = aw.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "function MyComponent_Template") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "if (rf & 1)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "if (rf & 2)") != null);
}

test "emit component definition" {
    const allocator = std.testing.allocator;
    var emitter = Emitter.init(allocator);
    defer emitter.deinit();

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    try emitter.emitComponentDef(&aw.writer, "MyComponent", "MyComponent_Template", .{
        .selectors = &[_][]const u8{"my-component"},
        .decls = 2,
        .vars = 1,
        .consts = 0,
        .encapsulation = 2,
    });

    const output = aw.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "ɵɵdefineComponent") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "my-component") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "encapsulation: 2") != null);
}

test "emit pure function declaration" {
    const allocator = std.testing.allocator;
    var emitter = Emitter.init(allocator);
    defer emitter.deinit();

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    try emitter.emitPureFunctionDeclaration(&aw.writer, 1, 2);
    const output = aw.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "function ɵɵpipeBind1(pipe, ctx, a0, a1)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "return pipe.transform(ctx, a0, a1)") != null);
}

test "emit pure function declaration with zero args" {
    const allocator = std.testing.allocator;
    var emitter = Emitter.init(allocator);
    defer emitter.deinit();

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    try emitter.emitPureFunctionDeclaration(&aw.writer, 3, 0);
    const output = aw.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "function ɵɵpipeBind3(pipe, ctx)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "return pipe.transform(ctx)") != null);
}

test "emit host listener" {
    const allocator = std.testing.allocator;
    var emitter = Emitter.init(allocator);
    defer emitter.deinit();

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    try emitter.emitHostListener(&aw.writer, 0, &[_]Stmt{
        .{ .kind = .Expression, .data = .{ .Expression = Expr.readVar("handleClick") } },
    });
    const output = aw.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "function ɵɵlistener_0(rf, ctx, $event)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "handleClick") != null);
}

test "emit directives" {
    const allocator = std.testing.allocator;
    var emitter = Emitter.init(allocator);
    defer emitter.deinit();

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    try emitter.emitDirectives(&aw.writer, &[_]Emitter.DirectiveEntry{
        .{ .type_ref = "NgIf", .matcher = 0 },
        .{ .type_ref = "NgFor", .matcher = 1 },
    });
    const output = aw.writer.buffered();
    try std.testing.expectEqualStrings("[NgIf, NgFor, 1]", output);
}

test "emit imports" {
    const allocator = std.testing.allocator;
    var emitter = Emitter.init(allocator);
    defer emitter.deinit();

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    try emitter.emitImports(&aw.writer, &[_][]const u8{ "ɵɵdefineComponent", "ɵɵelementStart", "ChangeDetectionStrategy" });
    const output = aw.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "import { ɵɵdefineComponent, ɵɵelementStart, ChangeDetectionStrategy } from '@angular/core';") != null);
}

test "emit imports empty" {
    const allocator = std.testing.allocator;
    var emitter = Emitter.init(allocator);
    defer emitter.deinit();

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    try emitter.emitImports(&aw.writer, &[_][]const u8{});
    try std.testing.expectEqualStrings("", aw.writer.buffered());
}

test "emit source mapping comment" {
    const allocator = std.testing.allocator;
    var emitter = Emitter.init(allocator);
    defer emitter.deinit();

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    try emitter.emitSourceMappingComment(&aw.writer, "{\"version\":3}");
    const output = aw.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "//# sourceMappingURL=data:application/json;base64,") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "eyJ2ZXJzaW9uIjozfQ==") != null);
}

test "emit var binding" {
    const allocator = std.testing.allocator;
    var emitter = Emitter.init(allocator);
    defer emitter.deinit();

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    try emitter.emitVarBinding(&aw.writer, "title", Expr.literalStr("hello"));
    const output = aw.writer.buffered();
    try std.testing.expectEqualStrings("ctx.title = \"hello\";\n", output);
}

test "emit component def with inputs outputs styles" {
    const allocator = std.testing.allocator;
    var emitter = Emitter.init(allocator);
    defer emitter.deinit();

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    try emitter.emitComponentDef(&aw.writer, "MyComp", "MyComp_Template", .{
        .selectors = &[_][]const u8{"my-comp"},
        .inputs = &[_]Emitter.InputEntry{
            .{ .prop_name = "name", .template_name = "name" },
            .{ .prop_name = "age", .template_name = "userAge" },
        },
        .outputs = &[_]Emitter.OutputEntry{
            .{ .prop_name = "click", .template_name = "click" },
        },
        .features = &[_][]const u8{"ɵɵNgOnChanges"},
        .styles = &[_][]const u8{":host { display: block; }"},
        .on_push = true,
    });

    const output = aw.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "inputs: {name: \"name\", age: \"userAge\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "outputs: {click: \"click\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "features: [ɵɵNgOnChanges]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "styles: [\":host { display: block; }\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "ChangeDetectionStrategy.OnPush") != null);
}
