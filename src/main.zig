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
    pub const Ast = @import("expression_parser/ast.zig");
    pub const Lexer = @import("expression_parser/lexer.zig");
    pub const Parser = @import("expression_parser/parser.zig");
    pub const Serializer = @import("expression_parser/serializer.zig");
};

// ─── HTML/ML Parser ───────────────────────────────────────────
pub const html = struct {
    pub const Ast = @import("ml_parser/ast.zig");
    pub const Lexer = @import("ml_parser/lexer.zig");
    pub const Parser = @import("ml_parser/parser.zig");
    pub const Tags = @import("ml_parser/tags.zig");
    pub const Entities = @import("ml_parser/entities.zig");
};

// ─── Template Parser ──────────────────────────────────────────
pub const template = struct {
    pub const BindingParser = @import("template_parser/binding_parser.zig");
    pub const Preparser = @import("template_parser/template_preparser.zig");
    pub const Transform = @import("template/transform.zig");
};

// ─── R3 Template AST (Ivy) ───────────────────────────────────
pub const r3_ast = @import("render3/r3_ast.zig");
pub const r3_identifiers = @import("render3/r3_identifiers.zig");
pub const r3_query = @import("render3/view/query_generation.zig");

// ─── IR (Intermediate Representation) ─────────────────────────
pub const ir = struct {
    pub const enums = @import("template/pipeline/ir/enums.zig");
    pub const expression = @import("template/pipeline/ir/expression.zig");
    pub const ops = @import("template/pipeline/ir/ops.zig");
    pub const job = @import("template/pipeline/ir/job.zig");
    pub const ingest = @import("template/pipeline/ir/ingest.zig");
    pub const conversion = @import("template/pipeline/ir/conversion.zig");
    pub const phases = @import("template/pipeline/src/registry.zig");
    pub const emit = @import("template/pipeline/ir/emit.zig");
    pub const reify = @import("template/pipeline/ir/reify.zig");
};

// ─── Directive Matching & T2 Binder ────────────────────────────
pub const directive_matching = @import("directive_matching.zig");
pub const t2_binder = @import("render3/view/t2_binder.zig");

// ─── Output / Code Generation ─────────────────────────────────
pub const output = struct {
    pub const Ast = @import("output/output_ast.zig");
    pub const Emitter = @import("output/abstract_emitter.zig");
    pub const SourceMap = @import("output/source_map.zig");
};

// ─── Schema (DOM element definitions) ─────────────────────────
pub const schema = @import("schema/dom_element_schema_registry.zig");

// ─── Type Checking ─────────────────────────────────────────────
pub const type_checker = @import("typecheck/type_check_block.zig");

// ─── i18n (Internationalization) ────────────────────────────────
pub const i18n = @import("i18n/index.zig");

// ─── Pipe Compilation ───────────────────────────────────────────
pub const pipe_compiler = @import("render3/r3_pipe_compiler.zig");

