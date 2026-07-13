/// IR Transformation Phases — 50 real transformation phases
///
/// Each phase transforms the IR in-place for optimization/correctness.
/// DOD: Phases operate on contiguous OpList arrays — single-pass O(n)
/// where possible, no heap allocations in hot paths, stack variables,
/// contiguous array iteration, comptime decisions where possible.
///
/// Phase categories:
///   Create  — transform creation-phase ops (DOM tree building)
///   Update  — transform update-phase ops (binding application)
///   Both    — touch both create and update lists
///   Post    — final analysis / cleanup after all transformations
const std = @import("std");

const job_mod = @import("../job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../ops.zig");
const IrOp = ir_ops.IrOp;
pub const OpKind = ir_ops.OpKind;
const hasTrait = ir_ops.hasTrait;
const OpTrait = ir_ops.OpTrait;
pub const Namespace = ir_ops.Namespace;

const ir_enums = @import("../enums.zig");
const CompilationKind = ir_enums.CompilationKind;
const BindingKind = ir_enums.BindingKind;
const isCreationOp = ir_enums.isCreationOp;

const ir_expr = @import("../expression.zig");
const IrExpr = ir_expr.IrExpr;
const ExpressionKind = ir_enums.ExpressionKind;

const source_span = @import("../../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

const schema = @import("../../schema/registry.zig");
const SecurityContext = schema.SecurityContext;

const html_tags = @import("../../html/tags.zig");

// ─── Per-phase modules (Phase 3: splitting into per-phase files) ──
const ng_container = @import("ng_container.zig");
const resolve_dollar_event = @import("resolve_dollar_event.zig");
const any_cast = @import("any_cast.zig");
const track_variables = @import("track_variables.zig");
const save_restore_view = @import("save_restore_view.zig");
const strip_nonrequired_parens = @import("strip_nonrequired_parentheses.zig");
// i18n phases
const i18n_context = @import("i18n_context.zig");
const create_i18n_contexts = @import("create_i18n_contexts.zig");
const convert_i18n_bindings = @import("convert_i18n_bindings.zig");
const i18n_text_extraction = @import("i18n_text_extraction.zig");
const propagate_i18n_blocks = @import("propagate_i18n_blocks.zig");
const extract_i18n_messages = @import("extract_i18n_messages.zig");
const i18n_const_collection = @import("i18n_const_collection.zig");
const resolve_i18n_element_placeholders = @import("resolve_i18n_element_placeholders.zig");
const resolve_i18n_expression_placeholders = @import("resolve_i18n_expression_placeholders.zig");
const resolve_i18n_attr_sanitizers = @import("resolve_i18n_attr_sanitizers.zig");
const apply_i18n_expressions = @import("apply_i18n_expressions.zig");
const assign_i18n_slot_dependencies = @import("assign_i18n_slot_dependencies.zig");
const remove_i18n_contexts = @import("remove_i18n_contexts.zig");
// Non-i18n phases
const naming = @import("naming.zig");
const resolve_names = @import("resolve_names.zig");
const chaining = @import("chaining.zig");
const control_directives = @import("control_directives.zig");
const convert_animations = @import("convert_animations.zig");
const defer_resolve_targets = @import("defer_resolve_targets.zig");
const resolve_defer_deps_fns = @import("resolve_defer_deps_fns.zig");
const generate_arrow_functions = @import("generate_arrow_functions.zig");
const generate_local_let_references = @import("generate_local_let_references.zig");
const generate_variables = @import("generate_variables.zig");
const insert_incremental_hydration_runtime = @import("insert_incremental_hydration_runtime.zig");
const parse_extracted_styles = @import("parse_extracted_styles.zig");
const phase_remove_content_selectors = @import("phase_remove_content_selectors.zig");
const regular_expression_optimization = @import("regular_expression_optimization.zig");
const safe_navigation_migration = @import("safe_navigation_migration.zig");
const resolve_foreign_content = @import("resolve_foreign_content.zig");
const wrap_icus = @import("wrap_icus.zig");
const remove_illegal_let_references = @import("remove_illegal_let_references.zig");
const pipe_variadic = @import("pipe_variadic.zig");

// ─── Per-phase imports (Phase 3: code migrated to per-phase files) ──
const attach_source_locations_mod = @import("attach_source_locations.zig");
const attribute_extraction_mod = @import("attribute_extraction.zig");
const binding_specialization_mod = @import("binding_specialization.zig");
const collapse_singleton_interpolations_mod = @import("collapse_singleton_interpolations.zig");
const conditionals_mod = @import("conditionals.zig");
const const_collection_mod = @import("const_collection.zig");
const defer_configs_mod = @import("defer_configs.zig");
const empty_elements_mod = @import("empty_elements.zig");
const expand_safe_reads_mod = @import("expand_safe_reads.zig");
const generate_advance_mod = @import("generate_advance.zig");
const generate_projection_def_mod = @import("generate_projection_def.zig");
const has_const_expression_collection_mod = @import("has_const_expression_collection.zig");
const host_style_property_parsing_mod = @import("host_style_property_parsing.zig");
const local_refs_mod = @import("local_refs.zig");
const namespace_mod = @import("namespace.zig");
const next_context_merging_mod = @import("next_context_merging.zig");
const ordering_mod = @import("ordering.zig");
const pipe_creation_mod = @import("pipe_creation.zig");
const pure_function_extraction_mod = @import("pure_function_extraction.zig");
const pure_literal_structures_mod = @import("pure_literal_structures.zig");
const remove_empty_bindings_mod = @import("remove_empty_bindings.zig");
const resolve_contexts_mod = @import("resolve_contexts.zig");
const resolve_sanitizers_mod = @import("resolve_sanitizers.zig");
const slot_allocation_mod = @import("slot_allocation.zig");
const store_let_optimization_mod = @import("store_let_optimization.zig");
const style_binding_specialization_mod = @import("style_binding_specialization.zig");
const temporary_variables_mod = @import("temporary_variables.zig");
const track_fn_optimization_mod = @import("track_fn_optimization.zig");
const transform_two_way_binding_set_mod = @import("transform_two_way_binding_set.zig");
const var_counting_mod = @import("var_counting.zig");
const variable_optimization_mod = @import("variable_optimization.zig");
const reify_mod = @import("reify.zig");
const deduplicate_text_bindings_mod = @import("deduplicate_text_bindings.zig");
const remove_unused_i18n_attrs_mod = @import("remove_unused_i18n_attrs.zig");
const nonbindable_mod = @import("nonbindable.zig");

const orderCreationOps = ordering_mod.run;
const processDeferredBlocks = defer_configs_mod.run;
const emitNamespaceChanges = namespace_mod.run;
const generateAdvanceOps = generate_advance_mod.run;
const coalesceTextOps = empty_elements_mod.run;
const deduplicateAttributes = attribute_extraction_mod.run;
const validateNesting = ordering_mod.validateNesting;
const mergeAdjacentText = deduplicate_text_bindings_mod.mergeAdjacentText;
const removeEmptyIcuBlocks = remove_unused_i18n_attrs_mod.removeEmptyIcuBlocks;
const attachSourceLocations = attach_source_locations_mod.run;
const injectSecurityContexts = resolve_sanitizers_mod.run;
const markSecurityContexts = resolve_sanitizers_mod.markSecurityContexts;
const declareNamespaces = namespace_mod.declareNamespaces;
const orderUpdateOps = ordering_mod.orderUpdateOps;
const removeEmptyBindings = remove_empty_bindings_mod.run;
const collapseSingletonInterpolations = collapse_singleton_interpolations_mod.run;
const resolveContexts = resolve_contexts_mod.run;
const expandTwoWayBindings = transform_two_way_binding_set_mod.run;
const createPipes = pipe_creation_mod.run;
const liftLocalRefs = local_refs_mod.run;
const expandSafeReads = expand_safe_reads_mod.run;
const generateTemporaryVariables = temporary_variables_mod.run;
const optimizeVariables = variable_optimization_mod.run;
const hoistStoreLets = store_let_optimization_mod.run;
const normalizeBindingOrder = binding_specialization_mod.run;
const removeDuplicateAdvanceOps = next_context_merging_mod.run;
const allocateInterpolationSlots = slot_allocation_mod.allocateInterpolationSlots;
const generatePureFunctions = pure_function_extraction_mod.run;
const normalizeStyleMapExpressions = style_binding_specialization_mod.run;
const normalizeClassMapExpressions = style_binding_specialization_mod.normalizeClassMapExpressions;
const constantFoldExpressions = pure_literal_structures_mod.run;
const foldBinaryExpr = pure_literal_structures_mod.foldBinaryExpr;
const resolvePureFunctionRefs = has_const_expression_collection_mod.run;
const resolvePureRefs = has_const_expression_collection_mod.resolvePureRefs;
const deduplicatePipes = pipe_creation_mod.deduplicatePipes;
const inlineSimpleVariables = variable_optimization_mod.inlineSimpleVariables;
const convertAttributeToProperty = binding_specialization_mod.convertAttributeToProperty;
const extractHostBindings = host_style_property_parsing_mod.run;
const generateRepeaterTrackBy = track_fn_optimization_mod.run;
const wrapConditionalBranches = conditionals_mod.run;
const removeUnusedStoreLets = store_let_optimization_mod.removeUnusedStoreLets;
const normalizeTwoWayBindingPairs = transform_two_way_binding_set_mod.normalizeTwoWayBindingPairs;
const hoistConstantExpressions = const_collection_mod.run;
const reorderProjectionBindings = generate_projection_def_mod.run;
const allocateSlots = slot_allocation_mod.run;
const countVariables = var_counting_mod.run;
const validateXrefs = var_counting_mod.validateXrefs;
const removeNoopOps = nonbindable_mod.removeNoopOps;
const compactXrefs = var_counting_mod.compactXrefs;
const finalValidation = reify_mod.finalValidation;
const generateViewId = reify_mod.generateViewId;
const validateOpConsistency = reify_mod.validateOpConsistency;
const optimizeTemplateSize = reify_mod.optimizeTemplateSize;
const generateDirectiveMetadata = reify_mod.generateDirectiveMetadata;

// ─── Helpers ──────────────────────────────────────────────────

/// Max nesting depth for stack-allocated tracking arrays.
const MAX_DEPTH: usize = 128;

/// Whether a property name is security-sensitive (needs security_context).
fn isDangerousProperty(name: []const u8) bool {
    const dangerous = [_][]const u8{
        "innerHTML",
        "outerHTML",
        "formaction",
        "action",
        "data",
        "srcdoc",
    };
    for (dangerous) |d| {
        if (std.mem.eql(u8, name, d)) return true;
    }
    // href/src with javascript: prefix is checked separately
    return false;
}

/// Whether a URL-like property value starts with "javascript:".
fn isJavascriptUrl(value: []const u8) bool {
    return value.len >= 11 and std.mem.eql(u8, value[0..11], "javascript:");
}

/// Get the mutable expression pointer from an op, if it has one.
/// Returns null for ops without expressions.
fn getExpressionPtr(op: *IrOp) ?*IrExpr {
    return switch (op.data) {
        .Binding => |*b| b.expression,
        .Property => |*p| p.expression,
        .DomProperty => |*d| d.expression,
        .StyleProp => |*s| s.expression,
        .ClassProp => |*c| c.expression,
        .StyleMap => |*s| s.expression,
        .ClassMap => |*c| c.expression,
        .TwoWayProperty => |*t| t.expression,
        .InterpolateText => null, // has expressions[] but not a single expr
        .Conditional => |*c| c.condition_expr,
        .Repeater => |*r| r.track_by_fn orelse return null,
        .StoreLet => |*s| s.expression,
        .Variable => |*v| v.value,
        .Animation => |*a| a.expr,
        .AnimationBinding => |*a| a.expression,
        .AnimationString => |*a| a.expression,
        else => null,
    };
}

/// Get the property/binding name from an op, if it has one.
fn getOpName(op: IrOp) ?[]const u8 {
    return switch (op.data) {
        .Binding => |b| b.name,
        .Property => |p| p.name,
        .DomProperty => |d| d.name,
        .StyleProp => |s| s.name,
        .ClassProp => |c| c.name,
        .TwoWayProperty => |t| t.name,
        .TwoWayListener => |t| t.name,
        .Listener => |l| l.name,
        .ElementStart => |e| e.name,
        .Statement => |s| s,
        else => null,
    };
}

/// Get the name of a Variable or StoreLet op.
fn getVariableName(op: IrOp) ?[]const u8 {
    return switch (op.data) {
        .StoreLet => |s| s.name,
        .Variable => |v| v.name,
        else => null,
    };
}

/// Binding priority for canonical ordering (lower = earlier).
fn bindingPriority(kind: OpKind) u8 {
    return switch (kind) {
        .TwoWayProperty, .TwoWayListener => 0,
        .Property, .DomProperty => 1,
        .Binding => 2,
        .ClassProp, .ClassMap => 3,
        .StyleProp, .StyleMap => 4,
        .InterpolateText => 5,
        .Pipe => 6,
        .AnimationBinding, .AnimationString => 7,
        .Advance => 8,
        .StoreLet, .Variable => 9,
        .Conditional => 10,
        .Repeater => 11,
        .I18nExpression => 12,
        else => 255,
    };
}

/// Create a zero-span IR op (used as fallback for inserted ops).
fn zeroOp(kind: OpKind, xref: u32, data: ir_ops.OpData) IrOp {
    return .{
        .kind = kind,
        .xref = xref,
        .source_span = .empty(),
        .data = data,
    };
}

// ─── Phase Registry ──────────────────────────────────────────

pub const Phase = struct {
    name: []const u8,
    fn_ptr: *const fn (job: *ComponentCompilationJob, view: *ViewCompilationUnit) anyerror!void,
    kind: PhaseKind,

    pub const PhaseKind = enum { Create, Update, Both, Post };
};

/// All core phases in dependency order.
/// Create phases first → Both → Update → Post.
/// Phase 3: Added 6 new phases from Angular original (ng_container, etc.)
pub const CORE_PHASES: []const Phase = &.{
    // ── Create Phase (10) ─────────────────────────────────────
    .{ .name = "ngContainer", .fn_ptr = ng_container.run, .kind = .Create },
    .{ .name = "orderCreationOps", .fn_ptr = orderCreationOps, .kind = .Create },
    .{ .name = "processDeferredBlocks", .fn_ptr = processDeferredBlocks, .kind = .Create },
    .{ .name = "emitNamespaceChanges", .fn_ptr = emitNamespaceChanges, .kind = .Create },
    .{ .name = "generateAdvanceOps", .fn_ptr = generateAdvanceOps, .kind = .Create },
    .{ .name = "coalesceTextOps", .fn_ptr = coalesceTextOps, .kind = .Create },
    .{ .name = "deduplicateAttributes", .fn_ptr = deduplicateAttributes, .kind = .Create },
    .{ .name = "validateNesting", .fn_ptr = validateNesting, .kind = .Create },
    .{ .name = "mergeAdjacentText", .fn_ptr = mergeAdjacentText, .kind = .Create },
    .{ .name = "removeEmptyIcuBlocks", .fn_ptr = removeEmptyIcuBlocks, .kind = .Create },

    // ── Both Phase (2) ─────────────────────────────────────────
    .{ .name = "attachSourceLocations", .fn_ptr = attachSourceLocations, .kind = .Both },
    .{ .name = "injectSecurityContexts", .fn_ptr = injectSecurityContexts, .kind = .Both },

    // ── Update Phase (29) ──────────────────────────────────────
    .{ .name = "orderUpdateOps", .fn_ptr = orderUpdateOps, .kind = .Update },
    .{ .name = "removeEmptyBindings", .fn_ptr = removeEmptyBindings, .kind = .Update },
    .{ .name = "collapseSingletonInterpolations", .fn_ptr = collapseSingletonInterpolations, .kind = .Update },
    .{ .name = "resolveContexts", .fn_ptr = resolveContexts, .kind = .Update },
    .{ .name = "expandTwoWayBindings", .fn_ptr = expandTwoWayBindings, .kind = .Update },
    .{ .name = "createPipes", .fn_ptr = createPipes, .kind = .Update },
    .{ .name = "liftLocalRefs", .fn_ptr = liftLocalRefs, .kind = .Update },
    .{ .name = "expandSafeReads", .fn_ptr = expandSafeReads, .kind = .Update },
    .{ .name = "generateTemporaryVariables", .fn_ptr = generateTemporaryVariables, .kind = .Update },
    .{ .name = "optimizeVariables", .fn_ptr = optimizeVariables, .kind = .Update },
    .{ .name = "hoistStoreLets", .fn_ptr = hoistStoreLets, .kind = .Update },
    .{ .name = "normalizeBindingOrder", .fn_ptr = normalizeBindingOrder, .kind = .Update },
    .{ .name = "removeDuplicateAdvanceOps", .fn_ptr = removeDuplicateAdvanceOps, .kind = .Update },
    .{ .name = "allocateInterpolationSlots", .fn_ptr = allocateInterpolationSlots, .kind = .Update },
    .{ .name = "generatePureFunctions", .fn_ptr = generatePureFunctions, .kind = .Update },
    .{ .name = "normalizeStyleMapExpressions", .fn_ptr = normalizeStyleMapExpressions, .kind = .Update },
    .{ .name = "normalizeClassMapExpressions", .fn_ptr = normalizeClassMapExpressions, .kind = .Update },
    .{ .name = "constantFoldExpressions", .fn_ptr = constantFoldExpressions, .kind = .Update },
    .{ .name = "resolvePureFunctionRefs", .fn_ptr = resolvePureFunctionRefs, .kind = .Update },
    .{ .name = "deduplicatePipes", .fn_ptr = deduplicatePipes, .kind = .Update },
    .{ .name = "inlineSimpleVariables", .fn_ptr = inlineSimpleVariables, .kind = .Update },
    .{ .name = "convertAttributeToProperty", .fn_ptr = convertAttributeToProperty, .kind = .Update },
    .{ .name = "extractHostBindings", .fn_ptr = extractHostBindings, .kind = .Update },
    .{ .name = "generateRepeaterTrackBy", .fn_ptr = generateRepeaterTrackBy, .kind = .Update },
    .{ .name = "wrapConditionalBranches", .fn_ptr = wrapConditionalBranches, .kind = .Update },
    .{ .name = "removeUnusedStoreLets", .fn_ptr = removeUnusedStoreLets, .kind = .Update },
    .{ .name = "normalizeTwoWayBindingPairs", .fn_ptr = normalizeTwoWayBindingPairs, .kind = .Update },
    .{ .name = "hoistConstantExpressions", .fn_ptr = hoistConstantExpressions, .kind = .Update },
    .{ .name = "reorderProjectionBindings", .fn_ptr = reorderProjectionBindings, .kind = .Update },
    // Phase 3: New update phases from Angular original
    .{ .name = "resolveDollarEvent", .fn_ptr = resolve_dollar_event.run, .kind = .Update },
    .{ .name = "deleteAnyCasts", .fn_ptr = any_cast.run, .kind = .Update },
    .{ .name = "trackVariables", .fn_ptr = track_variables.run, .kind = .Update },
    .{ .name = "saveRestoreView", .fn_ptr = save_restore_view.run, .kind = .Update },
    .{ .name = "stripNonrequiredParens", .fn_ptr = strip_nonrequired_parens.run, .kind = .Update },
    // Phase 3: i18n phases
    .{ .name = "createI18nContexts", .fn_ptr = create_i18n_contexts.run, .kind = .Update },
    .{ .name = "convertI18nBindings", .fn_ptr = convert_i18n_bindings.run, .kind = .Update },
    .{ .name = "i18nTextExtraction", .fn_ptr = i18n_text_extraction.run, .kind = .Update },
    .{ .name = "propagateI18nBlocks", .fn_ptr = propagate_i18n_blocks.run, .kind = .Update },
    .{ .name = "extractI18nMessages", .fn_ptr = extract_i18n_messages.run, .kind = .Update },
    .{ .name = "i18nConstCollection", .fn_ptr = i18n_const_collection.run, .kind = .Update },
    .{ .name = "resolveI18nElementPlaceholders", .fn_ptr = resolve_i18n_element_placeholders.run, .kind = .Update },
    .{ .name = "resolveI18nExpressionPlaceholders", .fn_ptr = resolve_i18n_expression_placeholders.run, .kind = .Update },
    .{ .name = "resolveI18nAttrSanitizers", .fn_ptr = resolve_i18n_attr_sanitizers.run, .kind = .Update },
    .{ .name = "applyI18nExpressions", .fn_ptr = apply_i18n_expressions.run, .kind = .Update },
    .{ .name = "assignI18nSlotDependencies", .fn_ptr = assign_i18n_slot_dependencies.run, .kind = .Update },
    .{ .name = "removeI18nContexts", .fn_ptr = remove_i18n_contexts.run, .kind = .Update },
    // Phase 3: Non-i18n phases
    .{ .name = "naming", .fn_ptr = naming.run, .kind = .Update },
    .{ .name = "resolveNames", .fn_ptr = resolve_names.run, .kind = .Update },
    .{ .name = "chaining", .fn_ptr = chaining.run, .kind = .Update },
    .{ .name = "controlDirectives", .fn_ptr = control_directives.run, .kind = .Update },
    .{ .name = "convertAnimations", .fn_ptr = convert_animations.run, .kind = .Update },
    .{ .name = "deferResolveTargets", .fn_ptr = defer_resolve_targets.run, .kind = .Update },
    .{ .name = "resolveDeferDepsFns", .fn_ptr = resolve_defer_deps_fns.run, .kind = .Update },
    .{ .name = "generateArrowFunctions", .fn_ptr = generate_arrow_functions.run, .kind = .Update },
    .{ .name = "generateLocalLetReferences", .fn_ptr = generate_local_let_references.run, .kind = .Update },
    .{ .name = "generateVariables", .fn_ptr = generate_variables.run, .kind = .Update },
    .{ .name = "insertIncrementalHydrationRuntime", .fn_ptr = insert_incremental_hydration_runtime.run, .kind = .Update },
    .{ .name = "parseExtractedStyles", .fn_ptr = parse_extracted_styles.run, .kind = .Update },
    .{ .name = "phaseRemoveContentSelectors", .fn_ptr = phase_remove_content_selectors.run, .kind = .Update },
    .{ .name = "regexOptimization", .fn_ptr = regular_expression_optimization.run, .kind = .Update },
    .{ .name = "safeNavigationMigration", .fn_ptr = safe_navigation_migration.run, .kind = .Update },
    .{ .name = "resolveForeignContent", .fn_ptr = resolve_foreign_content.run, .kind = .Update },
    .{ .name = "wrapIcus", .fn_ptr = wrap_icus.run, .kind = .Update },
    .{ .name = "removeIllegalLetReferences", .fn_ptr = remove_illegal_let_references.run, .kind = .Update },
    .{ .name = "pipeVariadic", .fn_ptr = pipe_variadic.run, .kind = .Update },

    // ── Post Phase (10) ───────────────────────────────────────
    .{ .name = "allocateSlots", .fn_ptr = allocateSlots, .kind = .Post },
    .{ .name = "countVariables", .fn_ptr = countVariables, .kind = .Post },
    .{ .name = "validateXrefs", .fn_ptr = validateXrefs, .kind = .Post },
    .{ .name = "removeNoopOps", .fn_ptr = removeNoopOps, .kind = .Post },
    .{ .name = "compactXrefs", .fn_ptr = compactXrefs, .kind = .Post },
    .{ .name = "finalValidation", .fn_ptr = finalValidation, .kind = .Post },
    .{ .name = "generateViewId", .fn_ptr = generateViewId, .kind = .Post },
    .{ .name = "validateOpConsistency", .fn_ptr = validateOpConsistency, .kind = .Post },
    .{ .name = "optimizeTemplateSize", .fn_ptr = optimizeTemplateSize, .kind = .Post },
    .{ .name = "generateDirectiveMetadata", .fn_ptr = generateDirectiveMetadata, .kind = .Post },
};

// ─── Explicit Pipeline with Timing ──────────────────────────

/// Explicit pipeline phase with per-phase timing.
pub const PipelinePhase = struct {
    name: []const u8,
    fn_ptr: *const fn (job: *ComponentCompilationJob, view: *ViewCompilationUnit) anyerror!void,
    elapsed_ns: u64 = 0,
};

/// All pipeline phases in the required execution order.
/// This is the authoritative phase sequence — CORE_PHASES is derived from this.
pub const PIPELINE_PHASES: []const PipelinePhase = &.{
    // ── Security & Namespace (pre-pass) ──────────────────────
    .{ .name = "injectSecurityContexts", .fn_ptr = injectSecurityContexts },
    .{ .name = "declareNamespaces", .fn_ptr = declareNamespaces },

    // ── Core phases (from CORE_PHASES, minus injectSecurityContexts) ──
    .{ .name = "ngContainer", .fn_ptr = ng_container.run },
    .{ .name = "orderCreationOps", .fn_ptr = orderCreationOps },
    .{ .name = "processDeferredBlocks", .fn_ptr = processDeferredBlocks },
    .{ .name = "emitNamespaceChanges", .fn_ptr = emitNamespaceChanges },
    .{ .name = "generateAdvanceOps", .fn_ptr = generateAdvanceOps },
    .{ .name = "coalesceTextOps", .fn_ptr = coalesceTextOps },
    .{ .name = "deduplicateAttributes", .fn_ptr = deduplicateAttributes },
    .{ .name = "validateNesting", .fn_ptr = validateNesting },
    .{ .name = "mergeAdjacentText", .fn_ptr = mergeAdjacentText },
    .{ .name = "removeEmptyIcuBlocks", .fn_ptr = removeEmptyIcuBlocks },
    .{ .name = "attachSourceLocations", .fn_ptr = attachSourceLocations },
    .{ .name = "orderUpdateOps", .fn_ptr = orderUpdateOps },
    .{ .name = "removeEmptyBindings", .fn_ptr = removeEmptyBindings },
    .{ .name = "collapseSingletonInterpolations", .fn_ptr = collapseSingletonInterpolations },
    .{ .name = "resolveContexts", .fn_ptr = resolveContexts },
    .{ .name = "expandTwoWayBindings", .fn_ptr = expandTwoWayBindings },
    .{ .name = "createPipes", .fn_ptr = createPipes },
    .{ .name = "liftLocalRefs", .fn_ptr = liftLocalRefs },
    .{ .name = "expandSafeReads", .fn_ptr = expandSafeReads },
    .{ .name = "generateTemporaryVariables", .fn_ptr = generateTemporaryVariables },
    .{ .name = "optimizeVariables", .fn_ptr = optimizeVariables },
    .{ .name = "hoistStoreLets", .fn_ptr = hoistStoreLets },
    .{ .name = "normalizeBindingOrder", .fn_ptr = normalizeBindingOrder },
    .{ .name = "removeDuplicateAdvanceOps", .fn_ptr = removeDuplicateAdvanceOps },
    .{ .name = "allocateInterpolationSlots", .fn_ptr = allocateInterpolationSlots },
    .{ .name = "generatePureFunctions", .fn_ptr = generatePureFunctions },
    .{ .name = "normalizeStyleMapExpressions", .fn_ptr = normalizeStyleMapExpressions },
    .{ .name = "normalizeClassMapExpressions", .fn_ptr = normalizeClassMapExpressions },
    .{ .name = "constantFoldExpressions", .fn_ptr = constantFoldExpressions },
    .{ .name = "resolvePureFunctionRefs", .fn_ptr = resolvePureFunctionRefs },
    .{ .name = "deduplicatePipes", .fn_ptr = deduplicatePipes },
    .{ .name = "inlineSimpleVariables", .fn_ptr = inlineSimpleVariables },
    .{ .name = "convertAttributeToProperty", .fn_ptr = convertAttributeToProperty },
    .{ .name = "extractHostBindings", .fn_ptr = extractHostBindings },
    .{ .name = "generateRepeaterTrackBy", .fn_ptr = generateRepeaterTrackBy },
    .{ .name = "wrapConditionalBranches", .fn_ptr = wrapConditionalBranches },
    .{ .name = "removeUnusedStoreLets", .fn_ptr = removeUnusedStoreLets },
    .{ .name = "normalizeTwoWayBindingPairs", .fn_ptr = normalizeTwoWayBindingPairs },
    .{ .name = "hoistConstantExpressions", .fn_ptr = hoistConstantExpressions },
    .{ .name = "reorderProjectionBindings", .fn_ptr = reorderProjectionBindings },
    // Phase 3: New update phases
    .{ .name = "resolveDollarEvent", .fn_ptr = resolve_dollar_event.run },
    .{ .name = "deleteAnyCasts", .fn_ptr = any_cast.run },
    .{ .name = "trackVariables", .fn_ptr = track_variables.run },
    .{ .name = "saveRestoreView", .fn_ptr = save_restore_view.run },
    .{ .name = "stripNonrequiredParens", .fn_ptr = strip_nonrequired_parens.run },
    // Phase 3: i18n phases
    .{ .name = "createI18nContexts", .fn_ptr = create_i18n_contexts.run },
    .{ .name = "convertI18nBindings", .fn_ptr = convert_i18n_bindings.run },
    .{ .name = "i18nTextExtraction", .fn_ptr = i18n_text_extraction.run },
    .{ .name = "propagateI18nBlocks", .fn_ptr = propagate_i18n_blocks.run },
    .{ .name = "extractI18nMessages", .fn_ptr = extract_i18n_messages.run },
    .{ .name = "i18nConstCollection", .fn_ptr = i18n_const_collection.run },
    .{ .name = "resolveI18nElementPlaceholders", .fn_ptr = resolve_i18n_element_placeholders.run },
    .{ .name = "resolveI18nExpressionPlaceholders", .fn_ptr = resolve_i18n_expression_placeholders.run },
    .{ .name = "resolveI18nAttrSanitizers", .fn_ptr = resolve_i18n_attr_sanitizers.run },
    .{ .name = "applyI18nExpressions", .fn_ptr = apply_i18n_expressions.run },
    .{ .name = "assignI18nSlotDependencies", .fn_ptr = assign_i18n_slot_dependencies.run },
    .{ .name = "removeI18nContexts", .fn_ptr = remove_i18n_contexts.run },
    // Phase 3: Non-i18n phases
    .{ .name = "naming", .fn_ptr = naming.run },
    .{ .name = "resolveNames", .fn_ptr = resolve_names.run },
    .{ .name = "chaining", .fn_ptr = chaining.run },
    .{ .name = "controlDirectives", .fn_ptr = control_directives.run },
    .{ .name = "convertAnimations", .fn_ptr = convert_animations.run },
    .{ .name = "deferResolveTargets", .fn_ptr = defer_resolve_targets.run },
    .{ .name = "resolveDeferDepsFns", .fn_ptr = resolve_defer_deps_fns.run },
    .{ .name = "generateArrowFunctions", .fn_ptr = generate_arrow_functions.run },
    .{ .name = "generateLocalLetReferences", .fn_ptr = generate_local_let_references.run },
    .{ .name = "generateVariables", .fn_ptr = generate_variables.run },
    .{ .name = "insertIncrementalHydrationRuntime", .fn_ptr = insert_incremental_hydration_runtime.run },
    .{ .name = "parseExtractedStyles", .fn_ptr = parse_extracted_styles.run },
    .{ .name = "phaseRemoveContentSelectors", .fn_ptr = phase_remove_content_selectors.run },
    .{ .name = "regexOptimization", .fn_ptr = regular_expression_optimization.run },
    .{ .name = "safeNavigationMigration", .fn_ptr = safe_navigation_migration.run },
    .{ .name = "resolveForeignContent", .fn_ptr = resolve_foreign_content.run },
    .{ .name = "wrapIcus", .fn_ptr = wrap_icus.run },
    .{ .name = "removeIllegalLetReferences", .fn_ptr = remove_illegal_let_references.run },
    .{ .name = "pipeVariadic", .fn_ptr = pipe_variadic.run },
    .{ .name = "allocateSlots", .fn_ptr = allocateSlots },
    .{ .name = "countVariables", .fn_ptr = countVariables },
    .{ .name = "validateXrefs", .fn_ptr = validateXrefs },
    .{ .name = "removeNoopOps", .fn_ptr = removeNoopOps },
    .{ .name = "compactXrefs", .fn_ptr = compactXrefs },
    .{ .name = "finalValidation", .fn_ptr = finalValidation },
    .{ .name = "generateViewId", .fn_ptr = generateViewId },
    .{ .name = "validateOpConsistency", .fn_ptr = validateOpConsistency },
    .{ .name = "optimizeTemplateSize", .fn_ptr = optimizeTemplateSize },
    .{ .name = "generateDirectiveMetadata", .fn_ptr = generateDirectiveMetadata },
};

/// Per-phase timing results (mutable copy for each transform call).
pub const PhaseTimings = struct {
    phase_name: []const u8,
    elapsed_ns: u64,
};

/// Main Transform Entry Point ──────────────────────────────
/// Runs all phases on root + embedded views.
pub fn transform(job: *ComponentCompilationJob, kind: CompilationKind) !void {
    _ = kind;
    // Run phases on root view
    for (PIPELINE_PHASES) |phase| {
        try phase.fn_ptr(job, &job.root);
    }

    // Run phases on embedded views
    var it = job.views.iterator();
    while (it.next()) |entry| {
        for (PIPELINE_PHASES) |phase| {
            try phase.fn_ptr(job, entry.value_ptr.*);
        }
    }
}

/// Run phases with per-phase nanosecond timing instrumentation.
/// Returns a slice of PhaseTimings (caller owns the memory via the allocator).
/// DOD: Single allocation for the timings array, std.time.nanoTimestamp per phase.
pub fn transformWithTimings(
    allocator: std.mem.Allocator,
    job: *ComponentCompilationJob,
    _: CompilationKind,
) ![]PhaseTimings {
    const phase_count = PIPELINE_PHASES.len;
    var timings = try allocator.alloc(PhaseTimings, phase_count);
    errdefer allocator.free(timings);

    // Run phases on root view
    for (PIPELINE_PHASES, 0..) |phase, i| {
        const start = getNsTimestamp();
        try phase.fn_ptr(job, &job.root);
        const end = getNsTimestamp();
        timings[i] = .{
            .phase_name = phase.name,
            .elapsed_ns = @intCast(end - start),
        };
    }

    // Run phases on embedded views (accumulate timing into existing entries)
    var it = job.views.iterator();
    while (it.next()) |entry| {
        for (PIPELINE_PHASES, 0..) |phase, i| {
            const start = getNsTimestamp();
            try phase.fn_ptr(job, entry.value_ptr.*);
            const end = getNsTimestamp();
            timings[i].elapsed_ns += @intCast(end - start);
        }
    }

    return timings;
}

/// Get current monotonic timestamp in nanoseconds
fn getNsTimestamp() i64 {
    var ts: std.os.linux.timespec = undefined;
    const rc = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
    if (rc != 0) return 0;
    return @as(i64, ts.sec) * std.time.ns_per_s + ts.nsec;
}

// ═══════════════════════════════════════════════════════════════
//  CREATE PHASES
// ═══════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════
//  BOTH PHASES (touch create + update)
// ═══════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════
//  UPDATE PHASES
// ═══════════════════════════════════════════════════════════════

/// Const version of getExpressionPtr for read-only access.
fn getExpressionPtrConst(op: IrOp) ?*const IrExpr {
    return switch (op.data) {
        .Binding => |b| b.expression,
        .Property => |p| p.expression,
        .DomProperty => |d| d.expression,
        .StyleProp => |s| s.expression,
        .ClassProp => |c| c.expression,
        .StyleMap => |s| s.expression,
        .ClassMap => |c| c.expression,
        .TwoWayProperty => |t| t.expression,
        .Conditional => |c| c.condition_expr,
        .Repeater => |r| r.track_by_fn orelse null,
        .StoreLet => |s| s.expression,
        .Variable => |v| v.value,
        .Animation => |a| a.expr,
        .AnimationBinding => |a| a.expression,
        .AnimationString => |a| a.expression,
        else => null,
    };
}

/// Update the expression pointer in an op's data (based on kind).
fn updateOpExpression(op: *IrOp, new_expr: *IrExpr) void {
    switch (op.kind) {
        .Binding => op.data.Binding.expression = new_expr,
        .Property => op.data.Property.expression = new_expr,
        .DomProperty => op.data.DomProperty.expression = new_expr,
        .StyleProp => op.data.StyleProp.expression = new_expr,
        .ClassProp => op.data.ClassProp.expression = new_expr,
        .StyleMap => op.data.StyleMap.expression = new_expr,
        .ClassMap => op.data.ClassMap.expression = new_expr,
        .TwoWayProperty => op.data.TwoWayProperty.expression = new_expr,
        .Conditional => op.data.Conditional.condition_expr = new_expr,
        .StoreLet => op.data.StoreLet.expression = new_expr,
        .Variable => op.data.Variable.value = new_expr,
        .AnimationBinding => op.data.AnimationBinding.expression = new_expr,
        .AnimationString => op.data.AnimationString.expression = new_expr,
        else => {},
    }
}

// ═══════════════════════════════════════════════════════════════
//  POST PHASES
// ═══════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════
//  PHASES 31–50
// ═══════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════
//  TESTS
// ═══════════════════════════════════════════════════════════════

test "all 50 phases run on a realistic job" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "TestComponent", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 20 };

    // ── Create ops ────────────────────────────────────────────
    // <div>                    xref=0
    //   <span>                 xref=1
    //     "Hello"              xref=2
    //   </span>
    //   <svg>                  xref=3 (namespace change → triggers emitNamespaceChanges)
    //   </svg>
    // </div>
    try job.root.create.append(.{
        .kind = .ElementStart,
        .xref = 0,
        .source_span = span,
        .data = .{ .ElementStart = .{ .name = "div", .namespace = .HTML, .attrs_xref = 0 } },
    });
    try job.root.create.append(.{
        .kind = .ElementStart,
        .xref = 1,
        .source_span = span,
        .data = .{ .ElementStart = .{ .name = "span", .namespace = .HTML, .attrs_xref = 0 } },
    });
    try job.root.create.append(.{
        .kind = .Text,
        .xref = 2,
        .source_span = span,
        .data = .{ .Text = .{ .const_index = 0 } },
    });
    try job.root.create.append(.{
        .kind = .ElementEnd,
        .xref = 1,
        .source_span = span,
        .data = .{ .ElementEnd = {} },
    });
    try job.root.create.append(.{
        .kind = .ElementStart,
        .xref = 3,
        .source_span = span,
        .data = .{ .ElementStart = .{ .name = "svg", .namespace = .SVG, .attrs_xref = 0 } },
    });
    try job.root.create.append(.{
        .kind = .ElementEnd,
        .xref = 3,
        .source_span = span,
        .data = .{ .ElementEnd = {} },
    });
    try job.root.create.append(.{
        .kind = .ElementEnd,
        .xref = 0,
        .source_span = span,
        .data = .{ .ElementEnd = {} },
    });

    // ── Expressions (stack-allocated) ────────────────────────
    var expr_title = IrExpr.readVariable("title", 0, span);
    var expr_empty = IrExpr.empty(span);
    var expr_name = IrExpr.readVariable("name", 1, span);
    var expr_count = IrExpr.readVariable("count", 2, span);

    // ── Update ops ────────────────────────────────────────────
    // Property binding [title]="title" on div (xref=0)
    try job.root.update.append(.{
        .kind = .Property,
        .xref = 0,
        .source_span = span,
        .data = .{ .Property = .{ .name = "title", .expression = &expr_title, .security_context = null } },
    });
    // Empty binding [id]="" — should be removed by removeEmptyBindings
    try job.root.update.append(.{
        .kind = .Binding,
        .xref = 0,
        .source_span = span,
        .data = .{ .Binding = .{ .name = "id", .expression = &expr_empty, .binding_kind = .Attribute } },
    });
    // Singleton interpolation on text node (xref=2)
    try job.root.update.append(.{
        .kind = .InterpolateText,
        .xref = 2,
        .source_span = span,
        .data = .{ .InterpolateText = .{
            .const_indices = &.{},
            .expressions = &.{&expr_name},
            .security_context = null,
        } },
    });
    // Two consecutive Advance ops — should be merged by removeDuplicateAdvanceOps
    try job.root.update.append(.{
        .kind = .Advance,
        .xref = 1,
        .source_span = span,
        .data = .{ .Advance = 1 },
    });
    try job.root.update.append(.{
        .kind = .Advance,
        .xref = 1,
        .source_span = span,
        .data = .{ .Advance = 2 },
    });
    // Property on svg (xref=3) — should be after the merged Advance
    try job.root.update.append(.{
        .kind = .Property,
        .xref = 3,
        .source_span = span,
        .data = .{ .Property = .{ .name = "width", .expression = &expr_count, .security_context = null } },
    });

    // ── Run all 30 phases ────────────────────────────────────
    try transform(&job, .Tmpl);

    // ── Post-condition assertions ─────────────────────────────
    // decls should be set and > 0 (we have xrefs 0-3)
    try std.testing.expect(job.root.decls != null);
    try std.testing.expect(job.root.decls.? >= 1);

    // vars should be set (0 since no Variable/StoreLet ops)
    try std.testing.expect(job.root.vars != null);

    // Create ops should have NamespaceDeclare inserted (SVG namespace change)
    // Original 7 ops + NamespaceDeclare = 8, possibly + Advance = 9
    try std.testing.expect(job.root.create.len() >= 8);

    // Update ops: removed empty Binding (-1), merged Advance ops (-1) = 5 - 2 = 3 minimum
    // But expandTwoWayBindings might add ops if there were TwoWayProperty ops (there aren't)
    try std.testing.expect(job.root.update.len() >= 3);
    try std.testing.expect(job.root.update.len() <= 5);

    // Verify the merged Advance: find it and check value = 3
    {
        var found_advance: bool = false;
        var advance_val: u32 = 0;
        for (job.root.update.ops.items) |op| {
            if (op.kind == .Advance) {
                advance_val = op.data.Advance;
                found_advance = true;
            }
        }
        try std.testing.expect(found_advance);
        try std.testing.expectEqual(@as(u32, 3), advance_val);
    }

    // Verify empty binding was removed
    {
        for (job.root.update.ops.items) |op| {
            if (op.kind == .Binding) {
                // If there's a Binding, it must not be empty
                try std.testing.expect(op.data.Binding.expression.kind != .EmptyExpr);
            }
        }
    }
}

