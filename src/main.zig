/// Angular Compiler — Zig Implementation
///
/// Tận dụng tối đa sức mạnh compile-time của Zig:
///   - comptime tagged unions thay vì class hierarchies
///   - comptime visitor pattern type-safe
///   - Arena allocator cho zero-fragmentation AST allocation
///   - Interned strings qua comptime hash map
///   - Zero-copy string slicing ([]const u8)
///   - Generic data structures từ std lib
///
/// Compilation pipeline:
///   Template string → HTML Lexer → HTML AST → R3 AST → IR → ~60 phases → Output JS
pub const std = @import("std");

// ─── Public API ───────────────────────────────────────────────
pub const Compiler = @import("compiler.zig").Compiler;
pub const Config = @import("config.zig");
pub const ComponentMeta = @import("compiler.zig").ComponentMeta;
pub const CompilationResult = @import("compiler.zig").CompilationResult;
pub const InputMeta = @import("compiler.zig").InputMeta;
pub const OutputMeta = @import("compiler.zig").OutputMeta;

// ─── Core Infrastructure ──────────────────────────────────────
pub const source_span = @import("source_span.zig");
pub const chars = @import("chars.zig");
pub const interned = @import("interned.zig");
pub const arena = @import("arena.zig");

// ─── Expression Parser ────────────────────────────────────────
pub const expr = struct {
    pub const Ast = @import("expr/ast.zig");
    pub const Lexer = @import("expr/lexer.zig");
    pub const Parser = @import("expr/parser.zig");
    pub const Serializer = @import("expr/serializer.zig");
};

// ─── HTML/ML Parser ───────────────────────────────────────────
pub const html = struct {
    pub const Ast = @import("html/ast.zig");
    pub const Lexer = @import("html/lexer.zig");
    pub const Parser = @import("html/parser.zig");
    pub const Tags = @import("html/tags.zig");
    pub const Entities = @import("html/entities.zig");
};

// ─── Template Parser ──────────────────────────────────────────
pub const template = struct {
    pub const BindingParser = @import("template/binding_parser.zig");
    pub const Preparser = @import("template/preparser.zig");
    pub const Transform = @import("template/transform.zig");
};

// ─── R3 Template AST (Ivy) ───────────────────────────────────
pub const r3_ast = @import("render3/r3_ast.zig");
pub const r3_identifiers = @import("render3/identifiers.zig");
pub const r3_query = @import("render3/query.zig");

// ─── IR (Intermediate Representation) ─────────────────────────
pub const ir = struct {
    pub const enums = @import("ir/enums.zig");
    pub const expression = @import("ir/expression.zig");
    pub const ops = @import("ir/ops.zig");
    pub const job = @import("ir/job.zig");
    pub const ingest = @import("ir/ingest.zig");
    pub const conversion = @import("ir/conversion.zig");
    pub const phases = @import("ir/phases.zig");
    pub const emit = @import("ir/emit.zig");
    pub const reify = @import("ir/reify.zig");
};

// ─── Directive Matching & T2 Binder ────────────────────────────
pub const directive_matching = @import("directive_matching.zig");
pub const t2_binder = @import("t2_binder.zig");

// ─── Output / Code Generation ─────────────────────────────────
pub const output = struct {
    pub const Ast = @import("output/ast.zig");
    pub const Emitter = @import("output/emitter.zig");
    pub const SourceMap = @import("output/source_map.zig");
};

// ─── Schema (DOM element definitions) ─────────────────────────
pub const schema = @import("schema/registry.zig");

// ─── Type Checking ─────────────────────────────────────────────
pub const type_checker = @import("type_checker.zig");

// ─── i18n (Internationalization) ────────────────────────────────
pub const i18n = @import("i18n.zig");

// ─── Pipe Compilation ───────────────────────────────────────────
pub const pipe_compiler = @import("pipe_compiler.zig");

test {
    std.testing.refAllDecls(@This());
    _ = @import("source_span.zig");
    _ = @import("chars.zig");
    _ = @import("interned.zig");
    _ = @import("arena.zig");
    _ = @import("config.zig");
    _ = @import("expr/ast.zig");
    _ = @import("expr/lexer.zig");
    _ = @import("expr/parser.zig");
    _ = @import("html/ast.zig");
    _ = @import("html/lexer.zig");
    _ = @import("html/parser.zig");
    _ = @import("html/tags.zig");
    _ = @import("template/binding_parser.zig");
    _ = @import("render3/r3_ast.zig");
    _ = @import("ir/enums.zig");
    _ = @import("ir/expression.zig");
    _ = @import("ir/ops.zig");
    _ = @import("ir/job.zig");
    _ = @import("output/ast.zig");
    _ = @import("output/emitter.zig");
    _ = @import("output/source_map.zig");
    _ = @import("template/transform.zig");
    _ = @import("template/preparser.zig");
    _ = @import("ir/ingest.zig");
    _ = @import("ir/phases.zig");
    _ = @import("ir/emit.zig");
    _ = @import("ir/conversion.zig");
    _ = @import("schema/registry.zig");
    _ = @import("html/entities.zig");
    _ = @import("expr/serializer.zig");
    _ = @import("type_checker.zig");
    _ = @import("i18n.zig");
    _ = @import("pipe_compiler.zig");
    _ = @import("compiler.zig");
    _ = @import("render3/identifiers.zig");
    _ = @import("render3/query.zig");
    _ = @import("ir/reify.zig");
    _ = @import("directive_matching.zig");
    _ = @import("t2_binder.zig");
}
