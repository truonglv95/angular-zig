/// Pipe Compilation — Angular Pipe Processing
///
/// Handles the pipe compilation pipeline:
///   - Pipe detection in expressions (expr | pipeName:arg1:arg2)
///   - Pipe purity analysis (determines if pipe can be memoized)
///   - Pipe argument validation
///   - Pipe transform function generation for Output AST
///
/// DOD optimizations:
///   - comptime StaticStringMap for known pipe registry (O(1) lookup)
///   - Zero-alloc purity check (all data in compact struct)
///   - Contiguous pipe metadata array
///   - No heap allocation during pipe detection in hot path
const std = @import("std");
const Allocator = std.mem.Allocator;

const expr_ast = @import("../expression_parser/ast.zig");
const Ast = expr_ast.Ast;
const ir_expr = @import("../template/pipeline/ir/expression.zig");
const IrExpr = ir_expr.IrExpr;
const ExpressionKind = @import("../template/pipeline/ir/enums.zig").ExpressionKind;

// ─── Pipe Metadata ───────────────────────────────────────────

pub const PipeDef = struct {
    name: []const u8,
    /// Whether this pipe is pure (same input → same output)
    /// Pure pipes can be memoized across change detection cycles
    pure: bool,
    /// Number of required arguments (excluding the input value)
    min_args: u8,
    /// Maximum number of arguments (255 = unlimited)
    max_args: u8,
    /// Display name for error messages
    display_name: []const u8,
};

// ─── Known Pipe Registry (comptime) ──────────────────────────
/// All built-in Angular pipes with their metadata.
/// DOD: comptime hash map — zero runtime init, O(1) lookup.
const KNOWN_PIPES = std.StaticStringMap(PipeDef).initComptime(.{
    .{ "async", PipeDef{ .name = "async", .pure = true, .min_args = 0, .max_args = 0, .display_name = "AsyncPipe" } },
    .{ "currency", PipeDef{ .name = "currency", .pure = true, .min_args = 0, .max_args = 2, .display_name = "CurrencyPipe" } },
    .{ "date", PipeDef{ .name = "date", .pure = true, .min_args = 0, .max_args = 2, .display_name = "DatePipe" } },
    .{ "decimal", PipeDef{ .name = "decimal", .pure = true, .min_args = 0, .max_args = 2, .display_name = "DecimalPipe" } },
    .{ "percent", PipeDef{ .name = "percent", .pure = true, .min_args = 0, .max_args = 2, .display_name = "PercentPipe" } },
    .{ "json", PipeDef{ .name = "json", .pure = true, .min_args = 0, .max_args = 1, .display_name = "JsonPipe" } },
    .{ "lowercase", PipeDef{ .name = "lowercase", .pure = true, .min_args = 0, .max_args = 0, .display_name = "LowerCasePipe" } },
    .{ "uppercase", PipeDef{ .name = "uppercase", .pure = true, .min_args = 0, .max_args = 0, .display_name = "UpperCasePipe" } },
    .{ "titlecase", PipeDef{ .name = "titlecase", .pure = true, .min_args = 0, .max_args = 0, .display_name = "TitleCasePipe" } },
    .{ "slice", PipeDef{ .name = "slice", .pure = true, .min_args = 1, .max_args = 2, .display_name = "SlicePipe" } },
    .{ "keyvalue", PipeDef{ .name = "keyvalue", .pure = true, .min_args = 0, .max_args = 1, .display_name = "KeyValuePipe" } },
    .{ "i18nSelect", PipeDef{ .name = "i18nSelect", .pure = true, .min_args = 0, .max_args = 0, .display_name = "I18nSelectPipe" } },
    .{ "i18nPlural", PipeDef{ .name = "i18nPlural", .pure = true, .min_args = 0, .max_args = 0, .display_name = "I18nPluralPipe" } },
});

// ─── Pipe Compilation Result ─────────────────────────────────

pub const PipeCompileResult = struct {
    /// The IR expression for the pipe binding
    expr: *IrExpr,
    /// Whether this pipe is pure (can be memoized)
    is_pure: bool,
    /// The pipe name
    name: []const u8,
    /// Argument count
    arg_count: u8,
};

// ─── Pipe Compiler ───────────────────────────────────────────

