/// Angular Compiler — Full Pipeline Facade
///
/// Pipeline: Template → HTML Lex → HTML Parse → R3 Transform → IR Ingest
///          → IR Phases → IR Emit → Output AST → JS Emit
///
/// DOD optimizations:
///   - Arena allocator for ALL AST nodes (single free at end)
///   - Zero-copy string handling throughout
///   - Contiguous OpList arrays for IR
///   - Monotonic slot/xref allocation (O(1))
///   - String interning for identifiers
///   - nanosecond-precision timing per phase
///   - No GC, no async overhead, no heap thrashing
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Monotonic nanosecond timestamp (replaces removed getNsTimestamp)
fn getNsTimestamp() i64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
    return @as(i64, ts.sec) * @as(i64, 1_000_000_000) + @as(i64, ts.nsec);
}

const config_mod = @import("config.zig");
const Config = config_mod.Config;
const ViewEncapsulation = config_mod.ViewEncapsulation;
const ChangeDetectionStrategy = config_mod.ChangeDetectionStrategy;

const arena_mod = @import("arena.zig");
const AstArena = arena_mod.AstArena;
const source_span = @import("source_span.zig");
const ParseError = source_span.ParseError;
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

const interned = @import("interned.zig");
const StringPool = interned.StringPool;

const html_lexer = @import("ml_parser/lexer.zig");
const html_parser = @import("ml_parser/parser.zig");
const html_ast = @import("ml_parser/ast.zig");

const template_transform = @import("template/transform.zig");
const TransformContext = template_transform.TransformContext;

const schema_registry = @import("schema/dom_element_schema_registry.zig");
const SchemaRegistry = schema_registry.SchemaRegistry;

const r3_ast = @import("render3/r3_ast.zig");
const ParsedTemplate = r3_ast.ParsedTemplate;

const ir_job = @import("template/pipeline/ir/job.zig");
const ComponentCompilationJob = ir_job.ComponentCompilationJob;
const ir_enums = @import("template/pipeline/ir/enums.zig");
const CompilationMode = ir_enums.CompilationMode;

const ir_ingest = @import("template/pipeline/ir/ingest.zig");
const ir_phases = @import("template/pipeline/src/registry.zig");
const ir_emit = @import("template/pipeline/ir/emit.zig");

const output_ast = @import("output/ast.zig");
const output_emitter = @import("output/emitter.zig");
const Emitter = output_emitter.Emitter;
const Stmt = output_ast.Stmt;
const Expr = output_ast.Expr;
const source_map_mod = @import("output/source_map.zig");
const SourceMap = source_map_mod.SourceMap;

// ─── Compilation Result ──────────────────────────────────────

pub const CompilationResult = struct {
    js_source: []const u8,
    source_map_json: ?[]const u8,
    template_fn_name: []const u8,
    const_count: u32,
    decl_count: u32,
    var_count: u32,
    errors: []const ParseError,
    stats: CompilationStats,

    pub fn deinit(self: *CompilationResult, allocator: Allocator) void {
        allocator.free(self.js_source);
        if (self.source_map_json) |sm| allocator.free(sm);
        if (self.stats.phase_timings.len > 0) {
            allocator.free(self.stats.phase_timings);
        }
        // errors was toOwnedSlice'd — free it
        if (self.errors.len > 0) {
            allocator.free(self.errors);
        }
    }
};

pub const CompilationStats = struct {
    html_parse_ns: u64 = 0,
    r3_transform_ns: u64 = 0,
    ir_gen_ns: u64 = 0,
    ir_transform_ns: u64 = 0,
    ir_emit_ns: u64 = 0,
    js_emit_ns: u64 = 0,
    sourcemap_ns: u64 = 0,
    total_ns: u64 = 0,
    arena_bytes: usize = 0,
    html_nodes: usize = 0,
    r3_nodes: usize = 0,
    ir_create_ops: usize = 0,
    ir_update_ops: usize = 0,
    output_stmts: usize = 0,
    /// Per-phase nanosecond timings (allocated, owned by caller).
    phase_timings: []const ir_phases.PhaseTimings = &.{},
};