test "markSecurityContexts marks innerHTML" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "SecComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 20 };

    // Create op with innerHTML attribute
    try job.root.create.append(.{
        .kind = .Attribute,
        .xref = 0,
        .source_span = span,
        .data = .{ .Attribute = .{ .name = "innerHTML", .value = "<b>bold</b>", .security_context = null } },
    });

    // Update op with innerHTML property
    var expr = IrExpr.readVariable("htmlContent", 0, span);
    try job.root.update.append(.{
        .kind = .Property,
        .xref = 0,
        .source_span = span,
        .data = .{ .Property = .{ .name = "innerHTML", .expression = &expr, .security_context = null } },
    });

    try injectSecurityContexts(&job, &job.root);

    // Check create op's innerHTML was marked with SecurityContext.HTML
    const create_items = job.root.create.ops.items;
    try std.testing.expect(create_items[0].data.Attribute.security_context != null);
    try std.testing.expectEqual(@intFromEnum(SecurityContext.HTML), create_items[0].data.Attribute.security_context.?);

    // Check update op's innerHTML was marked with SecurityContext.HTML
    const update_items = job.root.update.ops.items;
    try std.testing.expect(update_items[0].data.Property.security_context != null);
    try std.testing.expectEqual(@intFromEnum(SecurityContext.HTML), update_items[0].data.Property.security_context.?);
}

