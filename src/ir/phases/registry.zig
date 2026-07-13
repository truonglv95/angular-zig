/// IR Phase Registry — Comptime-generated phase pipeline
///
/// This module defines the ordered phase pipeline for IR transformation.
/// All phase implementations live in `impl.zig` (will be gradually split
/// into per-phase files matching the original Angular structure).
///
/// DOD: The phase pipeline is a comptime array — the compiler unrolls
/// the entire `inline for` loop at build time, eliminating per-phase
/// dispatch overhead and enabling cross-phase optimization.
const std = @import("std");

const impl = @import("impl.zig");

// ─── Re-exports ──────────────────────────────────────────────
pub const Phase = impl.Phase;
pub const PhaseKind = impl.Phase.PhaseKind;
pub const PhaseTimings = impl.PhaseTimings;
pub const PipelinePhase = impl.PipelinePhase;
pub const CORE_PHASES = impl.CORE_PHASES;
pub const PIPELINE_PHASES = impl.CORE_PHASES;
pub const transform = impl.transform;
pub const transformWithTimings = impl.transformWithTimings;

// ─── Per-phase module imports (matching Angular's phases/ directory) ──
// Each file re-exports `run` as the phase entry point.
// This section mirrors the import structure of Angular's template/pipeline/src/phases/.
pub const phases = struct {
    // ── Create phases ──
    pub const ng_container = @import("ng_container.zig");
    pub const ordering = @import("ordering.zig");
    pub const defer_configs = @import("defer_configs.zig");
    pub const namespace = @import("namespace.zig");
    pub const generate_advance = @import("generate_advance.zig");
    pub const empty_elements = @import("empty_elements.zig");
    pub const attribute_extraction = @import("attribute_extraction.zig");

    // ── Both phases ──
    pub const attach_source_locations = @import("attach_source_locations.zig");
    pub const resolve_sanitizers = @import("resolve_sanitizers.zig");

    // ── Update phases ──
    pub const remove_empty_bindings = @import("remove_empty_bindings.zig");
    pub const collapse_singleton_interpolations = @import("collapse_singleton_interpolations.zig");
    pub const resolve_contexts = @import("resolve_contexts.zig");
    pub const transform_two_way_binding_set = @import("transform_two_way_binding_set.zig");
    pub const pipe_creation = @import("pipe_creation.zig");
    pub const local_refs = @import("local_refs.zig");
    pub const expand_safe_reads = @import("expand_safe_reads.zig");
    pub const temporary_variables = @import("temporary_variables.zig");
    pub const variable_optimization = @import("variable_optimization.zig");
    pub const store_let_optimization = @import("store_let_optimization.zig");
    pub const binding_specialization = @import("binding_specialization.zig");
    pub const next_context_merging = @import("next_context_merging.zig");
    pub const pure_function_extraction = @import("pure_function_extraction.zig");
    pub const style_binding_specialization = @import("style_binding_specialization.zig");
    pub const pure_literal_structures = @import("pure_literal_structures.zig");
    pub const has_const_expression_collection = @import("has_const_expression_collection.zig");
    pub const host_style_property_parsing = @import("host_style_property_parsing.zig");
    pub const track_fn_optimization = @import("track_fn_optimization.zig");
    pub const conditionals = @import("conditionals.zig");
    pub const const_collection = @import("const_collection.zig");
    pub const generate_projection_def = @import("generate_projection_def.zig");

    // ── Post phases ──
    pub const slot_allocation = @import("slot_allocation.zig");
    pub const var_counting = @import("var_counting.zig");

    // ── Phase 3: New phases ported from Angular ──
    pub const any_cast = @import("any_cast.zig");
    pub const resolve_dollar_event = @import("resolve_dollar_event.zig");
    pub const track_variables = @import("track_variables.zig");
    pub const save_restore_view = @import("save_restore_view.zig");
    pub const strip_nonrequired_parentheses = @import("strip_nonrequired_parentheses.zig");
};

// ─── Phase Categories ────────────────────────────────────────
/// Create-phase ops: DOM tree building (Element, Text, Listener, etc.)
/// Run before update phases.
pub const CREATE_PHASES = blk: {
    var count: usize = 0;
    for (CORE_PHASES) |p| {
        if (p.kind == .Create) count += 1;
    }
    var arr: [count]Phase = undefined;
    var idx: usize = 0;
    for (CORE_PHASES) |p| {
        if (p.kind == .Create) {
            arr[idx] = p;
            idx += 1;
        }
    }
    break :blk arr;
};

/// Update-phase ops: binding application (Property, StyleProp, etc.)
/// Run after create phases.
pub const UPDATE_PHASES = blk: {
    var count: usize = 0;
    for (CORE_PHASES) |p| {
        if (p.kind == .Update) count += 1;
    }
    var arr: [count]Phase = undefined;
    var idx: usize = 0;
    for (CORE_PHASES) |p| {
        if (p.kind == .Update) {
            arr[idx] = p;
            idx += 1;
        }
    }
    break :blk arr;
};