test {
    std.testing.refAllDecls(@This());
    _ = @import("source_span.zig");
    _ = @import("chars.zig");
    _ = @import("interned.zig");
    _ = @import("arena.zig");
    _ = @import("config.zig");
    _ = @import("expression_parser/ast.zig");
    _ = @import("expression_parser/lexer.zig");
    _ = @import("expression_parser/parser.zig");
    _ = @import("ml_parser/ast.zig");
    _ = @import("ml_parser/lexer.zig");
    _ = @import("ml_parser/parser.zig");
    _ = @import("ml_parser/tags.zig");
    _ = @import("template_parser/binding_parser.zig");
    _ = @import("render3/r3_ast.zig");
    _ = @import("template/pipeline/ir/enums.zig");
    _ = @import("template/pipeline/ir/expression.zig");
    _ = @import("template/pipeline/ir/ops.zig");
    _ = @import("template/pipeline/ir/job.zig");
    _ = @import("output/output_ast.zig");
    _ = @import("output/abstract_emitter.zig");
    _ = @import("output/source_map.zig");
    _ = @import("template/transform.zig");
    _ = @import("template_parser/template_preparser.zig");
    _ = @import("template/pipeline/ir/ingest.zig");
    _ = @import("template/pipeline/src/registry.zig");
    _ = @import("template/pipeline/src/ingest.zig");
    _ = @import("template/pipeline/src/instruction.zig");
    _ = @import("template/pipeline/src/emit.zig");
    _ = @import("template/pipeline/src/conversion.zig");
    _ = @import("template/pipeline/src/namespaces.zig");
    _ = @import("template/pipeline/ir/emit.zig");
    _ = @import("template/pipeline/ir/conversion.zig");
    _ = @import("schema/dom_element_schema_registry.zig");
    _ = @import("ml_parser/entities.zig");
    _ = @import("expression_parser/serializer.zig");
    _ = @import("typecheck/type_check_block.zig");
    _ = @import("typecheck/api.zig");
    _ = @import("typecheck/expression.zig");
    _ = @import("typecheck/host_bindings.zig");
    _ = @import("typecheck/oob.zig");
    _ = @import("typecheck/ops/events.zig");
    _ = @import("typecheck/ops/inputs.zig");
    _ = @import("typecheck/ops/expression.zig");
    _ = @import("typecheck/ops/directive_constructor.zig");
    _ = @import("typecheck/ops/template.zig");
    _ = @import("typecheck/ops/bindings.zig");
    _ = @import("typecheck/ops/content_projection.zig");
    _ = @import("typecheck/ops/switch_block.zig");
    _ = @import("typecheck/ops/if_block.zig");
    _ = @import("typecheck/ops/codegen.zig");
    _ = @import("typecheck/ops/references.zig");
    _ = @import("typecheck/ops/directive_type.zig");
    _ = @import("typecheck/ops/variables.zig");
    _ = @import("typecheck/ops/for_block.zig");
    _ = @import("typecheck/ops/signal_forms.zig");
    _ = @import("i18n/index.zig");
    _ = @import("i18n/i18n_parser.zig");
    _ = @import("i18n/extractor_merger.zig");
    _ = @import("render3/r3_pipe_compiler.zig");
    _ = @import("render3/r3_control_flow.zig");
    _ = @import("render3/r3_deferred_triggers.zig");
    _ = @import("render3/r3_deferred_blocks.zig");
    _ = @import("render3/r3_template_transform.zig");
    _ = @import("render3/r3_module_compiler.zig");
    _ = @import("render3/r3_factory.zig");
    _ = @import("render3/r3_hmr_compiler.zig");
    _ = @import("render3/r3_class_metadata_compiler.zig");
    _ = @import("render3/view/compiler.zig");
    _ = @import("render3/view/api.zig");
    _ = @import("render3/view/util.zig");
    _ = @import("render3/view/template.zig");
    _ = @import("render3/view/i18n/meta.zig");
    _ = @import("render3/view/i18n/localize_utils.zig");
    _ = @import("render3/view/i18n/get_msg_utils.zig");
    _ = @import("render3/partial/api.zig");
    _ = @import("render3/partial/directive.zig");
    _ = @import("render3/partial/component.zig");
    _ = @import("render3/partial/injectable.zig");
    _ = @import("render3/partial/ng_module.zig");
    _ = @import("render3/partial/pipe.zig");
    _ = @import("render3/partial/factory.zig");
    _ = @import("render3/partial/injector.zig");
    _ = @import("render3/partial/service.zig");
    _ = @import("compiler.zig");
    _ = @import("render3/r3_identifiers.zig");
    _ = @import("render3/view/query_generation.zig");
    _ = @import("template/pipeline/ir/reify.zig");
    _ = @import("directive_matching.zig");
    _ = @import("render3/view/t2_binder.zig");
}