test "injectSecurityContexts uses schema registry for href/src" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "HrefComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 20 };

    var expr_url = IrExpr.readVariable("url", 0, span);
    // href → SecurityContext.URL
    try job.root.update.append(.{
        .kind = .Property,
        .xref = 0,
        .source_span = span,
        .data = .{ .Property = .{ .name = "href", .expression = &expr_url, .security_context = null } },
    });
    // src → SecurityContext.RESOURCE_URL
    try job.root.update.append(.{
        .kind = .Property,
        .xref = 1,
        .source_span = span,
        .data = .{ .Property = .{ .name = "src", .expression = &expr_url, .security_context = null } },
    });
    // safe property — no security context
    try job.root.update.append(.{
        .kind = .Property,
        .xref = 2,
        .source_span = span,
        .data = .{ .Property = .{ .name = "title", .expression = &expr_url, .security_context = null } },
    });

    try injectSecurityContexts(&job, &job.root);

    const items = job.root.update.ops.items;
    try std.testing.expectEqual(@intFromEnum(SecurityContext.URL), items[0].data.Property.security_context.?);
    try std.testing.expectEqual(@intFromEnum(SecurityContext.RESOURCE_URL), items[1].data.Property.security_context.?);
    try std.testing.expectEqual(null, items[2].data.Property.security_context);
}