/// Post-phase ops: final analysis/cleanup (slot allocation, validation, etc.)
/// Run after all create + update phases.
pub const POST_PHASES = blk: {
    var count: usize = 0;
    for (CORE_PHASES) |p| {
        if (p.kind == .Post) count += 1;
    }
    var arr: [count]Phase = undefined;
    var idx: usize = 0;
    for (CORE_PHASES) |p| {
        if (p.kind == .Post) {
            arr[idx] = p;
            idx += 1;
        }
    }
    break :blk arr;
};

/// Both-phase ops: touch both create and update lists.
pub const BOTH_PHASES = blk: {
    var count: usize = 0;
    for (CORE_PHASES) |p| {
        if (p.kind == .Both) count += 1;
    }
    var arr: [count]Phase = undefined;
    var idx: usize = 0;
    for (CORE_PHASES) |p| {
        if (p.kind == .Both) {
            arr[idx] = p;
            idx += 1;
        }
    }
    break :blk arr;
};

// ─── Comptime Phase Count ────────────────────────────────────
pub const TOTAL_PHASES = CORE_PHASES.len;
pub const CREATE_PHASE_COUNT = CREATE_PHASES.len;
pub const UPDATE_PHASE_COUNT = UPDATE_PHASES.len;
pub const POST_PHASE_COUNT = POST_PHASES.len;
pub const BOTH_PHASE_COUNT = BOTH_PHASES.len;

// ─── Original Angular Phase Mapping ──────────────────────────
/// Maps the 50 Zig phases to the 72 original Angular phases.
/// Phases marked "MISSING" need to be ported in Phase 3.
/// This serves as a tracking table for port progress.
pub const AngularPhaseMapping = struct {
    zig_phase: []const u8,
    angular_phase: []const u8,
    status: PhaseStatus,
};

pub const PhaseStatus = enum {
    ported,     // Phase exists in Zig and matches Angular
    partial,    // Phase exists but is incomplete
    missing,    // Phase does not exist in Zig yet
    extra,      // Phase exists in Zig but not in Angular (Zig-specific)
};