pub const PipeCompiler = struct {
    allocator: Allocator,
    /// Custom pipes registered at compile time
    custom_pipes: std.StringHashMap(PipeDef),
    /// Track which pipes have been used (for import generation)
    used_pipes: std.StringHashMap(void),

    pub fn init(allocator: Allocator) PipeCompiler {
        return .{
            .allocator = allocator,
            .custom_pipes = std.StringHashMap(PipeDef).init(allocator),
            .used_pipes = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *PipeCompiler) void {
        self.custom_pipes.deinit();
        self.used_pipes.deinit();
    }

    /// Register a custom pipe definition
    pub fn registerPipe(self: *PipeCompiler, def: PipeDef) !void {
        try self.custom_pipes.put(def.name, def);
    }

    /// Look up a pipe by name. Checks custom pipes first, then built-ins.
    /// DOD: O(1) comptime hash lookup for built-ins.
    pub fn lookup(self: *const PipeCompiler, name: []const u8) ?PipeDef {
        if (self.custom_pipes.get(name)) |def| return def;
        return KNOWN_PIPES.get(name);
    }

    /// Check if a pipe is pure (memoizable).
    /// Pure pipes produce the same output for the same input.
    pub fn isPure(self: *const PipeCompiler, name: []const u8) bool {
        if (self.lookup(name)) |def| return def.pure;
        // Unknown pipes default to impure (safe default)
        return false;
    }

    /// Validate pipe argument count against its definition.
    pub fn validateArgs(self: *const PipeCompiler, name: []const u8, arg_count: u8) ?[]const u8 {
        if (self.lookup(name)) |def| {
            if (arg_count < def.min_args) {
                return "Pipe has too few arguments";
            }
            if (def.max_args != 255 and arg_count > def.max_args) {
                return "Pipe has too many arguments";
            }
            return null;
        }
        // Unknown pipe — no validation possible
        return null;
    }

    /// Compile a pipe binding from an expression AST node.
    /// Converts the AST pipe expression into an IR PipeBinding expression.
    pub fn compilePipe(self: *PipeCompiler, pipe_node: *const Ast, job: anytype) !PipeCompileResult {
        const pipe_data = pipe_node.data.BindingPipe;

        // Track usage
        self.used_pipes.put(pipe_data.name, {}) catch {};

        // Import the conversion module for real expression conversion
        const conversion = @import("../template/pipeline/ir/conversion.zig");

        // Convert arguments using the real expression converter
        const ir_args = try job.allocator.alloc(*IrExpr, pipe_data.args.len);
        for (pipe_data.args, 0..) |arg, i| {
            ir_args[i] = try conversion.convertExpr(job, arg);
        }

        // Determine purity
        const is_pure = self.isPure(pipe_data.name);

        // Create the IR expression
        const expr_ptr = try job.allocator.create(IrExpr);
        expr_ptr.* = .{
            .kind = if (is_pure) .PureFunctionExpr else .PipeBinding,
            .span = pipe_node.abs_span,
            .data = .{ .PipeBinding = .{
                .name = pipe_data.name,
                .args = ir_args,
                .pure = is_pure,
            } },
        };

        return .{
            .expr = expr_ptr,
            .is_pure = is_pure,
            .name = pipe_data.name,
            .arg_count = @intCast(pipe_data.args.len),
        };
    }

    /// Get all used pipe names (for import generation).
    /// Returns a contiguous slice of pipe names.
    pub fn getUsedPipeNames(self: *PipeCompiler) ![]const []const u8 {
        const names = try self.allocator.alloc([]const u8, self.used_pipes.count());
        var it = self.used_pipes.keyIterator();
        var i: usize = 0;
        while (it.next()) |key| {
            names[i] = key.*;
            i += 1;
        }
        return names;
    }

    /// Generate pipe import statements for the output.
    /// DOD: Single pass over used pipes, contiguous buffer.
    pub fn generateImports(self: *PipeCompiler) ![]const u8 {
        const names = try self.getUsedPipeNames();
        defer self.allocator.free(names);

        if (names.len == 0) return "";

        // Estimate buffer size
        var buf = std.array_list.Managed(u8).initCapacity(self.allocator, names.len * 80) catch unreachable;

        // Group by module (built-in pipes come from @angular/common)
        for (names) |name| {
            const def = self.lookup(name) orelse continue;
            if (KNOWN_PIPES.has(name)) {
                // Built-in pipe from @angular/common
                try buf.appendSlice("import { ");
                try buf.appendSlice(def.display_name);
                try buf.appendSlice(" } from '@angular/common';\n");
            }
            // Custom pipes are imported via their own modules (handled elsewhere)
        }

        return buf.toOwnedSlice();
    }

    // ═══════════════════════════════════════════════════════════
    // Pipe Chaining Analysis
    // ═══════════════════════════════════════════════════════════

    /// Analyze a chain of pipes and determine if the entire chain is pure.
    /// A pipe chain is pure only if ALL pipes in the chain are pure.
    /// DOD: Linear scan O(n) with early exit on first impure pipe.
    pub fn isChainPure(self: *const PipeCompiler, start_node: *const Ast) bool {
        var current = start_node;
        while (true) {
            if (current.data != .BindingPipe) return true; // Not a pipe = pure
            const pipe = current.data.BindingPipe;
            if (!self.isPure(pipe.name)) return false;
            // Continue to the input expression of this pipe
            current = pipe.exp;
            if (current.data != .BindingPipe) return true;
        }
    }

    /// Count the number of pipes in a chain.
    pub fn countPipesInChain(start_node: *const Ast) u8 {
        var count: u8 = 0;
        var current = start_node;
        while (current.data == .BindingPipe) {
            count += 1;
            current = current.data.BindingPipe.exp;
        }
        return count;
    }
};

// ─── Pipe Transform Generation ───────────────────────────────
/// Generates the ɵɵpipe transform function call for Output AST.
pub const PipeTransformGen = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) PipeTransformGen {
        return .{ .allocator = allocator };
    }

    /// Generate a pipe binding statement for the output AST.
    /// Returns the name of the pipe variable and the call expression source.
    /// Format: ɵɵpipeBind1(0, PipeName, arg1Expr)
    pub fn generatePipeBinding(
        self: *PipeTransformGen,
        slot: u32,
        pipe_name: []const u8,
        arg_count: u8,
    ) ![]const u8 {
        const fn_name = if (arg_count == 0)
            "ɵɵpipe"
        else
            try std.fmt.allocPrint(self.allocator, "ɵɵpipeBind{d}", .{arg_count});

        var aw = std.Io.Writer.Allocating.initCapacity(self.allocator, 128) catch unreachable;
        defer aw.deinit();

        try aw.writer.writeAll(fn_name);
        try aw.writer.writeAll("(");
        try aw.writer.print("{d}", .{slot});
        try aw.writer.writeAll(", ");
        try aw.writer.writeAll(pipe_name);

        // Placeholder for arguments (will be filled by IR emitter)
        for (0..arg_count) |i| {
            try aw.writer.writeAll(", /* arg");
            try aw.writer.print("{d}", .{i});
            try aw.writer.writeAll(" */");
        }

        try aw.writer.writeAll(")");

        if (arg_count > 0) {
            self.allocator.free(fn_name);
        }

        var list = aw.toArrayList();
        return list.toOwnedSlice(self.allocator);
    }
};