test "injectSecurityContexts marks all InterpolateText as HTML" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "InterpComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 20 };
    var expr = IrExpr.readVariable("name", 0, span);

    try job.root.update.append(.{
        .kind = .InterpolateText,
        .xref = 0,
        .source_span = span,
        .data = .{ .InterpolateText = .{
            .const_indices = &.{},
            .expressions = &.{&expr},
            .security_context = null,
        } },
    });

    try injectSecurityContexts(&job, &job.root);

    const items = job.root.update.ops.items;
    try std.testing.expectEqual(@intFromEnum(SecurityContext.HTML), items[0].data.InterpolateText.security_context.?);
}

test "declareNamespaces inserts NamespaceDeclare for SVG" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "NsDeclComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 10 };

    try job.root.create.append(.{ .kind = .ElementStart, .xref = 0, .source_span = span, .data = .{ .ElementStart = .{ .name = "div", .namespace = .HTML, .attrs_xref = 0 } } });
    try job.root.create.append(.{ .kind = .ElementStart, .xref = 1, .source_span = span, .data = .{ .ElementStart = .{ .name = "svg", .namespace = .SVG, .attrs_xref = 0 } } });
    try job.root.create.append(.{ .kind = .ElementStart, .xref = 2, .source_span = span, .data = .{ .ElementStart = .{ .name = "circle", .namespace = .SVG, .attrs_xref = 0 } } });
    try job.root.create.append(.{ .kind = .ElementEnd, .xref = 2, .source_span = span, .data = .{ .ElementEnd = {} } });
    try job.root.create.append(.{ .kind = .ElementEnd, .xref = 1, .source_span = span, .data = .{ .ElementEnd = {} } });
    try job.root.create.append(.{ .kind = .ElementEnd, .xref = 0, .source_span = span, .data = .{ .ElementEnd = {} } });

    try declareNamespaces(&job, &job.root);

    // Should have inserted exactly 1 NamespaceDeclare (before first SVG element)
    const items = job.root.create.ops.items;
    var ns_declare_count: usize = 0;
    for (items) |op| {
        if (op.kind == .NamespaceDeclare) {
            ns_declare_count += 1;
            try std.testing.expectEqual(Namespace.SVG, op.data.NamespaceDeclare);
        }
    }
    try std.testing.expectEqual(@as(usize, 1), ns_declare_count);

    // NamespaceDeclare should come before the SVG ElementStart
    var svg_idx: usize = 0;
    var ns_idx: usize = 0;
    for (items, 0..) |op, i| {
        if (op.kind == .ElementStart and op.data.ElementStart.namespace == .SVG and svg_idx == 0) {
            svg_idx = i;
        }
        if (op.kind == .NamespaceDeclare) {
            ns_idx = i;
        }
    }
    try std.testing.expect(ns_idx < svg_idx);
}