/// Phase mapping table (will be updated as phases are ported).
pub const PHASE_MAPPING = [_]AngularPhaseMapping{
    // ── Create phases ──
    .{ .zig_phase = "orderCreationOps", .angular_phase = "ordering.ts", .status = .ported },
    .{ .zig_phase = "processDeferredBlocks", .angular_phase = "defer_configs.ts", .status = .partial },
    .{ .zig_phase = "emitNamespaceChanges", .angular_phase = "namespace.ts", .status = .ported },
    .{ .zig_phase = "generateAdvanceOps", .angular_phase = "generate_advance.ts", .status = .ported },
    .{ .zig_phase = "coalesceTextOps", .angular_phase = "empty_elements.ts", .status = .partial },
    .{ .zig_phase = "deduplicateAttributes", .angular_phase = "attribute_extraction.ts", .status = .ported },
    .{ .zig_phase = "validateNesting", .angular_phase = "(zig-specific)", .status = .extra },
    .{ .zig_phase = "mergeAdjacentText", .angular_phase = "deduplicate_text_bindings.ts", .status = .ported },
    .{ .zig_phase = "removeEmptyIcuBlocks", .angular_phase = "remove_unused_i18n_attrs.ts", .status = .partial },

    // ── Both phases ──
    .{ .zig_phase = "attachSourceLocations", .angular_phase = "attach_source_locations.ts", .status = .ported },
    .{ .zig_phase = "injectSecurityContexts", .angular_phase = "resolve_sanitizers.ts", .status = .ported },

    // ── Update phases ──
    .{ .zig_phase = "orderUpdateOps", .angular_phase = "ordering.ts", .status = .ported },
    .{ .zig_phase = "removeEmptyBindings", .angular_phase = "remove_empty_bindings.ts", .status = .ported },
    .{ .zig_phase = "collapseSingletonInterpolations", .angular_phase = "collapse_singleton_interpolations.ts", .status = .ported },
    .{ .zig_phase = "resolveContexts", .angular_phase = "resolve_contexts.ts", .status = .ported },
    .{ .zig_phase = "expandTwoWayBindings", .angular_phase = "transform_two_way_binding_set.ts", .status = .ported },
    .{ .zig_phase = "createPipes", .angular_phase = "pipe_creation.ts", .status = .ported },
    .{ .zig_phase = "liftLocalRefs", .angular_phase = "local_refs.ts", .status = .ported },
    .{ .zig_phase = "expandSafeReads", .angular_phase = "expand_safe_reads.ts", .status = .ported },
    .{ .zig_phase = "generateTemporaryVariables", .angular_phase = "temporary_variables.ts", .status = .partial },
    .{ .zig_phase = "optimizeVariables", .angular_phase = "variable_optimization.ts", .status = .partial },
    .{ .zig_phase = "hoistStoreLets", .angular_phase = "store_let_optimization.ts", .status = .ported },
    .{ .zig_phase = "normalizeBindingOrder", .angular_phase = "binding_specialization.ts", .status = .partial },
    .{ .zig_phase = "removeDuplicateAdvanceOps", .angular_phase = "next_context_merging.ts", .status = .partial },
    .{ .zig_phase = "allocateInterpolationSlots", .angular_phase = "(zig-specific)", .status = .extra },
    .{ .zig_phase = "generatePureFunctions", .angular_phase = "pure_function_extraction.ts", .status = .partial },
    .{ .zig_phase = "normalizeStyleMapExpressions", .angular_phase = "style_binding_specialization.ts", .status = .partial },
    .{ .zig_phase = "normalizeClassMapExpressions", .angular_phase = "style_binding_specialization.ts", .status = .partial },
    .{ .zig_phase = "constantFoldExpressions", .angular_phase = "pure_literal_structures.ts", .status = .partial },
    .{ .zig_phase = "resolvePureFunctionRefs", .angular_phase = "has_const_expression_collection.ts", .status = .partial },
    .{ .zig_phase = "deduplicatePipes", .angular_phase = "pipe_creation.ts", .status = .ported },
    .{ .zig_phase = "inlineSimpleVariables", .angular_phase = "variable_optimization.ts", .status = .partial },
    .{ .zig_phase = "convertAttributeToProperty", .angular_phase = "binding_specialization.ts", .status = .partial },
    .{ .zig_phase = "extractHostBindings", .angular_phase = "host_style_property_parsing.ts", .status = .partial },
    .{ .zig_phase = "generateRepeaterTrackBy", .angular_phase = "track_fn_optimization.ts", .status = .ported },
    .{ .zig_phase = "wrapConditionalBranches", .angular_phase = "conditionals.ts", .status = .ported },
    .{ .zig_phase = "removeUnusedStoreLets", .angular_phase = "store_let_optimization.ts", .status = .ported },
    .{ .zig_phase = "normalizeTwoWayBindingPairs", .angular_phase = "transform_two_way_binding_set.ts", .status = .ported },
    .{ .zig_phase = "hoistConstantExpressions", .angular_phase = "const_collection.ts", .status = .partial },
    .{ .zig_phase = "reorderProjectionBindings", .angular_phase = "generate_projection_def.ts", .status = .partial },

    // ── Post phases ──
    .{ .zig_phase = "allocateSlots", .angular_phase = "slot_allocation.ts", .status = .ported },
    .{ .zig_phase = "countVariables", .angular_phase = "var_counting.ts", .status = .ported },
    .{ .zig_phase = "validateXrefs", .angular_phase = "(zig-specific)", .status = .extra },
    .{ .zig_phase = "removeNoopOps", .angular_phase = "nonbindable.ts", .status = .partial },
    .{ .zig_phase = "compactXrefs", .angular_phase = "(zig-specific)", .status = .extra },
    .{ .zig_phase = "finalValidation", .angular_phase = "(zig-specific)", .status = .extra },
    .{ .zig_phase = "generateViewId", .angular_phase = "(zig-specific)", .status = .extra },
    .{ .zig_phase = "validateOpConsistency", .angular_phase = "(zig-specific)", .status = .extra },
    .{ .zig_phase = "optimizeTemplateSize", .angular_phase = "(zig-specific)", .status = .extra },
    .{ .zig_phase = "generateDirectiveMetadata", .angular_phase = "(zig-specific)", .status = .extra },

    // ── MISSING Angular phases (need to be ported) ──
    .{ .zig_phase = "(missing)", .angular_phase = "any_cast.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "apply_i18n_expressions.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "assign_i18n_slot_dependencies.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "chaining.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "control_directives.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "convert_animations.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "convert_i18n_bindings.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "create_i18n_contexts.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "defer_resolve_targets.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "extract_i18n_messages.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "generate_arrow_functions.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "generate_local_let_references.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "generate_variables.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "i18n_const_collection.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "i18n_text_extraction.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "insert_incremental_hydration_runtime.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "naming.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "ng_container.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "parse_extracted_styles.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "phase_remove_content_selectors.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "pipe_variadic.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "propagate_i18n_blocks.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "regular_expression_optimization.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "remove_i18n_contexts.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "remove_illegal_let_references.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "resolve_defer_deps_fns.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "resolve_dollar_event.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "resolve_foreign_content.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "resolve_i18n_attr_sanitizers.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "resolve_i18n_element_placeholders.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "resolve_i18n_expression_placeholders.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "resolve_names.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "safe_navigation_migration.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "save_restore_view.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "strip_nonrequired_parentheses.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "track_variables.ts", .status = .missing },
    .{ .zig_phase = "(missing)", .angular_phase = "wrap_icus.ts", .status = .missing },
};

/// Count phases by status.
pub fn countByStatus(status: PhaseStatus) usize {
    var count: usize = 0;
    for (PHASE_MAPPING) |m| {
        if (m.status == status) count += 1;
    }
    return count;
}