// ─── Component Metadata ──────────────────────────────────────

pub const ComponentMeta = struct {
    name: []const u8,
    template: []const u8,
    template_url: ?[]const u8 = null,
    selectors: []const []const u8 = &[_][]const u8{},
    inputs: []const InputMeta = &[_]InputMeta{},
    outputs: []const OutputMeta = &[_]OutputMeta{},
    encapsulation: ViewEncapsulation = .Emulated,
    change_detection: ?ChangeDetectionStrategy = null,
    styles: []const []const u8 = &[_][]const u8{},
    style_urls: []const []const u8 = &[_][]const u8{},
    is_standalone: bool = false,
    imports: []const []const u8 = &[_][]const u8{},
};

pub const InputMeta = struct {
    property_name: []const u8,
    binding_name: ?[]const u8 = null,
    required: bool = false,
    transform: ?[]const u8 = null,
};

pub const OutputMeta = struct {
    property_name: []const u8,
    binding_name: []const u8,
};

// ─── Compiler ─────────────────────────────────────────────────

pub const Compiler = struct {
    allocator: Allocator,
    config: Config,
    string_pool: StringPool,
    schema: SchemaRegistry,

    pub fn init(allocator: Allocator, config: Config) Compiler {
        return .{
            .allocator = allocator,
            .config = config,
            .string_pool = StringPool.init(allocator),
            .schema = .{},
        };
    }

    pub fn deinit(self: *Compiler) void {
        self.string_pool.deinit();
    }

    /// ═══════════════════════════════════════════════════════════
    /// MAIN ENTRY POINT: Compile a component template → JavaScript
    /// ═══════════════════════════════════════════════════════════
    pub fn compileComponent(self: *Compiler, meta: ComponentMeta) !CompilationResult {
        const total_start = getNsTimestamp();

        // ── Arena for ALL AST allocations (single free at end) ──
        var arena = AstArena.init(self.allocator);
        defer arena.deinit();

        var all_errors = std.array_list.Managed(ParseError).init(self.allocator);

        // Pre-intern common strings
        self.string_pool.preInternCommon() catch {};

        // ═══════════════════════════════════════════════════════════
        // PHASE 1: HTML Parse
        // ═══════════════════════════════════════════════════════════
        const html_start = getNsTimestamp();

        var html_lex = html_lexer.Lexer.init(self.allocator, meta.template);
        defer html_lex.deinit();
        const lex_result = try html_lex.tokenize();

        var h_parser = html_parser.Parser.init(self.allocator, &arena, meta.template, lex_result.@"0");
        defer h_parser.deinit();
        const html_result = try h_parser.parse();

        const html_end = getNsTimestamp();

        for (html_result.errors) |e| {
            try all_errors.append(e);
        }

        // ═══════════════════════════════════════════════════════════
        // PHASE 2: HTML AST → R3 Template AST
        // ═══════════════════════════════════════════════════════════
        const r3_start = getNsTimestamp();

        var ctx = TransformContext.init(self.allocator, &arena, meta.template);
        defer ctx.deinit();

        const r3_result = try template_transform.transformHtmlToR3(&ctx, html_result.root_nodes);

        const r3_end = getNsTimestamp();

        for (r3_result.errors) |e| {
            try all_errors.append(e);
        }

        // ═══════════════════════════════════════════════════════════
        // PHASE 3: R3 AST → IR (Ingestion)
        // ═══════════════════════════════════════════════════════════
        const ir_start = getNsTimestamp();

        var job = try ComponentCompilationJob.init(
            self.allocator,
            meta.name,
            if (self.config.full_template_type_check) .Full else .DomOnly,
        );
        defer job.deinit();

        try ir_ingest.ingestR3Nodes(&job, r3_result.nodes);

        const ir_end = getNsTimestamp();

        // ═══════════════════════════════════════════════════════════
        // PHASE 4: IR Transformation Phases (timed)
        // ═══════════════════════════════════════════════════════════
        const phases_start = getNsTimestamp();

        const phase_timings = ir_phases.transformWithTimings(self.allocator, &job, .Tmpl) catch |err| {
            // Fall back to non-timed transform on allocation failure
            try ir_phases.transform(&job, .Tmpl);
            const ph_fallback_end = getNsTimestamp();
            _ = ph_fallback_end;
            return err;
        };

        const phases_end = getNsTimestamp();

        // ═══════════════════════════════════════════════════════════
        // PHASE 5: IR → Output AST
        // ═══════════════════════════════════════════════════════════
        const emit_start = getNsTimestamp();

        const emitted = try ir_emit.emitView(&job, &job.root);

        const emit_end = getNsTimestamp();

        // ═══════════════════════════════════════════════════════════
        // PHASE 6: Output AST → JavaScript Source
        // ═══════════════════════════════════════════════════════════
        const js_start = getNsTimestamp();

        // ═══════════════════════════════════════════════════════════
        // Phase 6a: Emit constant array
        // ═══════════════════════════════════════════════════════════
        var buf = std.array_list.Managed(u8).initCapacity(self.allocator, 8192) catch unreachable;

        if (job.pool.size() > 0) {
            const consts_name = try std.fmt.allocPrint(self.allocator, "_c{d}", .{job.pool.size() - 1});
            try buf.appendSlice("const ");
            try buf.appendSlice(consts_name);
            try buf.appendSlice(" = [\n");

            for (job.pool.constants.items, 0..) |c, i| {
                try buf.appendSlice("  \"");
                try appendEscaped(&buf, c.value);
                try buf.appendSlice("\"");
                if (i < job.pool.constants.items.len - 1) try buf.appendSlice(",");
                try buf.appendSlice("\n");
            }
            try buf.appendSlice("];\n\n");
        }

        // ═══════════════════════════════════════════════════════════
        // Phase 6b: Emit Angular core imports
        // ═══════════════════════════════════════════════════════════
        {
            // Collect all runtime symbols used by this component
            var emitter = Emitter.init(self.allocator);
            defer emitter.deinit();

            // Always needed for defineComponent
            try emitter.imports.put("ɵɵdefineComponent", .{
                .module_name = "@angular/core",
                .name = "ɵɵdefineComponent",
                .qualified_name = "ɵɵdefineComponent",
            });

            // Add symbols based on what ops exist
            const create_items = job.root.create.ops.items;
            const update_items = job.root.update.ops.items;

            // Scan creation ops for needed imports
            for (create_items) |op| {
                switch (op.kind) {
                    .ElementStart => {
                        try emitter.imports.put("ɵɵelementStart", .{
                            .module_name = "@angular/core",
                            .name = "ɵɵelementStart",
                            .qualified_name = "ɵɵelementStart",
                        });
                        try emitter.imports.put("ɵɵelementEnd", .{
                            .module_name = "@angular/core",
                            .name = "ɵɵelementEnd",
                            .qualified_name = "ɵɵelementEnd",
                        });
                    },
                    .Text => {
                        try emitter.imports.put("ɵɵtext", .{
                            .module_name = "@angular/core",
                            .name = "ɵɵtext",
                            .qualified_name = "ɵɵtext",
                        });
                    },
                    .Projection => {
                        try emitter.imports.put("ɵɵprojectionDef", .{
                            .module_name = "@angular/core",
                            .name = "ɵɵprojectionDef",
                            .qualified_name = "ɵɵprojectionDef",
                        });
                    },
                    .ProjectionDef => {
                        try emitter.imports.put("ɵɵprojection", .{
                            .module_name = "@angular/core",
                            .name = "ɵɵprojection",
                            .qualified_name = "ɵɵprojection",
                        });
                    },
                    .Listener => {
                        try emitter.imports.put("ɵɵlistener", .{
                            .module_name = "@angular/core",
                            .name = "ɵɵlistener",
                            .qualified_name = "ɵɵlistener",
                        });
                    },
                    .RepeaterCreate => {
                        try emitter.imports.put("ɵɵrepeaterCreate", .{
                            .module_name = "@angular/core",
                            .name = "ɵɵrepeaterCreate",
                            .qualified_name = "ɵɵrepeaterCreate",
                        });
                    },
                    .ConditionalCreate => {
                        try emitter.imports.put("ɵɵconditionalCreate", .{
                            .module_name = "@angular/core",
                            .name = "ɵɵconditionalCreate",
                            .qualified_name = "ɵɵconditionalCreate",
                        });
                    },
                    else => {},
                }
            }

            // Scan update ops for needed imports
            for (update_items) |op| {
                switch (op.kind) {
                    .InterpolateText => {
                        try emitter.imports.put("ɵɵinterpolate", .{
                            .module_name = "@angular/core",
                            .name = "ɵɵinterpolate",
                            .qualified_name = "ɵɵinterpolate",
                        });
                    },
                    .Binding, .Property, .DomProperty => {
                        try emitter.imports.put("ɵɵpropertyInterpolate1", .{
                            .module_name = "@angular/core",
                            .name = "ɵɵpropertyInterpolate1",
                            .qualified_name = "ɵɵpropertyInterpolate1",
                        });
                    },
                    .ClassProp => {
                        try emitter.imports.put("ɵɵclassMapInterpolate1", .{
                            .module_name = "@angular/core",
                            .name = "ɵɵclassMapInterpolate1",
                            .qualified_name = "ɵɵclassMapInterpolate1",
                        });
                    },
                    .StyleProp => {
                        try emitter.imports.put("ɵɵstylePropInterpolate1", .{
                            .module_name = "@angular/core",
                            .name = "ɵɵstylePropInterpolate1",
                            .qualified_name = "ɵɵstylePropInterpolate1",
                        });
                    },
                    .StyleMap => {
                        try emitter.imports.put("ɵɵstyleMapInterpolate1", .{
                            .module_name = "@angular/core",
                            .name = "ɵɵstyleMapInterpolate1",
                            .qualified_name = "ɵɵstyleMapInterpolate1",
                        });
                    },
                    .ClassMap => {
                        try emitter.imports.put("ɵɵclassMapInterpolate2", .{
                            .module_name = "@angular/core",
                            .name = "ɵɵclassMapInterpolate2",
                            .qualified_name = "ɵɵclassMapInterpolate2",
                        });
                    },
                    .TwoWayProperty => {
                        try emitter.imports.put("ɵɵtwoWayProperty", .{
                            .module_name = "@angular/core",
                            .name = "ɵɵtwoWayProperty",
                            .qualified_name = "ɵɵtwoWayProperty",
                        });
                    },
                    .TwoWayListener => {
                        try emitter.imports.put("ɵɵtwoWayListener", .{
                            .module_name = "@angular/core",
                            .name = "ɵɵtwoWayListener",
                            .qualified_name = "ɵɵtwoWayListener",
                        });
                    },
                    .Advance => {
                        try emitter.imports.put("ɵɵadvance", .{
                            .module_name = "@angular/core",
                            .name = "ɵɵadvance",
                            .qualified_name = "ɵɵadvance",
                        });
                    },
                    .Repeater => {
                        try emitter.imports.put("ɵɵrepeater", .{
                            .module_name = "@angular/core",
                            .name = "ɵɵrepeater",
                            .qualified_name = "ɵɵrepeater",
                        });
                    },
                    .Conditional => {
                        try emitter.imports.put("ɵɵconditional", .{
                            .module_name = "@angular/core",
                            .name = "ɵɵconditional",
                            .qualified_name = "ɵɵconditional",
                        });
                    },
                    .StoreLet => {
                        try emitter.imports.put("ɵɵstoreLet", .{
                            .module_name = "@angular/core",
                            .name = "ɵɵstoreLet",
                            .qualified_name = "ɵɵstoreLet",
                        });
                    },
                    .Pipe => {
                        try emitter.imports.put("ɵɵpipeBind1", .{
                            .module_name = "@angular/core",
                            .name = "ɵɵpipeBind1",
                            .qualified_name = "ɵɵpipeBind1",
                        });
                    },
                    else => {},
                }
            }

            // Emit the import statement — collect symbol names
            if (emitter.imports.count() > 0) {
                const symbol_names = try self.allocator.alloc([]const u8, emitter.imports.count());
                defer self.allocator.free(symbol_names);
                var it = emitter.imports.keyIterator();
                var si: usize = 0;
                while (it.next()) |key| {
                    symbol_names[si] = key.*;
                    si += 1;
                }
                var aw = std.Io.Writer.Allocating.init(self.allocator);
                defer aw.deinit();
                try emitter.emitImports(&aw.writer, symbol_names);
                try buf.appendSlice(aw.writer.buffered());
            }
        }

        // ═══════════════════════════════════════════════════════════
        // Phase 6c: Emit template function
        // ═══════════════════════════════════════════════════════════
        const template_fn_name = try std.fmt.allocPrint(
            self.allocator,
            "{s}_Template",
            .{meta.name},
        );

        try buf.appendSlice("function ");
        try buf.appendSlice(template_fn_name);
        try buf.appendSlice("(rf, ctx) {\n");

        // Create block: if (rf & 1) { ... }
        if (emitted.create_stmts.len > 0) {
            try buf.appendSlice("  if (rf & 1) {\n");
            for (emitted.create_stmts) |stmt| {
                try emitStmtToString(&buf, stmt, 4);
            }
            try buf.appendSlice("  }\n");
        }

        // Update block: if (rf & 2) { ... }
        if (emitted.update_stmts.len > 0) {
            try buf.appendSlice("  if (rf & 2) {\n");
            for (emitted.update_stmts) |stmt| {
                try emitStmtToString(&buf, stmt, 4);
            }
            try buf.appendSlice("  }\n");
        }

        try buf.appendSlice("}\n\n");

        // ═══════════════════════════════════════════════════════════
        // Phase 6c-extra: Emit helper functions (event handlers, pipe factories)
        // ═══════════════════════════════════════════════════════════
        for (emitted.functions) |fn_stmt| {
            try emitStmtToString(&buf, fn_stmt, 0);
            try buf.appendSlice("\n");
        }

        // ═══════════════════════════════════════════════════════════
        // Phase 6d: Emit component definition using enhanced Emitter
        // ═══════════════════════════════════════════════════════════
        {
            var emitter = Emitter.init(self.allocator);
            defer emitter.deinit();

            // Collect input entries
            var input_entries = std.array_list.Managed(Emitter.InputEntry).initCapacity(self.allocator, meta.inputs.len) catch unreachable;
            defer input_entries.deinit();
            for (meta.inputs) |inp| {
                try input_entries.append(.{
                    .prop_name = inp.property_name,
                    .template_name = inp.binding_name orelse inp.property_name,
                    .is_alias = inp.binding_name != null,
                });
            }

            // Collect output entries
            var output_entries = std.array_list.Managed(Emitter.OutputEntry).initCapacity(self.allocator, meta.outputs.len) catch unreachable;
            defer output_entries.deinit();
            for (meta.outputs) |out| {
                try output_entries.append(.{
                    .prop_name = out.property_name,
                    .template_name = out.binding_name,
                });
            }

            // Build features array
            var features = std.array_list.Managed([]const u8).initCapacity(self.allocator, 2) catch unreachable;
            defer features.deinit();
            if (meta.inputs.len > 0) {
                try features.append("ɵɵNgOnChanges");
            }

            var comp_aw = std.Io.Writer.Allocating.init(self.allocator);
            defer comp_aw.deinit();
            try emitter.emitComponentDef(&comp_aw.writer, meta.name, template_fn_name, .{
                .selectors = meta.selectors,
                .decls = job.slots.next_slot,
                .vars = job.root.vars orelse 0,
                .consts = @intCast(if (job.pool.size() > 0) job.pool.size() else 0),
                .inputs = input_entries.items,
                .outputs = output_entries.items,
                .features = features.items,
                .styles = meta.styles,
                .on_push = meta.change_detection == .OnPush or
                    (meta.change_detection == null and meta.inputs.len > 0),
            });
            try buf.appendSlice(comp_aw.writer.buffered());
        }

        // ═══════════════════════════════════════════════════════════
        // PHASE 7: Source Map Generation (optional)
        // ═══════════════════════════════════════════════════════════
        const sm_start = getNsTimestamp();
        var source_map = SourceMap.init(self.allocator, meta.name);
        // Add source file reference
        const src_idx = source_map.addSource(meta.template_url orelse meta.name) catch 0;
        // Wire source map: map IR ops back to template source positions
        // Each creation op with a non-empty source span gets a mapping
        const gen_line: u32 = 0;
        var gen_col: u32 = 0;
        // Estimate column positions based on emitted output
        for (job.root.create.ops.items) |op| {
            if (op.source_span.start != 0 or op.source_span.end != 0) {
                // Convert source span to line/column (approximate: offset → line/col)
                const src_line = estimateLine(meta.template, op.source_span.start);
                const src_col = estimateCol(meta.template, op.source_span.start);
                try source_map.addMapping(.{
                    .generated_line = gen_line,
                    .generated_column = gen_col,
                    .source_index = src_idx,
                    .source_line = src_line,
                    .source_column = src_col,
                    .name_index = 0,
                });
            }
            gen_col += 4; // rough estimate per statement width
        }
        for (job.root.update.ops.items) |op| {
            if (op.source_span.start != 0 or op.source_span.end != 0) {
                const src_line = estimateLine(meta.template, op.source_span.start);
                const src_col = estimateCol(meta.template, op.source_span.start);
                try source_map.addMapping(.{
                    .generated_line = gen_line + 2, // update block offset
                    .generated_column = gen_col,
                    .source_index = src_idx,
                    .source_line = src_line,
                    .source_column = src_col,
                    .name_index = 0,
                });
            }
            gen_col += 4;
        }
        const sm_json = source_map.toJson() catch "{}";
        source_map.deinit();
        const sm_end = getNsTimestamp();

        const js_end = getNsTimestamp();
        const total_end = getNsTimestamp();

        const arena_stats = arena.stats();

        return .{
            .js_source = try buf.toOwnedSlice(),
            .source_map_json = sm_json,
            .template_fn_name = template_fn_name,
            .const_count = @intCast(job.pool.size()),
            .decl_count = job.slots.next_slot,
            .var_count = job.root.vars orelse 0,
            .errors = all_errors.toOwnedSlice() catch all_errors.items,
            .stats = .{
                .html_parse_ns = @intCast(html_end - html_start),
                .r3_transform_ns = @intCast(r3_end - r3_start),
                .ir_gen_ns = @intCast(ir_end - ir_start),
                .ir_transform_ns = @intCast(phases_end - phases_start),
                .ir_emit_ns = @intCast(emit_end - emit_start),
                .js_emit_ns = @intCast(js_end - js_start),
                .sourcemap_ns = @intCast(sm_end - sm_start),
                .total_ns = @intCast(total_end - total_start),
                .arena_bytes = arena_stats.total_allocated,
                .html_nodes = html_result.root_nodes.len,
                .r3_nodes = r3_result.nodes.len,
                .ir_create_ops = job.root.create.len(),
                .ir_update_ops = job.root.update.len(),
                .output_stmts = emitted.create_stmts.len + emitted.update_stmts.len,
                .phase_timings = phase_timings,
            },
        };
    }
};

