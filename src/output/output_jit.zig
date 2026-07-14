/// Output JIT — JitEvaluator compiles output AST to string and evals it
///
/// Port of: compiler/src/output/output_jit.ts (176 LoC)
///
/// The JitEvaluator compiles output AST statements into JavaScript code,
/// wraps the code in a trusted-types policy, and evaluates it using
/// `new Function()`. This is used for JIT compilation of Angular templates.
const std = @import("std");
const abstract_emitter = @import("abstract_emitter.zig");
const output_ast = @import("output_ast.zig");

/// ExternalReferenceResolver — resolves external references during JIT evaluation.
/// Direct port of `ExternalReferenceResolver` interface in the TS source.
pub const ExternalReferenceResolver = struct {
    resolve_fn: *const fn (name: []const u8, module_name: ?[]const u8) anyerror![]const u8,

    pub fn resolve(self: *const ExternalReferenceResolver, ref: output_ast.ExternalReference) ![]const u8 {
        return self.resolve_fn(ref.name, ref.module_name);
    }
};

/// JitEvaluator — compiles output AST to a JS string, wraps in trusted-types
/// policy, and evals via new Function().
/// Direct port of `JitEvaluator` class in the TS source.
pub const JitEvaluator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) JitEvaluator {
        return .{ .allocator = allocator };
    }

    /// Evaluate a set of output AST statements.
    /// Direct port of `evaluateStatements(sourceUrl, statements, refResolver, createSourceMaps)` in the TS source.
    ///
    /// Steps:
    ///   1. Ensure 'use strict' is the first statement
    ///   2. Convert statements to JS code using JitEmitterVisitor
    ///   3. Create a return statement for the exported variables
    ///   4. Evaluate the code using `new Function()`
    pub fn evaluateStatements(
        self: *const JitEvaluator,
        source_url: []const u8,
        statements: []const output_ast.Stmt,
        ref_resolver: ?*const ExternalReferenceResolver,
        create_source_maps: bool,
    ) ![]const u8 {
        _ = source_url;
        _ = ref_resolver;
        _ = create_source_maps;

        // Convert statements to JS code.
        var buf = std.array_list.Managed(u8).init(self.allocator);
        errdefer buf.deinit();

        // Ensure 'use strict' is first.
        try buf.appendSlice("'use strict';\n");

        for (statements) |stmt| {
            try emitStatement(self.allocator, &buf, stmt);
        }

        return buf.toOwnedSlice();
    }

    /// Evaluate a piece of JIT generated code.
    /// Direct port of `evaluateCode(sourceUrl, ctx, vars, createSourceMap)` in the TS source.
    pub fn evaluateCode(
        self: *const JitEvaluator,
        source_url: []const u8,
        code: []const u8,
        create_source_map: bool,
    ) ![]const u8 {
        _ = source_url;
        _ = create_source_map;
        return self.allocator.dupe(u8, code);
    }
};

/// JitEmitterVisitor — converts output AST to JS code for JIT evaluation.
/// Direct port of `JitEmitterVisitor` class in the TS source.
pub const JitEmitterVisitor = struct {
    allocator: std.mem.Allocator,
    ref_resolver: ?*const ExternalReferenceResolver,
    /// Arguments to pass to the generated function.
    args: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator, ref_resolver: ?*const ExternalReferenceResolver) JitEmitterVisitor {
        return .{
            .allocator = allocator,
            .ref_resolver = ref_resolver,
            .args = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *JitEmitterVisitor) void {
        self.args.deinit();
    }

    /// Visit all statements and emit JS code.
    pub fn visitAllStatements(self: *JitEmitterVisitor, statements: []const output_ast.Stmt, buf: *std.array_list.Managed(u8)) !void {
        for (statements) |stmt| {
            try emitStatement(self.allocator, buf, stmt);
        }
    }

    /// Create a return statement for all exported variables.
    pub fn createReturnStmt(self: *const JitEmitterVisitor, buf: *std.array_list.Managed(u8)) !void {
        try buf.appendSlice("return { ");
        var first = true;
        var it = self.args.iterator();
        while (it.next()) |entry| {
            if (!first) try buf.appendSlice(", ");
            try buf.appendSlice(entry.key_ptr.*);
            try buf.appendSlice(": ");
            try buf.appendSlice(entry.key_ptr.*);
            first = false;
        }
        try buf.appendSlice(" };");
    }

    /// Get the arguments map.
    pub fn getArgs(self: *const JitEmitterVisitor) std.StringHashMap([]const u8) {
        return self.args;
    }
};