test "declareNamespaces no-op for HTML-only templates" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "HtmlOnlyComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 10 };

    try job.root.create.append(.{ .kind = .ElementStart, .xref = 0, .source_span = span, .data = .{ .ElementStart = .{ .name = "div", .namespace = .HTML, .attrs_xref = 0 } } });
    try job.root.create.append(.{ .kind = .ElementEnd, .xref = 0, .source_span = span, .data = .{ .ElementEnd = {} } });

    try declareNamespaces(&job, &job.root);

    // No NamespaceDeclare should be inserted
    try std.testing.expectEqual(@as(usize, 2), job.root.create.len());
}

test "removeDuplicateAdvanceOps merges consecutive" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "AdvComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 5 };

    try job.root.update.append(.{ .kind = .Advance, .xref = 0, .source_span = span, .data = .{ .Advance = 1 } });
    try job.root.update.append(.{ .kind = .Advance, .xref = 0, .source_span = span, .data = .{ .Advance = 2 } });
    try job.root.update.append(.{ .kind = .Advance, .xref = 0, .source_span = span, .data = .{ .Advance = 3 } });
    try job.root.update.append(.{ .kind = .Property, .xref = 5, .source_span = span, .data = .{ .Property = .{ .name = "x", .expression = undefined, .security_context = null } } });

    try removeDuplicateAdvanceOps(&job, &job.root);

    try std.testing.expectEqual(@as(usize, 2), job.root.update.len());
    try std.testing.expectEqual(.Advance, job.root.update.ops.items[0].kind);
    try std.testing.expectEqual(@as(u32, 6), job.root.update.ops.items[0].data.Advance);
    try std.testing.expectEqual(.Property, job.root.update.ops.items[1].kind);
}