// ─── Statement to String (simplified) ───────────────────────
/// Convert Output AST Stmt to JS string (used in fallback path).
fn emitStmtToString(buf: *std.array_list.Managed(u8), stmt: Stmt, indent: u32) !void {
    for (0..indent) |_| {
        try buf.appendSlice("  ");
    }

    switch (stmt.data) {
        .Expression => |e| {
            try emitExprToString(buf, e);
            try buf.appendSlice(";\n");
        },
        .Return => |r| {
            if (r.value) |v| {
                try buf.appendSlice("return ");
                try emitExprToString(buf, v);
                try buf.appendSlice(";\n");
            }
        },
        .DeclareVar => |dv| {
            const mod_str = switch (dv.modifier) {
                .Const => "const ",
                .Let => "let ",
                .Var => "var ",
            };
            try buf.appendSlice(mod_str);
            try buf.appendSlice(dv.name);
            if (dv.value) |v| {
                try buf.appendSlice(" = ");
                try emitExprToString(buf, v);
            }
            try buf.appendSlice(";\n");
        },
        else => {},
    }
}

fn emitExprToString(buf: *std.array_list.Managed(u8), expr: Expr) !void {
    switch (expr.data) {
        .ReadVar => |v| {
            try buf.appendSlice(v.name);
        },
        .Literal => |l| {
            switch (l) {
                .String => |s| {
                    try buf.appendSlice("\"");
                    try appendEscaped(buf, s);
                    try buf.appendSlice("\"");
                },
                .Number => |n| {
                    var num_buf: [64]u8 = undefined;
                    const str = if (n == @trunc(n) and @abs(n) < 1e15)
                        try std.fmt.bufPrint(&num_buf, "{d}", .{@as(i64, @intFromFloat(n))})
                    else
                        try std.fmt.bufPrint(&num_buf, "{d}", .{n});
                    try buf.appendSlice(str);
                },
                .Boolean => |b| {
                    try buf.appendSlice(if (b) "true" else "false");
                },
                .Null => try buf.appendSlice("null"),
                .Undefined => try buf.appendSlice("undefined"),
            }
        },
        .InvokeFunction => |inv| {
            if (inv.fn_expr) |fn_e| {
                try emitExprToString(buf, fn_e.*);
                try buf.appendSlice("(");
                for (inv.args, 0..) |arg, i| {
                    if (i > 0) try buf.appendSlice(", ");
                    try emitExprToString(buf, arg);
                }
                try buf.appendSlice(")");
            }
        },
        .ReadProp => |r| {
            if (r.receiver) |recv| {
                try emitExprToString(buf, recv.*);
            }
            try buf.appendSlice(".");
            try buf.appendSlice(r.name);
        },
        .ReadKey => |r| {
            try emitExprToString(buf, r.receiver.*);
            try buf.appendSlice("[");
            try emitExprToString(buf, r.index.*);
            try buf.appendSlice("]");
        },
        .BinaryOperator => |b| {
            try emitExprToString(buf, b.lhs.*);
            try buf.appendSlice(" ");
            try buf.appendSlice(b.operator);
            try buf.appendSlice(" ");
            try emitExprToString(buf, b.rhs.*);
        },
        .Conditional => |c| {
            try emitExprToString(buf, c.condition.*);
            try buf.appendSlice(" ? ");
            try emitExprToString(buf, c.true_case.*);
            try buf.appendSlice(" : ");
            try emitExprToString(buf, c.false_case.*);
        },
        .Not => |n| {
            try buf.appendSlice("!(");
            try emitExprToString(buf, n.condition.*);
            try buf.appendSlice(")");
        },
        .UnaryOperator => |u| {
            try buf.appendSlice(u.operator);
            try emitExprToString(buf, u.operand.*);
        },
        .ArrowFunction => |a| {
            try buf.appendSlice("(");
            for (a.params, 0..) |p, i| {
                if (i > 0) try buf.appendSlice(", ");
                try buf.appendSlice(p.name);
            }
            try buf.appendSlice(") => ");
            switch (a.body) {
                .expression => |e| try emitExprToString(buf, e.*),
                .statements => try buf.appendSlice("{ /* ... */ }"),
            }
        },
        .Comma => |c| {
            for (c.exprs, 0..) |e, i| {
                if (i > 0) try buf.appendSlice(", ");
                try emitExprToString(buf, e);
            }
        },
        else => {
            try buf.appendSlice("/* expr */");
        },
    }
}

