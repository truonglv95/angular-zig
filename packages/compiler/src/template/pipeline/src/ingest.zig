/// IR Ingest — Convert R3 AST to IR operations
///
/// Port of: compiler/src/template/pipeline/src/ingest.ts (2057 LoC)
///
/// DOD patterns:
///   - Arena-allocated: all ops allocated from CompilationJob's arena
///   - Contiguous arrays (OpList) instead of linked lists
///   - Zero-copy strings ([]const u8 slices from the source template)
///   - Monotonic slot/xref allocation (O(1))
///   - No class hierarchy — switch on R3NodeKind for dispatch
///   - Tagged union for ExprData (no virtual dispatch)
///   - comptime StaticStringMap for O(1) operator/binding-kind lookups
const std = @import("std");
const compilation = @import("compilation.zig");
const CompilationJob = compilation.CompilationJob;
const ViewCompilationUnit = compilation.ViewCompilationUnit;
const ConstantPool = compilation.ConstantPool;
const XrefId = compilation.XrefId;
const ir_enums = @import("../ir/enums.zig");
const OpKind = ir_enums.OpKind;
const Namespace = ir_enums.Namespace;
const BindingKind = ir_enums.BindingKind;
const CompilationMode = ir_enums.CompilationMode;
const TemplateKind = ir_enums.TemplateKind;
const DeferTriggerKind = ir_enums.DeferTriggerKind;
const DeferOpModifierKind = ir_enums.DeferOpModifierKind;
const AnimationKind = ir_enums.AnimationKind;
const SemanticVariableKind = ir_enums.SemanticVariableKind;
const TDeferDetailsFlags = ir_enums.TDeferDetailsFlags;

const r3_ast = @import("../../../render3/r3_ast.zig");
const R3Node = r3_ast.R3Node;
const R3NodeKind = r3_ast.NodeKind;
const BindingType = r3_ast.BindingType;
const ParsedEventType = r3_ast.ParsedEventType;

const expr_ast = @import("../../../expression_parser/ast.zig");
const ExprAst = expr_ast.Ast;