test "emitNamespaceChanges inserts NamespaceDeclare for SVG" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "NsComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 10 };

    try job.root.create.append(.{ .kind = .ElementStart, .xref = 0, .source_span = span, .data = .{ .ElementStart = .{ .name = "div", .namespace = .HTML, .attrs_xref = 0 } } });
    try job.root.create.append(.{ .kind = .ElementStart, .xref = 1, .source_span = span, .data = .{ .ElementStart = .{ .name = "svg", .namespace = .SVG, .attrs_xref = 0 } } });
    try job.root.create.append(.{ .kind = .ElementEnd, .xref = 1, .source_span = span, .data = .{ .ElementEnd = {} } });
    try job.root.create.append(.{ .kind = .ElementEnd, .xref = 0, .source_span = span, .data = .{ .ElementEnd = {} } });

    try emitNamespaceChanges(&job, &job.root);

    // Should have inserted NamespaceDeclare before SVG ElementStart
    try std.testing.expectEqual(@as(usize, 5), job.root.create.len());
    try std.testing.expectEqual(.NamespaceDeclare, job.root.create.ops.items[1].kind);
    try std.testing.expectEqual(Namespace.SVG, job.root.create.ops.items[1].data.NamespaceDeclare);
    try std.testing.expectEqual(.ElementStart, job.root.create.ops.items[2].kind);
    try std.testing.expectEqual(.SVG, job.root.create.ops.items[2].data.ElementStart.namespace);
}