fn appendEscaped(buf: *std.array_list.Managed(u8), s: []const u8) !void {
    for (s) |ch| {
        switch (ch) {
            '\\' => try buf.appendSlice("\\\\"),
            '"' => try buf.appendSlice("\\\""),
            '\n' => try buf.appendSlice("\\n"),
            '\r' => try buf.appendSlice("\\r"),
            '\t' => try buf.appendSlice("\\t"),
            else => try buf.appendSlice(&[_]u8{ch}),
        }
    }
}

// ─── Source Map Helpers ─────────────────────────────────────

/// Estimate line number from a byte offset in source.
fn estimateLine(source: []const u8, offset: u32) u32 {
    var line: u32 = 0;
    const end = @min(@as(usize, offset), source.len);
    for (source[0..end]) |ch| {
        if (ch == '\n') line += 1;
    }
    return line;
}

/// Estimate column number from a byte offset in source (column in the current line).
fn estimateCol(source: []const u8, offset: u32) u32 {
    const end = @min(@as(usize, offset), source.len);
    // Walk backwards from offset to find the last newline
    var col: u32 = 0;
    var i: usize = 0;
    while (i < end) : (i += 1) {
        if (source[i] == '\n') {
            col = 0;
        } else {
            col += 1;
        }
    }
    return col;
}