// ─── Tests ────────────────────────────────────────────────────

test "KNOWN_PIPES lookup — built-in pipes" {
    var pc = PipeCompiler.init(std.testing.allocator);
    defer pc.deinit();

    const async_pipe = pc.lookup("async").?;
    try std.testing.expect(async_pipe.pure);
    try std.testing.expectEqual(@as(u8, 0), async_pipe.min_args);

    const date_pipe = pc.lookup("date").?;
    try std.testing.expect(date_pipe.pure);
    try std.testing.expectEqual(@as(u8, 2), date_pipe.max_args);

    const slice_pipe = pc.lookup("slice").?;
    try std.testing.expect(slice_pipe.pure);
    try std.testing.expectEqual(@as(u8, 1), slice_pipe.min_args);

    // Non-existent pipe
    try std.testing.expect(pc.lookup("nonexistent") == null);
}

test "register and lookup custom pipe" {
    const allocator = std.testing.allocator;
    var pc = PipeCompiler.init(allocator);
    defer pc.deinit();

    try pc.registerPipe(.{
        .name = "myPipe",
        .pure = true,
        .min_args = 1,
        .max_args = 2,
        .display_name = "MyPipe",
    });

    const def = pc.lookup("myPipe").?;
    try std.testing.expectEqualStrings("myPipe", def.name);
    try std.testing.expect(def.pure);
    try std.testing.expectEqual(@as(u8, 1), def.min_args);
}