test "orderCreationOps auto-closes unclosed elements" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "AutoClose", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 5 };

    // Open div but don't close it
    try job.root.create.append(.{ .kind = .ElementStart, .xref = 0, .source_span = span, .data = .{ .ElementStart = .{ .name = "div", .namespace = .HTML, .attrs_xref = 0 } } });

    try orderCreationOps(&job, &job.root);

    // Should have auto-closed with an ElementEnd
    try std.testing.expectEqual(@as(usize, 2), job.root.create.len());
    try std.testing.expectEqual(.ElementStart, job.root.create.ops.items[0].kind);
    try std.testing.expectEqual(.ElementEnd, job.root.create.ops.items[1].kind);
}

test "hoistStoreLets moves StoreLet to top" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "HoistComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 10 };

    var expr_a = IrExpr.readVariable("a", 0, span);
    var expr_b = IrExpr.readVariable("b", 1, span);

    // StoreLet appears AFTER other ops
    try job.root.update.append(.{ .kind = .Property, .xref = 0, .source_span = span, .data = .{ .Property = .{ .name = "x", .expression = &expr_a, .security_context = null } } });
    try job.root.update.append(.{ .kind = .StoreLet, .xref = 0, .source_span = span, .data = .{ .StoreLet = .{ .name = "tmp", .expression = &expr_b } } });

    try hoistStoreLets(&job, &job.root);

    try std.testing.expectEqual(.StoreLet, job.root.update.ops.items[0].kind);
    try std.testing.expectEqual(.Property, job.root.update.ops.items[1].kind);
}