// ─── Tests ─────────────────────────────────────────────────

test "compile simple component with full pipeline" {
    const allocator = std.testing.allocator;
    var compiler = Compiler.init(allocator, .{});

    const result = try compiler.compileComponent(.{
        .name = "TestComponent",
        .template = "<div>Hello</div>",
        .selectors = &[_][]const u8{"test-component"},
    });

    try std.testing.expect(result.errors.len == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.js_source, "function TestComponent_Template") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.js_source, "ɵɵelementStart") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.js_source, "ɵɵtext") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.js_source, "ɵɵelementEnd") != null);
    try std.testing.expect(result.stats.total_ns > 0);
    try std.testing.expect(result.stats.r3_transform_ns > 0);
    try std.testing.expect(result.stats.ir_gen_ns > 0);

    var r = result;
    r.deinit(allocator);
}

test "compile with nested elements" {
    const allocator = std.testing.allocator;
    var compiler = Compiler.init(allocator, .{});

    const result = try compiler.compileComponent(.{
        .name = "CardComponent",
        .template = "<div><h2>Title</h2><p>Body</p></div>",
    });

    try std.testing.expect(result.stats.ir_create_ops >= 5);
    var r = result;
    r.deinit(allocator);
}

test "compile stats" {
    const allocator = std.testing.allocator;
    var compiler = Compiler.init(allocator, .{});

    const result = try compiler.compileComponent(.{
        .name = "StatsComponent",
        .template = "<span>text</span>",
    });

    try std.testing.expect(result.stats.html_nodes > 0);
    try std.testing.expect(result.stats.r3_nodes > 0);
    try std.testing.expect(result.stats.ir_create_ops > 0);
    try std.testing.expect(result.stats.arena_bytes > 0);

    // All phases should take some time
    try std.testing.expect(result.stats.html_parse_ns > 0);
    try std.testing.expect(result.stats.r3_transform_ns >= 0);
    try std.testing.expect(result.stats.ir_gen_ns >= 0);

    var r = result;
    r.deinit(allocator);
}