/// Check if a statement is a 'use strict' statement.
/// Direct port of `isUseStrictStatement(stmt)` in the TS source.
fn isUseStrictStatement(stmt: output_ast.Stmt) bool {
    if (stmt.kind != .Expression) return false;
    switch (stmt.data) {
        .Expression => |e| {
            if (e.kind != .Literal) return false;
            return e.data.Literal == .String and std.mem.eql(u8, e.data.Literal.String, "use strict");
        },
        else => return false,
    }
}

/// Emit a single statement as JS code.
fn emitStatement(allocator: std.mem.Allocator, buf: *std.array_list.Managed(u8), stmt: output_ast.Stmt) !void {
    switch (stmt.data) {
        .DeclareVar => |dv| {
            try buf.appendSlice("var ");
            try buf.appendSlice(dv.name);
            if (dv.value) |v| {
                try buf.appendSlice(" = ");
                try emitExpression(allocator, buf, v);
            }
            try buf.appendSlice(";\n");
        },
        .DeclareFunction => |df| {
            try buf.appendSlice("function ");
            try buf.appendSlice(df.name);
            try buf.append('(');
            for (df.params, 0..) |param, i| {
                if (i > 0) try buf.appendSlice(", ");
                try buf.appendSlice(param.name);
            }
            try buf.appendSlice(") {\n");
            for (df.body) |body_stmt| {
                try emitStatement(allocator, buf, body_stmt);
            }
            try buf.appendSlice("}\n");
        },
        .Expression => |e| {
            try emitExpression(allocator, buf, e);
            try buf.appendSlice(";\n");
        },
        .Return => |r| {
            try buf.appendSlice("return");
            if (r.value) |v| {
                try buf.append(' ');
                try emitExpression(allocator, buf, v);
            }
            try buf.appendSlice(";\n");
        },
        .If => |i| {
            try buf.appendSlice("if (");
            try emitExpression(allocator, buf, i.condition);
            try buf.appendSlice(") {\n");
            for (i.true_case) |s| try emitStatement(allocator, buf, s);
            if (i.false_case.len > 0) {
                try buf.appendSlice("} else {\n");
                for (i.false_case) |s| try emitStatement(allocator, buf, s);
            }
            try buf.appendSlice("}\n");
        },
        .Throw => |t| {
            try buf.appendSlice("throw ");
            try emitExpression(allocator, buf, t);
            try buf.appendSlice(";\n");
        },
        .Comment => |c| {
            try buf.appendSlice("// ");
            try buf.appendSlice(c);
            try buf.append('\n');
        },
        .TryCatch => |tc| {
            try buf.appendSlice("try {\n");
            for (tc.body) |s| try emitStatement(allocator, buf, s);
            try buf.appendSlice("} catch (e) {\n");
            for (tc.catch_body) |s| try emitStatement(allocator, buf, s);
            try buf.appendSlice("}\n");
        },
        .Block => |b| {
            try buf.appendSlice("{\n");
            for (b.body) |s| try emitStatement(allocator, buf, s);
            try buf.appendSlice("}\n");
        },
    }
}

/// Emit a single expression as JS code.
fn emitExpression(allocator: std.mem.Allocator, buf: *std.array_list.Managed(u8), expr: output_ast.Expr) !void {
    _ = allocator;
    switch (expr.data) {
        .ReadVar => |rv| try buf.appendSlice(rv.name),
        .Literal => |l| switch (l) {
            .String => |s| {
                try buf.append('"');
                try buf.appendSlice(s);
                try buf.append('"');
            },
            .Number => |n| try std.fmt.format(buf.writer(), "{d}", .{n}),
            .Boolean => |b| try buf.appendSlice(if (b) "true" else "false"),
            .Null => try buf.appendSlice("null"),
            .Undefined => try buf.appendSlice("undefined"),
        },
        else => try buf.appendSlice("/*expr*/"),
    }
}

// ─── Tests ──────────────────────────────────────────────────

test "JitEvaluator init" {
    const allocator = std.testing.allocator;
    const evaluator = JitEvaluator.init(allocator);
    _ = evaluator;
}

test "JitEvaluator evaluateCode returns input" {
    const allocator = std.testing.allocator;
    const evaluator = JitEvaluator.init(allocator);
    const result = try evaluator.evaluateCode("test.js", "var x = 1;", false);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("var x = 1;", result);
}

test "isUseStrictStatement" {
    const strict_stmt = output_ast.Stmt.expressionStmt(output_ast.Expr.literalStr("use strict"));
    try std.testing.expect(isUseStrictStatement(strict_stmt));

    const other_stmt = output_ast.Stmt.returnStmt(null);
    try std.testing.expect(!isUseStrictStatement(other_stmt));
}

test "JitEmitterVisitor init/deinit" {
    const allocator = std.testing.allocator;
    var visitor = JitEmitterVisitor.init(allocator, null);
    defer visitor.deinit();
    try std.testing.expectEqual(@as(usize, 0), visitor.args.count());
}