test "validateArgs — built-in pipes" {
    var pc = PipeCompiler.init(std.testing.allocator);
    defer pc.deinit();

    // slice requires at least 1 arg
    try std.testing.expect(pc.validateArgs("slice", 0) != null);
    try std.testing.expect(pc.validateArgs("slice", 1) == null);
    try std.testing.expect(pc.validateArgs("slice", 2) == null);
    try std.testing.expect(pc.validateArgs("slice", 3) != null);

    // json accepts 0-1 args
    try std.testing.expect(pc.validateArgs("json", 0) == null);
    try std.testing.expect(pc.validateArgs("json", 1) == null);
    try std.testing.expect(pc.validateArgs("json", 2) != null);
}

test "isPure — known pure/impure pipes" {
    var pc = PipeCompiler.init(std.testing.allocator);
    defer pc.deinit();

    try std.testing.expect(pc.isPure("async"));
    try std.testing.expect(pc.isPure("date"));
    try std.testing.expect(pc.isPure("uppercase"));
    try std.testing.expect(pc.isPure("slice"));

    // Unknown pipes default to impure
    try std.testing.expect(!pc.isPure("unknownCustomPipe"));
}

test "isChainPure — all pure chain" {
    const allocator = std.testing.allocator;
    var arena = @import("../arena.zig").AstArena.init(allocator);
    defer arena.deinit();

    const span = @import("../source_span.zig").AbsoluteSourceSpan{ .start = 0, .end = 10 };
    var pc = PipeCompiler.init(allocator);
    defer pc.deinit();

    // Build: "hello" | uppercase | slice:1:2
    var str_lit = Ast.literalString(
        .{ .start = 0, .end = 5 },
        span,
        "hello",
    );
    const pipe1_node = try arena.create(Ast);
    pipe1_node.* = .{
        .span = .{ .start = 0, .end = 10 },
        .abs_span = span,
        .data = .{ .BindingPipe = .{
            .exp = &str_lit,
            .name = "uppercase",
            .args = &[_]*const Ast{},
        } },
    };
    const pipe2_node = try arena.create(Ast);
    pipe2_node.* = .{
        .span = .{ .start = 0, .end = 10 },
        .abs_span = span,
        .data = .{ .BindingPipe = .{
            .exp = pipe1_node,
            .name = "slice",
            .args = &[_]*const Ast{},
        } },
    };

    try std.testing.expect(pc.isChainPure(pipe2_node));
    try std.testing.expectEqual(@as(u8, 2), PipeCompiler.countPipesInChain(pipe2_node));
}

test "generateImports — built-in pipes" {
    const allocator = std.testing.allocator;
    var pc = PipeCompiler.init(allocator);
    defer pc.deinit();

    pc.used_pipes.put("date", {}) catch {};
    pc.used_pipes.put("uppercase", {}) catch {};

    const imports = try pc.generateImports();
    defer allocator.free(imports);

    try std.testing.expect(std.mem.indexOf(u8, imports, "DatePipe") != null);
    try std.testing.expect(std.mem.indexOf(u8, imports, "UpperCasePipe") != null);
    try std.testing.expect(std.mem.indexOf(u8, imports, "@angular/common") != null);
}

test "PipeTransformGen — binding generation" {
    const allocator = std.testing.allocator;
    var gen = PipeTransformGen.init(allocator);

    const no_args = try gen.generatePipeBinding(0, "date", 0);
    defer allocator.free(no_args);
    try std.testing.expect(std.mem.indexOf(u8, no_args, "ɵɵpipe(0, date") != null);

    const one_arg = try gen.generatePipeBinding(1, "slice", 1);
    defer allocator.free(one_arg);
    try std.testing.expect(std.mem.indexOf(u8, one_arg, "ɵɵpipeBind1(1, slice") != null);
}

test "KNOWN_PIPES comptime table" {
    comptime {
        @import("std").testing.expectEqual(@as(usize, 13), KNOWN_PIPES.kvs.len) catch unreachable;
    }
}