test "processDeferredBlocks inserts default trigger" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "DeferComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 5 };

    // Defer without a trigger
    try job.root.create.append(.{ .kind = .Defer, .xref = 0, .source_span = span, .data = .{ .Defer = .{ .deps_xref = 0 } } });
    try job.root.create.append(.{ .kind = .ElementStart, .xref = 1, .source_span = span, .data = .{ .ElementStart = .{ .name = "div", .namespace = .HTML, .attrs_xref = 0 } } });

    try processDeferredBlocks(&job, &job.root);

    // Should have inserted DeferOn(.Idle) after Defer
    try std.testing.expectEqual(@as(usize, 3), job.root.create.len());
    try std.testing.expectEqual(.Defer, job.root.create.ops.items[0].kind);
    try std.testing.expectEqual(.DeferOn, job.root.create.ops.items[1].kind);
    try std.testing.expectEqual(ir_enums.DeferTriggerKind.Idle, job.root.create.ops.items[1].data.DeferOn);
    try std.testing.expectEqual(.ElementStart, job.root.create.ops.items[2].kind);
}

test "compactXrefs renumbers to dense" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "CompactComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 5 };

    // Sparse xrefs: 0, 5, 10
    try job.root.create.append(.{ .kind = .ElementStart, .xref = 0, .source_span = span, .data = .{ .ElementStart = .{ .name = "a", .namespace = .HTML, .attrs_xref = 0 } } });
    try job.root.create.append(.{ .kind = .ElementStart, .xref = 5, .source_span = span, .data = .{ .ElementStart = .{ .name = "b", .namespace = .HTML, .attrs_xref = 0 } } });
    try job.root.create.append(.{ .kind = .ElementStart, .xref = 10, .source_span = span, .data = .{ .ElementStart = .{ .name = "c", .namespace = .HTML, .attrs_xref = 0 } } });

    try compactXrefs(&job, &job.root);

    // Should be renumbered to 0, 1, 2
    const items = job.root.create.ops.items;
    try std.testing.expectEqual(@as(u32, 0), items[0].xref);
    try std.testing.expectEqual(@as(u32, 1), items[1].xref);
    try std.testing.expectEqual(@as(u32, 2), items[2].xref);
}

test "deduplicateAttributes removes duplicate attrs" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "DedupAttr", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 10 };

    try job.root.create.append(.{ .kind = .Attribute, .xref = 0, .source_span = span, .data = .{ .Attribute = .{ .name = "class", .value = "a", .security_context = null } } });
    try job.root.create.append(.{ .kind = .Attribute, .xref = 0, .source_span = span, .data = .{ .Attribute = .{ .name = "class", .value = "b", .security_context = null } } });
    try job.root.create.append(.{ .kind = .Attribute, .xref = 0, .source_span = span, .data = .{ .Attribute = .{ .name = "id", .value = "x", .security_context = null } } });

    try deduplicateAttributes(&job, &job.root);

    // Should have removed the duplicate "class" attr
    try std.testing.expectEqual(@as(usize, 2), job.root.create.len());
    try std.testing.expectEqualStrings("class", job.root.create.ops.items[0].data.Attribute.name);
    try std.testing.expectEqualStrings("id", job.root.create.ops.items[1].data.Attribute.name);
}

test "expandTwoWayBindings emits listener" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "TwoWayComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 10 };
    var expr = IrExpr.readVariable("value", 0, span);

    try job.root.update.append(.{
        .kind = .TwoWayProperty,
        .xref = 0,
        .source_span = span,
        .data = .{ .TwoWayProperty = .{ .name = "value", .expression = &expr } },
    });

    try expandTwoWayBindings(&job, &job.root);

    // Should have TwoWayProperty + TwoWayListener
    try std.testing.expectEqual(@as(usize, 2), job.root.update.len());
    try std.testing.expectEqual(.TwoWayProperty, job.root.update.ops.items[0].kind);
    try std.testing.expectEqual(.TwoWayListener, job.root.update.ops.items[1].kind);
    try std.testing.expectEqualStrings("value", job.root.update.ops.items[1].data.TwoWayListener.name);
}

test "attachSourceLocations fills missing spans" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "SpanComp", .Full);
    defer job.deinit();

    const good_span = AbsoluteSourceSpan{ .start = 5, .end = 15 };
    const empty_span = AbsoluteSourceSpan.empty();

    try job.root.create.append(.{ .kind = .ElementStart, .xref = 0, .source_span = good_span, .data = .{ .ElementStart = .{ .name = "div", .namespace = .HTML, .attrs_xref = 0 } } });
    try job.root.create.append(.{ .kind = .Text, .xref = 1, .source_span = empty_span, .data = .{ .Text = .{ .const_index = 0 } } });

    try attachSourceLocations(&job, &job.root);

    // The Text op's span should be filled from the preceding ElementStart
    try std.testing.expectEqual(good_span, job.root.create.ops.items[1].source_span);
}