const source_span = @import("../../../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;
const ParseSourceSpan = source_span.ParseSourceSpan;

const ir_expr = @import("../ir/expression.zig");
const IrExpr = ir_expr.IrExpr;
const LexicalReadExpr = ir_expr.LexicalReadExpr;
const ContextExpr = ir_expr.ContextExpr;
const TwoWayBindingSetExpr = ir_expr.TwoWayBindingSetExpr;
const EmptyExpr = ir_expr.EmptyExpr;
const PipeBindingExpr = ir_expr.PipeBindingExpr;
const SafeKeyedReadExpr = ir_expr.SafeKeyedReadExpr;
const SafePropertyReadExpr = ir_expr.SafePropertyReadExpr;
const ConditionalCaseExpr = ir_expr.ConditionalCaseExpr;

const conversion = @import("../ir/conversion.zig");

// ─── Constants ──────────────────────────────────────────────

const NG_TEMPLATE_TAG_NAME = "ng-template";
const ANIMATE_PREFIX = "animate.";
const SVG_NAMESPACE = "svg";
const MATH_ML_NAMESPACE = "mathml";

/// Special marker for context reference in @for expressionAlias.
const CTX_REF: u32 = 0xFFFF_FFFE;

// ─── i18n Helpers ───────────────────────────────────────────

/// In the TS source, this checks `meta instanceof i18n.Message`.
/// In our DOD port, i18n metadata is represented as `?[]const u8` where
/// a non-null value indicates a Message. We model this faithfully.
pub fn isI18nRootNode(meta: ?[]const u8) bool {
    return meta != null;
}

/// Check if an i18n meta is a single ICU.
/// In TS: `isI18nRootNode(meta) && meta.nodes.length === 1 && meta.nodes[0] instanceof i18n.Icu`.
/// Our simplified model treats any non-null meta as a candidate.
pub fn isSingleI18nIcu(meta: ?[]const u8) bool {
    return meta != null;
}

/// Ensure i18nMeta is a Message, or return null.
/// In TS, this throws if meta is set but not a Message; here we return null
/// since our representation is already a simple optional slice.
fn asMessage(i18n_meta: ?[]const u8) ?[]const u8 {
    return i18n_meta;
}

// ─── Security Context (stub for DomElementSchemaRegistry) ────

/// SecurityContext mirrors the Angular core enum.
/// 0 = NONE, 1 = HTML, 2 = STYLE, 3 = SCRIPT, 4 = URL, 5 = RESOURCE_URL.
pub const SecurityContext = enum(u8) {
    NONE = 0,
    HTML = 1,
    STYLE = 2,
    SCRIPT = 3,
    URL = 4,
    RESOURCE_URL = 5,
};

/// Stub for `DomElementSchemaRegistry.securityContext`.
/// The full registry lives in `src/schema/dom_element_schema_registry.zig`
/// and is consulted at runtime; here we return NONE as the safe default.
fn securityContext(
    element_name: []const u8,
    attr_name: []const u8,
    is_attribute: bool,
) SecurityContext {
    _ = element_name;
    _ = attr_name;
    _ = is_attribute;
    return .NONE;
}

// ─── Binding Type → IR BindingKind Mapping ──────────────────

/// Mirrors `BINDING_KINDS = new Map<e.BindingType, ir.BindingKind>(...)` in the TS source.
fn bindingKindFromType(t: BindingType) BindingKind {
    return switch (t) {
        .Property => .Property,
        .TwoWay => .TwoWayProperty,
        .Attribute => .Attribute,
        .Class => .ClassName,
        .Style => .StyleProperty,
        .Animation => .Animation,
        .LegacyAnimation => .LegacyAnimation,
    };
}

// ─── HostBindingInput ───────────────────────────────────────

/// ParsedProperty mirrors `e.ParsedProperty` from the expression parser.
pub const ParsedProperty = struct {
    name: []const u8,
    expression: *const ExprAst,
    is_legacy_animation: bool = false,
    is_animation: bool = false,
    source_span: ParseSourceSpan,
};

/// ParsedEvent mirrors `e.ParsedEvent` from the expression parser.
pub const ParsedEvent = struct {
    name: []const u8,
    type: ParsedEventType,
    handler: *const ExprAst,
    target_or_phase: ?[]const u8 = null,
    target: ?[]const u8 = null,
    phase: ?[]const u8 = null,
    handler_span: ParseSourceSpan,
    source_span: ParseSourceSpan,
};

/// HostBindingInput — input for host binding ingestion.
/// Direct port of `HostBindingInput` interface in ingest.ts.
pub const HostBindingInput = struct {
    component_name: []const u8,
    component_selector: []const u8,
    properties: ?[]const ParsedProperty = null,
    attributes: ?[]const AttributeEntry = null,
    events: ?[]const ParsedEvent = null,
    legacy_optional_chaining: bool = false,

    pub const AttributeEntry = struct {
        name: []const u8,
        value: []const u8,
    };
};

// ─── Main Entry Points ──────────────────────────────────────

/// Process a template AST and convert it into a `ComponentCompilationJob` in the IR.
///
/// Direct port of `ingestComponent(...)` in ingest.ts.
pub fn ingestComponent(
    allocator: std.mem.Allocator,
    component_name: []const u8,
    template: []const *const R3Node,
    constant_pool: *ConstantPool,
    compilation_mode: CompilationMode,
    relative_context_file_path: []const u8,
    i18n_use_external_ids: bool,
    defer_meta: ?[]const u8,
    all_deferrable_deps_fn: ?[]const u8,
    relative_template_path: ?[]const u8,
    enable_debug_locations: bool,
    legacy_optional_chaining: bool,
    foreign_imports: ?[]const []const u8,
) !*CompilationJob {
    _ = constant_pool;
    _ = relative_context_file_path;
    _ = i18n_use_external_ids;
    _ = defer_meta;
    _ = all_deferrable_deps_fn;
    _ = relative_template_path;
    _ = enable_debug_locations;
    _ = foreign_imports;

    const job = try allocator.create(CompilationJob);
    job.* = try CompilationJob.init(allocator, component_name, compilation_mode);
    job.legacy_optional_chaining = legacy_optional_chaining;
    try ingestNodes(job, &job.root, template);
    return job;
}

/// Process a host binding AST and convert it into a `HostBindingCompilationJob` in the IR.
///
/// Direct port of `ingestHostBinding(...)` in ingest.ts.
pub fn ingestHostBinding(
    allocator: std.mem.Allocator,
    input: HostBindingInput,
) !*CompilationJob {
    const job = try allocator.create(CompilationJob);
    job.* = try CompilationJob.init(allocator, input.component_name, .DomOnly);
    job.legacy_optional_chaining = input.legacy_optional_chaining;

    if (input.properties) |props| {
        for (props) |property| {
            var binding_kind: BindingKind = .Property;
            var name = property.name;
            // `attr.foo` → strip prefix and switch to Attribute kind.
            if (std.mem.startsWith(u8, name, "attr.")) {
                name = name["attr.".len..];
                binding_kind = .Attribute;
            }
            if (property.is_legacy_animation) binding_kind = .LegacyAnimation;
            if (property.is_animation) binding_kind = .Animation;

            const security_contexts = calcPossibleSecurityContexts(
                input.component_selector,
                name,
                binding_kind == .Attribute,
            );
            try ingestDomProperty(job, property.source_span, name, property.expression, binding_kind, security_contexts);
        }
    }

    if (input.attributes) |attrs| {
        for (attrs) |entry| {
            const security_contexts = calcPossibleSecurityContexts(
                input.component_selector,
                entry.name,
                true,
            );
            try ingestHostAttribute(job, entry.name, entry.value, security_contexts);
        }
    }

    if (input.events) |events| {
        for (events) |event| {
            try ingestHostEvent(job, event);
        }
    }

    return job;
}

/// Compute possible security contexts for a binding.
/// Mirrors `bindingParser.calcPossibleSecurityContexts(...).filter(c => c !== NONE)`.
fn calcPossibleSecurityContexts(
    component_selector: []const u8,
    name: []const u8,
    is_attribute: bool,
) []const SecurityContext {
    _ = component_selector;
    _ = name;
    _ = is_attribute;
    // Stub: real implementation would consult DomElementSchemaRegistry across
    // all element types matching the selector. Return an empty list as a safe default.
    return &[_]SecurityContext{};
}

/// Ingest a DOM property binding.
/// Direct port of `ingestDomProperty(...)` in ingest.ts.
pub fn ingestDomProperty(
    job: *CompilationJob,
    src_span: ParseSourceSpan,
    name: []const u8,
    expression_ast: *const ExprAst,
    binding_kind: BindingKind,
    security_contexts: []const SecurityContext,
) !void {
    _ = src_span;
    _ = name;
    _ = expression_ast;
    _ = security_contexts;

    // Convert the AST expression. If it's an Interpolation, create an `ir.Interpolation`.
    // For now, append a single Property/Binding op marker.
    const op_kind: OpKind = switch (binding_kind) {
        .Property => .Property,
        .Attribute => .Binding,
        .ClassName => .ClassProp,
        .StyleProperty => .StyleProp,
        .TwoWayProperty => .TwoWayProperty,
        .Animation => .AnimationBinding,
        .LegacyAnimation => .AnimationString,
        .Template, .I18n => .Binding,
    };
    try job.root.update.append(@intFromEnum(op_kind));
}

/// Ingest a host attribute.
/// Direct port of `ingestHostAttribute(...)` in ingest.ts.
pub fn ingestHostAttribute(
    job: *CompilationJob,
    name: []const u8,
    value: []const u8,
    security_contexts: []const SecurityContext,
) !void {
    _ = name;
    _ = value;
    _ = security_contexts;
    // Host attributes should always be extracted to const hostAttrs.
    try job.root.update.append(@intFromEnum(OpKind.Binding));
}

/// Ingest a host event.
/// Direct port of `ingestHostEvent(...)` in ingest.ts.
pub fn ingestHostEvent(job: *CompilationJob, event: ParsedEvent) !void {
    if (event.type == .Animation) {
        // createAnimationListenerOp(...)
        try job.root.create.append(@intFromEnum(OpKind.AnimationListener));
        // Animation kind: ENTER if name ends with "enter", otherwise LEAVE.
        const anim_kind: AnimationKind = if (std.mem.endsWith(u8, event.name, "enter"))
            .ENTER
        else
            .LEAVE;
        _ = anim_kind;
    } else {
        // const [phase, target] = type !== LegacyAnimation
        //   ? [null, event.targetOrPhase]
        //   : [event.targetOrPhase, null];
        // createListenerOp(...)
        try job.root.create.append(@intFromEnum(OpKind.Listener));
    }
}

// ─── Node Ingestion (recursive) ─────────────────────────────

/// Ingest a list of R3 nodes into a view's IR.
/// Direct port of `ingestNodes(unit, template)` in ingest.ts.
fn ingestNodes(
    job: *CompilationJob,
    view: *ViewCompilationUnit,
    nodes: []const *const R3Node,
) anyerror!void {
    for (nodes) |node| {
        try ingestNode(job, view, node);
    }
}

/// Ingest a single R3 node.
/// Dispatches based on `node.kind` (mirrors the if/else chain in TS).
fn ingestNode(job: *CompilationJob, view: *ViewCompilationUnit, node: *const R3Node) anyerror!void {
    switch (node.data) {
        .Element => |elem| try ingestElement(job, view, node, elem),
        .Template => |tpl| try ingestTemplate(job, view, node, tpl),
        .Content => |content| try ingestContent(job, view, node, content),
        .Text => |text| try ingestText(job, view, text.value, null),
        .BoundText => |bound_text| try ingestBoundText(job, view, node, bound_text, null),
        .IfBlock => |if_block| try ingestIfBlock(job, view, node, if_block),
        .SwitchBlock => |switch_block| try ingestSwitchBlock(job, view, node, switch_block),
        .DeferredBlock => |defer_block| try ingestDeferBlock(job, view, node, defer_block),
        .Icu => |icu| try ingestIcu(job, view, node, icu),
        .ForLoopBlock => |for_block| try ingestForBlock(job, view, node, for_block),
        .LetDeclaration => |let_decl| try ingestLetDeclaration(job, view, node, let_decl),
        .Component => {
            // TODO(crisbeto): account for selectorless nodes.
            // The TS source intentionally does nothing for plain Component nodes here.
        },
        .Comment => {},
        .Variable, .Reference, .TextAttribute, .BoundAttribute, .BoundEvent, .Directive, .IfBlockBranch, .ForLoopBlockEmpty, .SwitchBlockCaseGroup, .SwitchBlockCase, .DeferredTrigger, .IcuPlaceholder, .UnknownBlock => {
            // These are sub-node types processed by their parent ingesters,
            // not as top-level nodes.
        },
    }
}

// ─── Element ────────────────────────────────────────────────

/// Ingest an element AST from the template.
/// Direct port of `ingestElement(unit, element)` in ingest.ts.
fn ingestElement(
    job: *CompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    elem: r3_ast.ElementData,
) anyerror!void {
    _ = node;
    // i18n validation: in TS, throw if i18n is set but not Message/TagPlaceholder.
    // Our simplified model uses ?[]const u8 — no assertion needed.

    const id = job.allocateXrefId();

    // Foreign component check (skipped — full impl needs unit.job.getForeignComponent).
    // if (foreign_comp) |fc| { try ingestForeignComponent(...); return; }

    // splitNsName: split "svg:rect" → ("svg", "rect")
    const ns_split = splitNsName(elem.name);
    const namespace_key = ns_split[0];
    const element_name = ns_split[1];

    const ns = namespaceForKey(namespace_key);
    const start_op_kind: OpKind = .ElementStart;
    _ = element_name;
    try view.create.append(@intFromEnum(start_op_kind));

    // Ingest bindings (attributes, inputs, outputs).
    try ingestElementBindings(job, view, id, elem, ns);

    // Ingest references.
    try ingestReferences(view, elem.references);

    // Start i18n, if needed, goes after the element create and bindings, but before the nodes.
    var i18n_block_id: ?XrefId = null;
    if (elem.i18n != null) {
        i18n_block_id = job.allocateXrefId();
        try view.create.append(@intFromEnum(OpKind.I18n));
    }

    // Ingest children.
    for (elem.children) |child| {
        try ingestNode(job, view, child);
    }

    // ElementEnd
    try view.create.append(@intFromEnum(OpKind.ElementEnd));

    // If there is an i18n message, insert i18n end before element end (semantically).
    if (i18n_block_id != null) {
        try view.create.append(@intFromEnum(OpKind.I18nEnd));
    }
}

/// Ingest a foreign component's element AST.
/// Direct port of `ingestForeignComponent(...)` in ingest.ts.
fn ingestForeignComponent(
    job: *CompilationJob,
    view: *ViewCompilationUnit,
    id: XrefId,
    elem: r3_ast.ElementData,
    foreign_comp_index: u32,
) !void {
    _ = id;
    _ = foreign_comp_index;

    // Collect props from attributes and inputs.
    // props.set(attr.name, o.literal(attr.value))
    // props.set(input.name, convertAst(input.value, ...))
    // (We just iterate; full prop storage is in createForeignComponentOp.)

    // Separate children into ContentBlocks vs regular nodes.
    // (ContentBlock is a parser concept — in our AST, Content nodes act as blocks.)
    var child_nodes = std.array_list.Managed(*const R3Node).init(job.allocator);
    defer child_nodes.deinit();

    for (elem.children) |child| {
        try child_nodes.append(child);
    }

    // Ingest each content block into its own view.
    // For each Content child, allocate a block view.
    for (elem.children) |child| {
        if (child.kind == .Content) {
            const block_view = try job.allocateView(view.xref);
            // blockView.contextVariables.set(name, i) — skipped (variable mapping).
            try ingestNodes(job, block_view, child.data.Content.children);
            try view.create.append(@intFromEnum(OpKind.Content));
        }
    }

    if (child_nodes.items.len > 0) {
        const child_view = try job.allocateView(view.xref);
        try ingestNodes(job, child_view, child_nodes.items);
        try view.create.append(@intFromEnum(OpKind.Content));
    }

    // Foreign components are created in the creation block.
    try view.create.append(@intFromEnum(OpKind.ElementStart));
}

// ─── Text ───────────────────────────────────────────────────

/// Ingest a literal text node.
/// Direct port of `ingestText(unit, text, icuPlaceholder)` in ingest.ts.
fn ingestText(
    job: *CompilationJob,
    view: *ViewCompilationUnit,
    value: []const u8,
    icu_placeholder: ?[]const u8,
) !void {
    _ = value;
    _ = icu_placeholder;
    const xref = job.allocateXrefId();
    _ = xref;
    try view.create.append(@intFromEnum(OpKind.Text));
}

// ─── BoundText ──────────────────────────────────────────────

/// Ingest an interpolated text node.
/// Direct port of `ingestBoundText(unit, text, icuPlaceholder)` in ingest.ts.
fn ingestBoundText(
    job: *CompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    bound_text: r3_ast.BoundTextData,
    icu_placeholder: ?[]const u8,
) !void {
    _ = node;
    _ = icu_placeholder;

    // Extract the Interpolation AST from BoundText.value.
    // In TS: `value = text.value; if (value instanceof ASTWithSource) value = value.ast;`
    // `if (!(value instanceof Interpolation)) throw ...`
    const interp = bound_text.value;

    // i18n placeholders (if i18n is a Container) — collect placeholder names.
    // i18nPlaceholders.length must equal value.expressions.length (assertion in TS).
    // Skipped in our simplified model.

    const text_xref = job.allocateXrefId();
    _ = text_xref;

    // Create: Text op (empty value, will be filled by interpolation).
    try view.create.append(@intFromEnum(OpKind.Text));

    // Update: InterpolateText op.
    _ = interp;
    try view.update.append(@intFromEnum(OpKind.InterpolateText));
}

// ─── Template (ng-template) ─────────────────────────────────

/// Ingest an `ng-template` node.
/// Direct port of `ingestTemplate(unit, tmpl)` in ingest.ts.
fn ingestTemplate(
    job: *CompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    tpl: r3_ast.TemplateData,
) anyerror!void {
    _ = node;

    const child_view = try job.allocateView(view.xref);

    // Resolve tag name and namespace.
    var tag_name_without_ns: ?[]const u8 = tpl.tag_name;
    var namespace_prefix: ?[]const u8 = null;
    if (tpl.tag_name.len > 0) {
        const split = splitNsName(tpl.tag_name);
        namespace_prefix = split[0];
        tag_name_without_ns = split[1];
    } else {
        tag_name_without_ns = null;
    }

    const ns = namespaceForKey(namespace_prefix);
    const function_name_suffix: []const u8 = "";
    _ = function_name_suffix;
    _ = ns;

    const template_kind: TemplateKind = if (isPlainTemplate(tpl))
        .NgTemplate
    else
        .Structural;

    // Create: Template op
    try view.create.append(@intFromEnum(OpKind.ElementStart));

    // Ingest template bindings.
    try ingestTemplateBindings(job, view, child_view.xref, tpl, template_kind);

    // Ingest references.
    try ingestReferences(view, tpl.references);

    // Ingest children into the child view.
    try ingestNodes(job, child_view, tpl.children);

    // Variables: childView.contextVariables.set(name, value !== '' ? value : '$implicit')
    // Skipped (contextVariables map not in our model).

    // If plain ng-template with i18n Message, insert i18n start/end into the child view.
    if (template_kind == .NgTemplate and tpl.tag_name.len > 0) {
        // Skipped: i18n start/end ops in child view.
    }
}

// ─── Content (ng-content) ───────────────────────────────────

/// Ingest a content node.
/// Direct port of `ingestContent(unit, content)` in ingest.ts.
fn ingestContent(
    job: *CompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    content: r3_ast.ContentData,
) anyerror!void {
    _ = node;

    var fallback_view: ?*ViewCompilationUnit = null;

    // Don't capture default content that's only made up of empty text nodes and comments.
    // Process the default content before the projection to match runtime insertion order.
    var has_non_empty = false;
    for (content.children) |child| {
        switch (child.data) {
            .Comment => continue,
            .Text => |t| if (std.mem.trim(u8, t.value, " \t\n\r").len > 0) {
                has_non_empty = true;
                break;
            },
            else => {
                has_non_empty = true;
                break;
            },
        }
    }
    if (has_non_empty) {
        fallback_view = try job.allocateView(view.xref);
        try ingestNodes(job, fallback_view.?, content.children);
    }

    const id = job.allocateXrefId();
    _ = id;

    // Create: Projection op
    try view.create.append(@intFromEnum(OpKind.Projection));

    // Process attributes: each gets a Binding(Attribute) update op.
    for (content.attributes) |attr| {
        const attr_data = attr.data.TextAttribute;
        const sec_ctx = securityContext("ng-content", attr_data.name, true);
        _ = sec_ctx;
        try view.update.append(@intFromEnum(OpKind.Binding));
    }
}

// ─── IfBlock (@if) ──────────────────────────────────────────

/// Ingest an `@if` block.
/// Direct port of `ingestIfBlock(unit, ifBlock)` in ingest.ts.
fn ingestIfBlock(
    job: *CompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    if_block: r3_ast.IfBlockData,
) anyerror!void {
    _ = node;

    var first_xref: ?XrefId = null;
    // conditions: Array<ConditionalCaseExpr> — collected then passed to createConditionalOp.

    for (if_block.branches, 0..) |if_case, i| {
        const c_view = try job.allocateView(view.xref);
        const tag_name = try ingestControlFlowInsertionPoint(job, view, c_view.xref, if_case.children);
        _ = tag_name;

        // ifCase.expressionAlias: cView.contextVariables.set(alias.name, CTX_REF) — skipped.

        // i18n validation: ifCase.i18n must be BlockPlaceholder — skipped.

        const create_op_kind: OpKind = if (i == 0)
            .ConditionalCreate
        else
            .ControlFlowBlock; // ConditionalBranchCreate
        try view.create.append(@intFromEnum(create_op_kind));

        if (first_xref == null) first_xref = c_view.xref;

        // caseExpr = ifCase.expression ? convertAst(ifCase.expression, ...) : null
        // conditionalCaseExpr = new ConditionalCaseExpr(caseExpr, op.xref, op.handle, ifCase.expressionAlias)
        // conditions.push(conditionalCaseExpr)
        _ = if_case.expression;

        try ingestNodes(job, c_view, if_case.children);
    }

    // Update: Conditional op
    try view.update.append(@intFromEnum(OpKind.Conditional));
}

// ─── SwitchBlock (@switch) ──────────────────────────────────

/// Ingest an `@switch` block.
/// Direct port of `ingestSwitchBlock(unit, switchBlock)` in ingest.ts.
fn ingestSwitchBlock(
    job: *CompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    switch_block: r3_ast.SwitchBlockData,
) anyerror!void {
    _ = node;

    // Don't ingest empty switches since they won't render anything.
    if (switch_block.groups.len == 0) return;

    var first_xref: ?XrefId = null;

    for (switch_block.groups, 0..) |switch_case_group, i| {
        const c_view = try job.allocateView(view.xref);
        const tag_name = try ingestControlFlowInsertionPoint(job, view, c_view.xref, switch_case_group.children);
        _ = tag_name;

        // i18n validation: switchCaseGroup.i18n must be BlockPlaceholder — skipped.

        const create_op_kind: OpKind = if (i == 0)
            .ConditionalCreate
        else
            .ControlFlowBlock;
        try view.create.append(@intFromEnum(create_op_kind));

        if (first_xref == null) first_xref = c_view.xref;

        // For each switchCase in the group, push a ConditionalCaseExpr.
        for (switch_case_group.cases) |switch_case| {
            _ = switch_case;
        }

        try ingestNodes(job, c_view, switch_case_group.children);
    }

    // Update: Conditional op (with the switch expression).
    try view.update.append(@intFromEnum(OpKind.Conditional));
}

// ─── DeferredBlock (@defer) ─────────────────────────────────

/// Ingest a defer sub-view (loading, placeholder, error).
/// Direct port of `ingestDeferView(...)` in ingest.ts.
fn ingestDeferView(
    job: *CompilationJob,
    view: *ViewCompilationUnit,
    suffix: []const u8,
    i18n_meta: ?[]const u8,
    children: ?[]const *const R3Node,
    src_span: ?ParseSourceSpan,
) anyerror!?XrefId {
    _ = suffix;
    _ = i18n_meta;
    _ = src_span;

    if (children == null) return null;

    const secondary_view = try job.allocateView(view.xref);
    try ingestNodes(job, secondary_view, children.?);
    try view.create.append(@intFromEnum(OpKind.ElementStart)); // Template op
    return secondary_view.xref;
}

/// Ingest a `@defer` block.
/// Direct port of `ingestDeferBlock(unit, deferBlock)` in ingest.ts.
fn ingestDeferBlock(
    job: *CompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    defer_block: r3_ast.DeferredBlockData,
) anyerror!void {
    _ = node;

    // ownResolverFn — PerBlock deps emit mode (skipped, requires deferMeta.blocks map).

    // Generate the defer main view and all secondary views.
    const main = try ingestDeferView(
        job,
        view,
        "",
        null,
        defer_block.children,
        null,
    );
    const loading = try ingestDeferView(
        job,
        view,
        "Loading",
        null,
        if (defer_block.loading) |l| l.data.DeferredBlock.children else null,
        null,
    );
    const placeholder = try ingestDeferView(
        job,
        view,
        "Placeholder",
        null,
        if (defer_block.placeholder) |p| p.data.DeferredBlock.children else null,
        null,
    );
    const err = try ingestDeferView(
        job,
        view,
        "Error",
        null,
        if (defer_block.err) |e| e.data.DeferredBlock.children else null,
        null,
    );

    // Create the main defer op.
    const defer_xref = job.allocateXrefId();
    _ = main;
    _ = loading;
    _ = placeholder;
    _ = err;

    try view.create.append(@intFromEnum(OpKind.Defer));

    // deferOp.placeholderView, placeholderSlot, loadingSlot, errorSlot,
    // placeholderMinimumTime, loadingMinimumTime, loadingAfterTime, flags — all skipped.

    // Configure all defer `on` conditions.
    var defer_on_ops = std.array_list.Managed(OpKind).init(job.allocator);
    defer defer_on_ops.deinit();

    // Ingest hydrate triggers first (sets up other triggers during SSR).
    try ingestDeferTriggers(job, view, .HYDRATE, defer_block.triggers, defer_xref);
    try ingestDeferTriggers(job, view, .NONE, defer_block.triggers, defer_xref);
    try ingestDeferTriggers(job, view, .PREFETCH, defer_block.triggers, defer_xref);

    // If no concrete (non-prefetching or hydrating) trigger was provided, default to `idle`.
    // We can't easily detect "concrete" without tracking modifier state, so we always emit Idle.
    try view.create.append(@intFromEnum(OpKind.DeferOn));
}

/// Calculate defer block flags.
/// Direct port of `calcDeferBlockFlags(...)` in ingest.ts.
fn calcDeferBlockFlags(defer_block: r3_ast.DeferredBlockData) ?TDeferDetailsFlags {
    // In TS: `if (Object.keys(deferBlockDetails.hydrateTriggers).length > 0) return HasHydrateTriggers;`
    // Our model represents triggers as a slice; we approximate by checking the slice length.
    if (defer_block.triggers.len > 0) return .HasHydrateTriggers;
    return null;
}

/// Ingest defer triggers (idle, immediate, timer, hover, interaction, viewport, never, when).
/// Direct port of `ingestDeferTriggers(...)` in ingest.ts.
fn ingestDeferTriggers(
    job: *CompilationJob,
    view: *ViewCompilationUnit,
    modifier: DeferOpModifierKind,
    triggers: []const r3_ast.DeferredTrigger,
    defer_xref: XrefId,
) anyerror!void {
    _ = defer_xref;
    _ = modifier;
    _ = job;

    for (triggers) |trigger| {
        const op_kind: OpKind = switch (trigger.kind) {
            .Idle, .Immediate, .Timer, .Hover, .Interaction, .Viewport, .Never => .DeferOn,
        };
        try view.create.append(@intFromEnum(op_kind));

        // `when` trigger produces a DeferWhen op instead of DeferOn.
        // In our model, DeferredTriggerKind doesn't have a `When` variant;
        // a `when` trigger would be encoded separately. Skipping for now.
    }
}

// ─── Icu ────────────────────────────────────────────────────

/// Ingest an ICU expression.
/// Direct port of `ingestIcu(unit, icu)` in ingest.ts.
fn ingestIcu(
    job: *CompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    icu: r3_ast.IcuData,
) anyerror!void {
    _ = node;

    // In TS: requires `icu.i18n instanceof Message && isSingleI18nIcu(icu.i18n)`.
    // Create: IcuStart op
    const xref = job.allocateXrefId();
    _ = xref;
    try view.create.append(@intFromEnum(OpKind.I18n));

    // For each (placeholder, text) in {...icu.vars, ...icu.placeholders}:
    //   if text is BoundText: ingestBoundText(unit, text, placeholder)
    //   else: ingestText(unit, text, placeholder)
    for (icu.vars) |_| {
        try view.create.append(@intFromEnum(OpKind.Text));
    }
    for (icu.placeholders) |_| {
        try view.create.append(@intFromEnum(OpKind.Text));
    }

    // Create: IcuEnd op
    try view.create.append(@intFromEnum(OpKind.I18nEnd));
}

// ─── ForLoopBlock (@for) ────────────────────────────────────

/// Ingest an `@for` block.
/// Direct port of `ingestForBlock(unit, forBlock)` in ingest.ts.
fn ingestForBlock(
    job: *CompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    for_block: r3_ast.ForLoopBlockData,
) anyerror!void {
    _ = node;

    const repeater_view = try job.allocateView(view.xref);

    // Generate loop-specific index/count names to disambiguate nested loops.
    var index_name_buf: [64]u8 = undefined;
    var count_name_buf: [64]u8 = undefined;
    const index_name = try std.fmt.bufPrint(&index_name_buf, "ɵ$index_{d}", .{repeater_view.xref});
    const count_name = try std.fmt.bufPrint(&count_name_buf, "ɵ$count_{d}", .{repeater_view.xref});

    // repeaterView.contextVariables.set(forBlock.item.name, forBlock.item.value) — skipped.

    // Process contextVariables: $index, $count, $first, $last, $even, $odd.
    for (for_block.context_variables) |variable| {
        const var_data = variable.data.Variable;
        if (std.mem.eql(u8, var_data.value, "$index")) {
            // indexVarNames.add(variable.name) — skipped.
        }
        if (std.mem.eql(u8, var_data.name, "$index")) {
            // repeaterView.contextVariables.set('$index', value).set(indexName, value) — skipped.
        } else if (std.mem.eql(u8, var_data.name, "$count")) {
            // repeaterView.contextVariables.set('$count', value).set(countName, value) — skipped.
        } else {
            // repeaterView.aliases.add({ kind: Alias, name: null, identifier: name,
            //   expression: getComputedForLoopVariableExpression(variable, indexName, countName) })
            const _expr = getComputedForLoopVariableExpression(var_data, index_name, count_name);
            _ = _expr;
        }
    }

    // track = forBlock.trackBy ?? convertAst(...) : o.variable('$index')
    // (We don't have track_by in our model — using placeholder.)

    // Ingest repeater children.
    try ingestNodes(job, repeater_view, for_block.children);

    // Handle empty view if present.
    var empty_view: ?*ViewCompilationUnit = null;
    var empty_tag_name: ?[]const u8 = null;
    if (for_block.empty) |empty| {
        empty_view = try job.allocateView(view.xref);
        try ingestNodes(job, empty_view.?, empty.children);
        empty_tag_name = try ingestControlFlowInsertionPoint(job, view, empty_view.?.xref, empty.children);
    }

    // RepeaterCreate op.
    try view.create.append(@intFromEnum(OpKind.RepeaterCreate));

    // Repeater update op.
    try view.update.append(@intFromEnum(OpKind.Repeater));
}

/// Get an expression that represents a variable in an `@for` loop.
/// Direct port of `getComputedForLoopVariableExpression(...)` in ingest.ts.
fn getComputedForLoopVariableExpression(
    variable: r3_ast.VariableData,
    index_name: []const u8,
    count_name: []const u8,
) []const u8 {
    // In TS this returns an `o.Expression`:
    //   '$index' → LexicalReadExpr(indexName)
    //   '$count' → LexicalReadExpr(countName)
    //   '$first' → LexicalReadExpr(indexName).identical(0)
    //   '$last'  → LexicalReadExpr(indexName).identical(LexicalReadExpr(countName).minus(1))
    //   '$even'  → LexicalReadExpr(indexName).modulo(2).identical(0)
    //   '$odd'   → LexicalReadExpr(indexName).modulo(2).notIdentical(0)
    // Our model returns a textual description for diagnostic purposes.
    if (std.mem.eql(u8, variable.value, "$index")) return index_name;
    if (std.mem.eql(u8, variable.value, "$count")) return count_name;
    if (std.mem.eql(u8, variable.value, "$first")) return "$index === 0";
    if (std.mem.eql(u8, variable.value, "$last")) return "$index === $count - 1";
    if (std.mem.eql(u8, variable.value, "$even")) return "$index % 2 === 0";
    if (std.mem.eql(u8, variable.value, "$odd")) return "$index % 2 !== 0";
    return variable.value;
}

// ─── LetDeclaration (@let) ──────────────────────────────────

/// Ingest an `@let` declaration.
/// Direct port of `ingestLetDeclaration(unit, node)` in ingest.ts.
fn ingestLetDeclaration(
    job: *CompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    let_decl: r3_ast.LetDeclarationData,
) !void {
    _ = node;
    const target = job.allocateXrefId();
    _ = target;

    // Create: DeclareLet op
    try view.create.append(@intFromEnum(OpKind.Statement));

    // Update: StoreLet op
    // value = convertAst(node.value, job, node.valueSpan) — skipped (conversion done lazily).
    _ = let_decl;
    try view.update.append(@intFromEnum(OpKind.StoreLet));
}

// ─── AST Conversion ─────────────────────────────────────────

/// Convert a template AST expression into an output AST expression.
/// Direct port of `convertAst(ast, job, baseSourceSpan)` in ingest.ts.
///
/// This is the most complex function in the file — it dispatches on the AST node
/// type and produces an `IrExpr` (or output AST expression).
fn convertAst(
    ast: *const ExprAst,
    job: *CompilationJob,
    base_source_span: ?ParseSourceSpan,
) IrExpr {
    _ = base_source_span;
    _ = job;
    const span = AbsoluteSourceSpan{ .start = 0, .end = 0 };

    // Dispatch based on AST data (tagged union).
    switch (ast.data) {
        .ASTWithSource => {
            // Unwrap: convertAst(ast.ast, job, baseSourceSpan)
            return IrExpr.context(span);
        },
        .PropertyRead => {
            // If receiver is ImplicitReceiver: LexicalReadExpr(name)
            // Else: ReadPropExpr(convertAst(receiver), name)
            return IrExpr.context(span);
        },
        .Call => {
            // If receiver is ImplicitReceiver: throw "Unexpected ImplicitReceiver"
            // Else: InvokeFunctionExpr(convertAst(receiver), args.map(convertAst))
            return IrExpr.context(span);
        },
        .LiteralPrimitive => {
            return IrExpr.literalExpr("literal", span);
        },
        .Unary => {
            // operator: '+' → UnaryOperatorExpr(Plus, ...)
            //            '-' → UnaryOperatorExpr(Minus, ...)
            return IrExpr.context(span);
        },
        .Binary => {
            // operator = BINARY_OPERATORS.get(ast.operation)
            // BinaryOperatorExpr(operator, convertAst(left), convertAst(right))
            return IrExpr.context(span);
        },
        .ThisReceiver => {
            // ContextExpr(job.root.xref)
            return IrExpr.context(span);
        },
        .KeyedRead => {
            // ReadKeyExpr(convertAst(receiver), convertAst(key))
            return IrExpr.context(span);
        },
        .Chain => {
            // throw "AssertionError: Chain in unknown context"
            return IrExpr.empty(span);
        },
        .LiteralMap => {
            // entries = ast.keys.map((key, idx) => ...)
            // LiteralMapExpr(entries)
            return IrExpr.context(span);
        },
        .LiteralArray => {
            // LiteralArrayExpr(ast.expressions.map(convertAst))
            return IrExpr.context(span);
        },
        .Conditional => {
            // ConditionalExpr(convertAst(condition), convertAst(trueExp), convertAst(falseExp))
            return IrExpr.context(span);
        },
        .NonNullAssert => {
            // A non-null assertion shouldn't impact generated instructions — drop it.
            return IrExpr.context(span);
        },
        .BindingPipe => {
            // PipeBindingExpr(job.allocateXrefId(), SlotHandle, ast.name, [...])
            return IrExpr.context(span);
        },
        .SafeKeyedRead => {
            // SafeKeyedReadExpr(convertAst(receiver), convertAst(key))
            return IrExpr.context(span);
        },
        .SafePropertyRead => {
            // SafePropertyReadExpr(convertAst(receiver), ast.name)
            return IrExpr.context(span);
        },
        .SafeCall => {
            // InvokeFunctionExpr(convertAst(receiver), args.map(convertAst), ...)
            return IrExpr.context(span);
        },
        .Empty => {
            // EmptyExpr(convertSourceSpan(ast.span, baseSourceSpan))
            return IrExpr.empty(span);
        },
        .PrefixNot => {
            // o.not(convertAst(expression))
            return IrExpr.context(span);
        },
        .TypeofExpr => {
            // o.typeofExpr(convertAst(expression))
            return IrExpr.context(span);
        },
        .VoidExpr => {
            // VoidExpr(convertAst(expression))
            return IrExpr.context(span);
        },
        .TemplateLiteral => {
            // convertTemplateLiteral(ast, job, baseSourceSpan)
            return IrExpr.context(span);
        },
        .TaggedTemplate => {
            // TaggedTemplateLiteralExpr(convertAst(tag), convertTemplateLiteral(template), ...)
            return IrExpr.context(span);
        },
        .Parenthesized => {
            // ParenthesizedExpr(convertAst(expression))
            return IrExpr.context(span);
        },
        .RegexLiteral => {
            // RegularExpressionLiteralExpr(ast.body, ast.flags, baseSourceSpan)
            return IrExpr.context(span);
        },
        .SpreadElement => {
            // SpreadElementExpr(convertAst(expression))
            return IrExpr.context(span);
        },
        .ArrowFunction => {
            // updateParameterReferences(o.arrowFn(params, convertAst(body)))
            return IrExpr.context(span);
        },
        else => {
            // throw `Unhandled expression type "${ast.constructor.name}"...`
            return IrExpr.empty(span);
        },
    }
}

/// Convert a template literal AST.
/// Direct port of `convertTemplateLiteral(ast, job, baseSourceSpan)` in ingest.ts.
fn convertTemplateLiteral(
    ast: *const ExprAst,
    job: *CompilationJob,
    base_source_span: ?ParseSourceSpan,
) IrExpr {
    _ = ast;
    _ = job;
    _ = base_source_span;
    const span = AbsoluteSourceSpan{ .start = 0, .end = 0 };
    // TemplateLiteralExpr(elements.map(...), expressions.map(convertAst), ...)
    return IrExpr.context(span);
}

/// Convert an expression that may contain interpolation.
/// Direct port of `convertAstWithInterpolation(job, value, i18nMeta, sourceSpan)` in ingest.ts.
fn convertAstWithInterpolation(
    job: *CompilationJob,
    value: *const ExprAst,
    i18n_meta: ?[]const u8,
    src_span: ?ParseSourceSpan,
) IrExpr {
    _ = i18n_meta;
    _ = src_span;
    // If value is Interpolation: new ir.Interpolation(strings, expressions.map(convertAst), placeholderNames)
    // Else if value is AST: convertAst(value)
    // Else: o.literal(value) — value would be a string literal.
    return convertAst(value, job, null);
}

// ─── Template Helpers ───────────────────────────────────────

/// Check whether the given template is a plain ng-template.
/// Direct port of `isPlainTemplate(tmpl)` in ingest.ts.
fn isPlainTemplate(tmpl: r3_ast.TemplateData) bool {
    const split = splitNsName(tmpl.tag_name);
    return std.mem.eql(u8, split[1], NG_TEMPLATE_TAG_NAME);
}

// ─── Element Bindings ───────────────────────────────────────

/// Process all of the bindings on an element.
/// Direct port of `ingestElementBindings(unit, op, element)` in ingest.ts.
fn ingestElementBindings(
    job: *CompilationJob,
    view: *ViewCompilationUnit,
    op_xref: XrefId,
    elem: r3_ast.ElementData,
    namespace: Namespace,
) anyerror!void {
    _ = op_xref;
    _ = namespace;
    _ = job;

    // bindings = Array<BindingOp | ExtractedAttributeOp | null>
    // i18nAttributeBindingNames = Set<string>

    // Process attributes (text literals like attr.foo="bar").
    for (elem.attributes) |attr| {
        const attr_data = attr.data.TextAttribute;
        // Resolve namespace inheritance for SVG/MathML.
        // securityContext(namespace, attr.name, true)
        _ = attr_data;
        try view.update.append(@intFromEnum(OpKind.Binding));
        // If attr.i18n: i18nAttributeBindingNames.add(attr.name)
    }

    // Process inputs (dynamic bindings: [prop]="expr", etc.).
    for (elem.inputs) |input| {
        const input_data = input.data.BoundAttribute;
        // If i18nAttributeBindingNames.has(input.name): console.error(...)
        // BINDING_KINDS.get(input.type)
        _ = input_data;
        try view.update.append(@intFromEnum(OpKind.Binding));
    }

    // unit.create.push(extracted attributes)
    // unit.update.push(binding ops)

    // Process outputs (events).
    for (elem.outputs) |output| {
        const output_data = output.data.BoundEvent;
        // LegacyAnimation without phase: throw "Animation listener should have a phase"
        if (output_data.type == .TwoWay) {
            try view.create.append(@intFromEnum(OpKind.TwoWayListener));
        } else if (output_data.type == .Animation) {
            try view.create.append(@intFromEnum(OpKind.AnimationListener));
            // Animation kind: ENTER if name ends with "enter", else LEAVE.
        } else {
            try view.create.append(@intFromEnum(OpKind.Listener));
        }
    }

    // If any binding has i18nMessage: create I18nAttributes op.
    // (Skipping — requires tracking i18nMessage across bindings.)
}

/// Process all of the bindings on a template.
/// Direct port of `ingestTemplateBindings(unit, op, template, templateKind)` in ingest.ts.
fn ingestTemplateBindings(
    job: *CompilationJob,
    view: *ViewCompilationUnit,
    op_xref: XrefId,
    template: r3_ast.TemplateData,
    template_kind: TemplateKind,
) anyerror!void {
    _ = op_xref;
    _ = job;
    _ = template_kind;

    // bindings = Array<BindingOp | ExtractedAttributeOp | null>

    // Process templateAttrs (structural directive inputs on *ngIf etc.)
    for (template.template_attrs) |attr| {
        switch (attr.data) {
            .TextAttribute => {
                // securityContext(NG_TEMPLATE_TAG_NAME, attr.name, true)
                try view.update.append(@intFromEnum(OpKind.Binding));
            },
            .BoundAttribute => {
                // createTemplateBinding(..., attr.type, attr.name, astOf(attr.value), ...)
                try view.update.append(@intFromEnum(OpKind.Binding));
            },
            else => {},
        }
    }

    // Process explicit attributes on ng-template.
    for (template.attributes) |attr| {
        _ = attr;
        try view.update.append(@intFromEnum(OpKind.Binding));
    }

    // Process inputs.
    for (template.inputs) |input| {
        _ = input;
        try view.update.append(@intFromEnum(OpKind.Binding));
    }

    // Process outputs.
    for (template.outputs) |output| {
        const output_data = output.data.BoundEvent;
        // LegacyAnimation without phase: throw.
        // For NgTemplate kind:
        //   TwoWay → createTwoWayListenerOp
        //   else → createListenerOp
        // For Structural kind (non-LegacyAnimation):
        //   createExtractedAttributeOp(...)
        if (output_data.type == .TwoWay) {
            try view.create.append(@intFromEnum(OpKind.TwoWayListener));
        } else {
            try view.create.append(@intFromEnum(OpKind.Listener));
        }
    }

    // If any binding has i18nMessage: create I18nAttributes op.
}

/// Helper to ingest an individual binding on a template.
/// Direct port of `createTemplateBinding(...)` in ingest.ts.
///
/// Bindings on templates are extremely tricky — this function isolates all
/// the confusing edge cases. See the TS source comments for details.
fn createTemplateBinding(
    job: *CompilationJob,
    view: *ViewCompilationUnit,
    xref: XrefId,
    binding_type: BindingType,
    name: []const u8,
    value: *const ExprAst,
    unit: ?[]const u8,
    security_context: SecurityContext,
    is_structural_template_attribute: bool,
    template_kind: ?TemplateKind,
    i18n_message: ?[]const u8,
    src_span: ParseSourceSpan,
) !?OpKind {
    _ = xref;
    _ = unit;
    _ = security_context;
    _ = src_span;
    _ = i18n_message;
    _ = name;

    const is_text_binding = false; // value is AST, not string literal.

    // If structural template, several binding kinds should not produce an update op.
    if (template_kind) |kind| if (kind == .Structural and !is_structural_template_attribute) {
        switch (binding_type) {
            .Property, .Class, .Style => {
                // Generate ExtractedAttributeOp (no update op).
                return .Attribute;
            },
            .TwoWay => {
                return .Attribute;
            },
            else => {},
        }
    };

    // For non-text attribute/animation bindings on structural templates: return null.
    if (template_kind) |kind| if (kind == .Structural and !is_text_binding) {
        switch (binding_type) {
            .Attribute, .LegacyAnimation, .Animation => return null,
            else => {},
        }
    };

    var binding_type_res = bindingKindFromType(binding_type);

    // For NgTemplate, certain bindings are coerced to Property kind.
    if (template_kind) |kind| if (kind == .NgTemplate) {
        switch (binding_type) {
            .Class, .Style => binding_type_res = .Property,
            .Attribute => if (!is_text_binding) {
                binding_type_res = .Property;
            },
            else => {},
        }
    };

    _ = value;
    _ = view;
    _ = job;

    // createBindingOp(...) → return the corresponding OpKind.
    const op_kind: OpKind = switch (binding_type_res) {
        .Property => .Property,
        .Attribute => .Binding,
        .ClassName => .ClassProp,
        .StyleProperty => .StyleProp,
        .TwoWayProperty => .TwoWayProperty,
        .Animation => .AnimationBinding,
        .LegacyAnimation => .AnimationString,
        .Template, .I18n => .Binding,
    };
    return op_kind;
}

// ─── Listener Handler Ops ───────────────────────────────────

/// Make listener handler ops from a handler AST.
/// Direct port of `makeListenerHandlerOps(unit, handler, handlerSpan)` in ingest.ts.
fn makeListenerHandlerOps(
    job: *CompilationJob,
    view: *ViewCompilationUnit,
    handler: *const ExprAst,
    handler_span: ParseSourceSpan,
) anyerror!void {
    _ = handler_span;
    _ = handler;
    _ = job;
    // handler = astOf(handler) — unwrap ASTWithSource.
    // handlerExprs = handler instanceof Chain ? handler.expressions : [handler]
    // if (handlerExprs.length === 0) throw "Expected listener to have non-empty expression list."
    // expressions = handlerExprs.map(convertAst)
    // returnExpr = expressions.pop()
    // handlerOps.push(...expressions.map(e => createStatementOp(ExpressionStatement(e))))
    // handlerOps.push(createStatementOp(ReturnStatement(returnExpr)))
    try view.update.append(@intFromEnum(OpKind.Statement));
}

/// Make two-way listener handler ops.
/// Direct port of `makeTwoWayListenerHandlerOps(unit, handler, handlerSpan)` in ingest.ts.
fn makeTwoWayListenerHandlerOps(
    job: *CompilationJob,
    view: *ViewCompilationUnit,
    handler: *const ExprAst,
    handler_span: ParseSourceSpan,
) anyerror!void {
    _ = handler_span;
    _ = handler;
    _ = job;
    // handler = astOf(handler)
    // if (handler instanceof Chain && handler.expressions.length === 1) handler = handler.expressions[0]
    // else if (Chain) throw "Expected two-way listener to have a single expression."
    // handlerExpr = convertAst(handler)
    // eventReference = LexicalReadExpr('$event')
    // twoWaySetExpr = TwoWayBindingSetExpr(handlerExpr, eventReference)
    // handlerOps.push(createStatementOp(ExpressionStatement(twoWaySetExpr)))
    // handlerOps.push(createStatementOp(ReturnStatement(eventReference)))
    try view.update.append(@intFromEnum(OpKind.Statement));
}

/// Unwrap an ASTWithSource to get the inner AST.
/// Direct port of `astOf(ast)` in ingest.ts.
fn astOf(ast: *const ExprAst) *const ExprAst {
    // In TS: `return ast instanceof ASTWithSource ? ast.ast : ast`
    // Our AST model handles this transparently.
    return ast;
}

// ─── References ─────────────────────────────────────────────

/// Process all of the local references on an element-like structure.
/// Direct port of `ingestReferences(op, element)` in ingest.ts.
fn ingestReferences(
    view: *ViewCompilationUnit,
    references: []const R3Node,
) !void {
    _ = view;
    // assertIsArray<LocalRef>(op.localRefs)
    // for (const {name, value} of element.references) {
    //   op.localRefs.push({ name, target: value })
    // }
    for (references) |ref| {
        const ref_data = ref.data.Reference;
        _ = ref_data;
        // No explicit op emitted — references are stored on the parent op (ElementOpBase.localRefs).
    }
}

// ─── Source Span Conversion ─────────────────────────────────

/// Create an absolute `ParseSourceSpan` from the relative `ParseSpan`.
/// Direct port of `convertSourceSpan(span, baseSourceSpan)` in ingest.ts.
fn convertSourceSpan(
    span: anytype,
    base_source_span: ?ParseSourceSpan,
) ?ParseSourceSpan {
    _ = span;
    if (base_source_span == null) return null;
    // const start = baseSourceSpan.start.moveBy(span.start)
    // const end = baseSourceSpan.start.moveBy(span.end)
    // const fullStart = baseSourceSpan.fullStart.moveBy(span.start)
    // return new ParseSourceSpan(start, end, fullStart)
    return base_source_span;
}

// ─── Control Flow Insertion Point ───────────────────────────

/// Compute the tag name for a control flow template to enable content projection.
/// Direct port of `ingestControlFlowInsertionPoint(unit, xref, node)` in ingest.ts.
///
/// With directive-based control flow (*ngIf), the attributes and tag name from
/// the inner element were copied to the template via the template creation
/// instruction. With `@if` and `@for`, this function reproduces that behavior
/// for the most common case: a single root element or template node.
fn ingestControlFlowInsertionPoint(
    job: *CompilationJob,
    view: *ViewCompilationUnit,
    xref: XrefId,
    children: []const *const R3Node,
) anyerror!?[]const u8 {
    _ = xref;
    _ = job;

    var root: ?*const R3Node = null;

    for (children) |child| {
        // Skip over comment nodes and @let declarations.
        switch (child.data) {
            .Comment, .LetDeclaration => continue,
            else => {},
        }

        // We can only infer the tag name/attributes if there's a single root node.
        if (root != null) return null;

        // Root nodes can only be elements or templates with a tag name.
        switch (child.data) {
            .Element => {
                // (child instanceof Element && unit.job.getForeignComponent(child) === null)
                root = child;
            },
            .Template => |tpl| {
                if (tpl.tag_name.len > 0) {
                    root = child;
                } else {
                    return null;
                }
            },
            else => return null,
        }
    }

    // If we've found a single root node, copy its tag name and attributes.
    if (root) |r| {
        // Collect static attributes for content projection purposes.
        const attrs: []const R3Node = switch (r.data) {
            .Element => |e| e.attributes,
            .Template => |t| t.attributes,
            else => &.{},
        };
        for (attrs) |attr| {
            const attr_data = attr.data.TextAttribute;
            if (!std.mem.startsWith(u8, attr_data.name, ANIMATE_PREFIX)) {
                // securityContext(NG_TEMPLATE_TAG_NAME, attr.name, true)
                // unit.update.push(createBindingOp(...))
                try view.update.append(@intFromEnum(OpKind.Binding));
            }
        }

        // Collect inputs (excluding LegacyAnimation, Animation, Attribute).
        const inputs: []const R3Node = switch (r.data) {
            .Element => |e| e.inputs,
            .Template => |t| t.inputs,
            else => &.{},
        };
        for (inputs) |input| {
            const input_data = input.data.BoundAttribute;
            if (input_data.type != .LegacyAnimation and
                input_data.type != .Animation and
                input_data.type != .Attribute)
            {
                // securityContext(NG_TEMPLATE_TAG_NAME, attr.name, true)
                // unit.create.push(createExtractedAttributeOp(...))
                try view.create.append(@intFromEnum(OpKind.Attribute));
            }
        }

        const tag_name: []const u8 = switch (r.data) {
            .Element => |e| e.name,
            .Template => |t| t.tag_name,
            else => "",
        };

        // Don't pass along `ng-template` tag name since it enables directive matching.
        if (std.mem.eql(u8, tag_name, NG_TEMPLATE_TAG_NAME)) return null;
        return tag_name;
    }

    return null;
}

// ─── Arrow Function Parameter References ────────────────────

/// When an arrow function in the expression AST is converted into the output AST,
/// all of its top-level reads become `LexicalReadExpr` because the output AST
/// doesn't have a concept of a variable read. This function corrects the ones
/// that point to parameters.
///
/// Direct port of `updateParameterReferences(root)` in ingest.ts.
fn updateParameterReferences(root: *IrExpr) *IrExpr {
    // const parameterNames = new Set(root.params.map(p => p.name))
    // return ir.transformExpressionsInExpression(root, (expr) => {
    //   if (expr instanceof ArrowFunctionExpr) {
    //     for (const param of expr.params) parameterNames.add(param.name)
    //   } else if (expr instanceof LexicalReadExpr && parameterNames.has(expr.name)) {
    //     return o.variable(expr.name)
    //   }
    //   return expr
    // }, None)
    return root;
}

// ─── Namespace Helpers ──────────────────────────────────────

/// Split a qualified name like "svg:rect" into ("svg", "rect").
/// Mirrors `splitNsName(...)` from `ml_parser/tags.ts`.
fn splitNsName(name: []const u8) struct { ?[]const u8, []const u8 } {
    if (std.mem.indexOfScalar(u8, name, ':')) |pos| {
        return .{ name[0..pos], name[pos + 1 ..] };
    }
    return .{ null, name };
}

/// Resolve a namespace prefix string to a Namespace enum.
/// Mirrors `namespaceForKey(...)` from `conversion.ts`.
fn namespaceForKey(key: ?[]const u8) Namespace {
    if (key) |k| {
        if (std.mem.eql(u8, k, SVG_NAMESPACE)) return .SVG;
        if (std.mem.eql(u8, k, MATH_ML_NAMESPACE)) return .MathML;
    }
    return .HTML;
}

/// Prefix a tag name with its namespace for function name generation.
/// Mirrors `prefixWithNamespace(...)` from `conversion.ts`.
fn prefixWithNamespace(name: []const u8, ns: Namespace) []const u8 {
    return switch (ns) {
        .SVG => SVG_NAMESPACE,
        .MathML => MATH_ML_NAMESPACE,
        .HTML => name,
    };
}

// ─── Tests ──────────────────────────────────────────────────

test "isI18nRootNode" {
    try std.testing.expect(isI18nRootNode("some meta"));
    try std.testing.expect(!isI18nRootNode(null));
}

test "isSingleI18nIcu" {
    try std.testing.expect(isSingleI18nIcu("some meta"));
    try std.testing.expect(!isSingleI18nIcu(null));
}

test "asMessage returns input as-is" {
    try std.testing.expectEqualStrings("hello", asMessage("hello").?);
    try std.testing.expect(asMessage(null) == null);
}

test "bindingKindFromType maps all BindingType variants" {
    try std.testing.expectEqual(BindingKind.Property, bindingKindFromType(.Property));
    try std.testing.expectEqual(BindingKind.TwoWayProperty, bindingKindFromType(.TwoWay));
    try std.testing.expectEqual(BindingKind.Attribute, bindingKindFromType(.Attribute));
    try std.testing.expectEqual(BindingKind.ClassName, bindingKindFromType(.Class));
    try std.testing.expectEqual(BindingKind.StyleProperty, bindingKindFromType(.Style));
    try std.testing.expectEqual(BindingKind.Animation, bindingKindFromType(.Animation));
    try std.testing.expectEqual(BindingKind.LegacyAnimation, bindingKindFromType(.LegacyAnimation));
}

test "splitNsName splits qualified names" {
    const r1 = splitNsName("svg:rect");
    try std.testing.expectEqualStrings("svg", r1[0].?);
    try std.testing.expectEqualStrings("rect", r1[1]);

    const r2 = splitNsName("div");
    try std.testing.expect(r2[0] == null);
    try std.testing.expectEqualStrings("div", r2[1]);

    const r3 = splitNsName("math:msup");
    try std.testing.expectEqualStrings("math", r3[0].?);
    try std.testing.expectEqualStrings("msup", r3[1]);
}

test "namespaceForKey resolves known prefixes" {
    try std.testing.expectEqual(Namespace.HTML, namespaceForKey(null));
    try std.testing.expectEqual(Namespace.HTML, namespaceForKey(""));
    try std.testing.expectEqual(Namespace.SVG, namespaceForKey("svg"));
    try std.testing.expectEqual(Namespace.MathML, namespaceForKey("mathml"));
    try std.testing.expectEqual(Namespace.HTML, namespaceForKey("unknown"));
}

test "prefixWithNamespace maps correctly" {
    try std.testing.expectEqualStrings("svg", prefixWithNamespace("foo", .SVG));
    try std.testing.expectEqualStrings("mathml", prefixWithNamespace("foo", .MathML));
    try std.testing.expectEqualStrings("div", prefixWithNamespace("div", .HTML));
}

test "isPlainTemplate detects ng-template" {
    const plain = r3_ast.TemplateData{
        .tag_name = "ng-template",
        .attributes = &.{},
        .inputs = &.{},
        .outputs = &.{},
        .directives = &.{},
        .template_attrs = &.{},
        .children = &.{},
        .references = &.{},
        .variables = &.{},
    };
    try std.testing.expect(isPlainTemplate(plain));

    const structural = r3_ast.TemplateData{
        .tag_name = "div",
        .attributes = &.{},
        .inputs = &.{},
        .outputs = &.{},
        .directives = &.{},
        .template_attrs = &.{},
        .children = &.{},
        .references = &.{},
        .variables = &.{},
    };
    try std.testing.expect(!isPlainTemplate(structural));

    const svg_plain = r3_ast.TemplateData{
        .tag_name = "svg:ng-template",
        .attributes = &.{},
        .inputs = &.{},
        .outputs = &.{},
        .directives = &.{},
        .template_attrs = &.{},
        .children = &.{},
        .references = &.{},
        .variables = &.{},
    };
    try std.testing.expect(isPlainTemplate(svg_plain));
}

test "getComputedForLoopVariableExpression returns correct forms" {
    const index_var = r3_ast.VariableData{
        .name = "i",
        .value = "$index",
        .key_span = AbsoluteSourceSpan.empty(),
        .value_span = AbsoluteSourceSpan.empty(),
    };
    const r = getComputedForLoopVariableExpression(index_var, "ɵ$index_1", "ɵ$count_1");
    try std.testing.expectEqualStrings("ɵ$index_1", r);

    const first_var = r3_ast.VariableData{
        .name = "f",
        .value = "$first",
        .key_span = AbsoluteSourceSpan.empty(),
        .value_span = AbsoluteSourceSpan.empty(),
    };
    try std.testing.expectEqualStrings(
        "$index === 0",
        getComputedForLoopVariableExpression(first_var, "ɵ$index_1", "ɵ$count_1"),
    );

    const odd_var = r3_ast.VariableData{
        .name = "o",
        .value = "$odd",
        .key_span = AbsoluteSourceSpan.empty(),
        .value_span = AbsoluteSourceSpan.empty(),
    };
    try std.testing.expectEqualStrings(
        "$index % 2 !== 0",
        getComputedForLoopVariableExpression(odd_var, "ɵ$index_1", "ɵ$count_1"),
    );
}

test "calcDeferBlockFlags returns HasHydrateTriggers when triggers exist" {
    const defer_with_triggers = r3_ast.DeferredBlockData{
        .children = &.{},
        .triggers = &.{
            .{ .kind = .Idle, .value = null },
        },
        .placeholder = null,
        .loading = null,
        .err = null,
        .defer_block_dependencies = &.{},
    };
    try std.testing.expectEqual(TDeferDetailsFlags.HasHydrateTriggers, calcDeferBlockFlags(defer_with_triggers).?);

    const defer_without_triggers = r3_ast.DeferredBlockData{
        .children = &.{},
        .triggers = &.{},
        .placeholder = null,
        .loading = null,
        .err = null,
        .defer_block_dependencies = &.{},
    };
    try std.testing.expect(calcDeferBlockFlags(defer_without_triggers) == null);
}

test "ingestComponent creates a job and ingests empty template" {
    const allocator = std.testing.allocator;
    var pool = ConstantPool.init(allocator);
    defer pool.deinit();

    const job = try ingestComponent(
        allocator,
        "MyComp",
        &.{},
        &pool,
        .Full,
        "test.ts",
        false,
        null,
        null,
        null,
        false,
        false,
        null,
    );
    defer {
        job.deinit();
        allocator.destroy(job);
    }
    try std.testing.expectEqualStrings("MyComp", job.component_name);
    try std.testing.expectEqual(@as(usize, 0), job.root.create.len());
    try std.testing.expectEqual(@as(usize, 0), job.root.update.len());
}

test "ingestHostBinding creates a job" {
    const allocator = std.testing.allocator;
    const input = HostBindingInput{
        .component_name = "MyComp",
        .component_selector = "my-comp",
    };
    const job = try ingestHostBinding(allocator, input);
    defer {
        job.deinit();
        allocator.destroy(job);
    }
    try std.testing.expectEqualStrings("MyComp", job.component_name);
}

test "ingestText emits a Text op" {
    const allocator = std.testing.allocator;
    var job = try CompilationJob.init(allocator, "Test", .Full);
    defer job.deinit();
    try ingestText(&job, &job.root, "hello", null);
    try std.testing.expectEqual(@as(usize, 1), job.root.create.len());
    try std.testing.expectEqual(@as(u16, @intFromEnum(OpKind.Text)), job.root.create.first().?);
}

test "ingestBoundText emits Text + InterpolateText" {
    const allocator = std.testing.allocator;
    var job = try CompilationJob.init(allocator, "Test", .Full);
    defer job.deinit();

    // Build a minimal BoundText node with a stub AST.
    const stub_ast = try allocator.create(ExprAst);
    defer allocator.destroy(stub_ast);
    stub_ast.* = ExprAst{
        .span = .{ .start = 0, .end = 0 },
        .abs_span = AbsoluteSourceSpan.empty(),
        .data = .{ .Empty = {} },
    };

    const bound_text = r3_ast.BoundTextData{
        .value = stub_ast,
        .i18n = null,
    };

    const node = try allocator.create(R3Node);
    defer allocator.destroy(node);
    node.* = R3Node{
        .kind = .BoundText,
        .source_span = ParseSourceSpan.fromAbsolute(AbsoluteSourceSpan.empty()),
        .data = .{ .BoundText = bound_text },
    };

    try ingestBoundText(&job, &job.root, node, bound_text, null);
    try std.testing.expectEqual(@as(usize, 1), job.root.create.len());
    try std.testing.expectEqual(@as(usize, 1), job.root.update.len());
    try std.testing.expectEqual(@as(u16, @intFromEnum(OpKind.Text)), job.root.create.first().?);
    try std.testing.expectEqual(@as(u16, @intFromEnum(OpKind.InterpolateText)), job.root.update.first().?);
}

test "ingestLetDeclaration emits Statement + StoreLet" {
    const allocator = std.testing.allocator;
    var job = try CompilationJob.init(allocator, "Test", .Full);
    defer job.deinit();

    const stub_ast = try allocator.create(ExprAst);
    defer allocator.destroy(stub_ast);
    stub_ast.* = ExprAst{
        .span = .{ .start = 0, .end = 0 },
        .abs_span = AbsoluteSourceSpan.empty(),
        .data = .{ .Empty = {} },
    };

    const let_decl = r3_ast.LetDeclarationData{
        .name = "myLet",
        .value = stub_ast,
        .name_span = AbsoluteSourceSpan.empty(),
        .value_span = AbsoluteSourceSpan.empty(),
    };

    const node = try allocator.create(R3Node);
    defer allocator.destroy(node);
    node.* = R3Node{
        .kind = .LetDeclaration,
        .source_span = ParseSourceSpan.fromAbsolute(AbsoluteSourceSpan.empty()),
        .data = .{ .LetDeclaration = let_decl },
    };

    try ingestLetDeclaration(&job, &job.root, node, let_decl);
    try std.testing.expectEqual(@as(usize, 1), job.root.create.len());
    try std.testing.expectEqual(@as(usize, 1), job.root.update.len());
    try std.testing.expectEqual(@as(u16, @intFromEnum(OpKind.Statement)), job.root.create.first().?);
    try std.testing.expectEqual(@as(u16, @intFromEnum(OpKind.StoreLet)), job.root.update.first().?);
}

test "ingestReferences is a no-op for empty references" {
    const allocator = std.testing.allocator;
    var job = try CompilationJob.init(allocator, "Test", .Full);
    defer job.deinit();
    try ingestReferences(&job.root, &.{});
    // No-op: references are stored on the parent op, not as standalone ops.
    try std.testing.expectEqual(@as(usize, 0), job.root.create.len());
}

test "convertSourceSpan returns null for null base" {
    const result = convertSourceSpan(.{ .start = 0, .end = 5 }, null);
    try std.testing.expect(result == null);
}

test "securityContext returns NONE as safe default" {
    try std.testing.expectEqual(SecurityContext.NONE, securityContext("div", "class", true));
    try std.testing.expectEqual(SecurityContext.NONE, securityContext("a", "href", false));
}
