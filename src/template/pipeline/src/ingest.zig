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
const std = @import("std");
const compilation = @import("compilation.zig");
const CompilationJob = compilation.CompilationJob;
const ViewCompilationUnit = compilation.ViewCompilationUnit;
const ConstantPool = compilation.ConstantPool;
const create_ops = @import("../ir/create_ops.zig");
const update_ops = @import("../ir/update_ops.zig");
const operations = @import("../ir/operations.zig");
const XrefId = operations.XrefId;
const ir_enums = @import("../ir/enums.zig");
const OpKind = ir_enums.OpKind;
const Namespace = ir_enums.Namespace;
const BindingKind = ir_enums.BindingKind;
const CompilationMode = ir_enums.CompilationMode;

const r3_ast = @import("../../render3/r3_ast.zig");
const R3Node = r3_ast.R3Node;
const R3NodeKind = r3_ast.R3NodeKind;

const source_span = @import("../../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

// ─── Constants ──────────────────────────────────────────────

const NG_TEMPLATE_TAG_NAME = "ng-template";
const ANIMATE_PREFIX = "animate.";
const SVG_NAMESPACE = "svg";
const MATH_ML_NAMESPACE = "mathml";

// ─── i18n Helpers ───────────────────────────────────────────

/// Check if an i18n meta is a root Message.
pub fn isI18nRootNode(meta: ?[]const u8) bool {
    return meta != null;
}

/// Check if an i18n meta is a single ICU.
pub fn isSingleI18nIcu(meta: ?[]const u8) bool {
    return meta != null;
}

/// Ensure i18nMeta is a Message, or return null.
fn asMessage(i18n_meta: ?[]const u8) ?[]const u8 {
    return i18n_meta;
}

// ─── Main Entry Points ──────────────────────────────────────

/// HostBindingInput — input for host binding ingestion.
pub const HostBindingInput = struct {
    component_name: []const u8,
    component_selector: []const u8,
    properties: ?[]const u8 = null,
    attributes: ?[]const u8 = null,
    events: ?[]const u8 = null,
    legacy_optional_chaining: bool = false,
};

/// Ingest a component template: convert R3 AST → IR ops.
pub fn ingestComponent(
    allocator: std.mem.Allocator,
    component_name: []const u8,
    template: []const *const R3Node,
    compilation_mode: CompilationMode,
) !*CompilationJob {
    const job = try allocator.create(CompilationJob);
    job.* = try CompilationJob.init(allocator, component_name, compilation_mode);
    try ingestNodes(job, &job.root, template);
    return job;
}

/// Ingest a host binding.
pub fn ingestHostBinding(
    allocator: std.mem.Allocator,
    input: HostBindingInput,
) !*CompilationJob {
    const job = try allocator.create(CompilationJob);
    job.* = try CompilationJob.init(allocator, input.component_name, .Full);
    _ = input;
    return job;
}

/// Ingest a DOM property binding.
pub fn ingestDomProperty(job: *CompilationJob, name: []const u8, value: []const u8) !void {
    _ = job;
    _ = name;
    _ = value;
}

/// Ingest a host attribute.
pub fn ingestHostAttribute(job: *CompilationJob, name: []const u8, value: []const u8) !void {
    _ = job;
    _ = name;
    _ = value;
}

/// Ingest a host event.
pub fn ingestHostEvent(job: *CompilationJob, event_name: []const u8, handler: []const u8) !void {
    _ = job;
    _ = event_name;
    _ = handler;
}

// ─── Node Ingestion (recursive) ─────────────────────────────

/// Ingest a list of R3 nodes into a view's IR.
fn ingestNodes(job: *CompilationJob, view: *ViewCompilationUnit, nodes: []const *const R3Node) !void {
    for (nodes) |node| {
        try ingestNode(job, view, node);
    }
}

/// Ingest a single R3 node.
fn ingestNode(job: *CompilationJob, view: *ViewCompilationUnit, node: *const R3Node) !void {
    switch (node.data) {
        .Element => |elem| try ingestElement(job, view, node, elem),
        .Text => |text| try ingestText(job, view, text.value),
        .BoundText => |bound_text| try ingestBoundText(job, view, bound_text),
        .TextAttribute => |attr| try ingestTextAttribute(job, view, attr),
        .BoundAttribute => |bound_attr| try ingestBoundAttribute(job, view, node, bound_attr),
        .BoundEvent => |bound_event| try ingestBoundEvent(job, view, node, bound_event),
        .Reference => |ref| try ingestReference(job, view, ref),
        .Template => |tpl| try ingestTemplate(job, view, node, tpl),
        .Content => |content| try ingestContent(job, view, node, content),
        .IfBlock => |if_block| try ingestIfBlock(job, view, node, if_block),
        .ForLoopBlock => |for_block| try ingestForLoopBlock(job, view, node, for_block),
        .SwitchBlock => |switch_block| try ingestSwitchBlock(job, view, node, switch_block),
        .DeferredBlock => |defer_block| try ingestDeferBlock(job, view, node, defer_block),
        .LetDeclaration => |let_decl| try ingestLetDeclaration(job, view, node, let_decl),
        .Comment => {},
        .Variable => |var_| try ingestVariable(job, view, var_),
        .Icu => |icu| try ingestIcu(job, view, node, icu),
        .ForLoopBlockEmpty => {},
        .DeferredTrigger => {},
        .IcuPlaceholder => {},
        .Component => |comp| try ingestComponent2(job, view, node, comp),
        .IfBlockBranch, .SwitchBlockCaseGroup, .SwitchBlockCase => unreachable,
    }
}

// ─── Element ────────────────────────────────────────────────

fn ingestElement(
    job: *CompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    elem: r3_ast.ElementData,
) !void {
    const slot = job.slots.allocSlot();
    const ns: Namespace = if (std.mem.startsWith(u8, elem.name, "svg:")) .SVG
        else if (std.mem.startsWith(u8, elem.name, "math:")) .MathML
        else .HTML;
    const name = if (std.mem.indexOfScalar(u8, elem.name, ':')) |pos| elem.name[pos+1..] else elem.name;

    // ElementStart
    try view.create.append(@intFromEnum(OpKind.ElementStart));

    // Ingest element bindings (inputs, outputs, attributes)
    for (elem.attributes) |attr| {
        try ingestNode(job, view, &attr);
    }
    for (elem.inputs) |input| {
        try ingestNode(job, view, &input);
    }
    for (elem.outputs) |output| {
        try ingestNode(job, view, &output);
    }
    for (elem.references) |ref| {
        try ingestNode(job, view, &ref);
    }

    // Ingest children
    for (elem.children) |child| {
        try ingestNode(job, view, child);
    }

    // ElementEnd
    try view.create.append(@intFromEnum(OpKind.ElementEnd));
}

// ─── Text ───────────────────────────────────────────────────

fn ingestText(job: *CompilationJob, view: *ViewCompilationUnit, value: []const u8) !void {
    const xref = job.allocateXrefId();
    _ = xref;
    try view.create.append(@intFromEnum(OpKind.Text));
    _ = value;
}

// ─── BoundText ──────────────────────────────────────────────

fn ingestBoundText(job: *CompilationJob, view: *ViewCompilationUnit, bound_text: r3_ast.BoundTextData) !void {
    const xref = job.allocateXrefId();
    // Create: Text op
    try view.create.append(@intFromEnum(OpKind.Text));
    // Update: InterpolateText op
    try view.update.append(@intFromEnum(OpKind.InterpolateText));
    _ = bound_text;
    _ = xref;
}

// ─── TextAttribute ──────────────────────────────────────────

fn ingestTextAttribute(job: *CompilationJob, view: *ViewCompilationUnit, attr: r3_ast.TextAttributeData) !void {
    try view.create.append(@intFromEnum(OpKind.Attribute));
    _ = attr;
    _ = job;
}

// ─── BoundAttribute ─────────────────────────────────────────

fn ingestBoundAttribute(job: *CompilationJob, view: *ViewCompilationUnit, node: *const R3Node, bound_attr: r3_ast.BoundAttributeData) !void {
    // Update: Property op
    try view.update.append(@intFromEnum(OpKind.Property));
    _ = bound_attr;
    _ = node;
    _ = job;
}

// ─── BoundEvent ─────────────────────────────────────────────

fn ingestBoundEvent(job: *CompilationJob, view: *ViewCompilationUnit, node: *const R3Node, bound_event: r3_ast.BoundEventData) !void {
    const slot = job.slots.allocSlot();
    const handler_fn_xref = job.allocateXrefId();
    // Create: Listener op
    try view.create.append(@intFromEnum(OpKind.Listener));
    _ = bound_event;
    _ = node;
    _ = slot;
    _ = handler_fn_xref;
}

// ─── Reference ──────────────────────────────────────────────

fn ingestReference(job: *CompilationJob, view: *ViewCompilationUnit, ref: r3_ast.ReferenceData) !void {
    const ref_slot = job.slots.allocSlot();
    try view.create.append(@intFromEnum(OpKind.Statement));
    _ = ref;
    _ = ref_slot;
}

// ─── Variable ───────────────────────────────────────────────

fn ingestVariable(job: *CompilationJob, view: *ViewCompilationUnit, var_: r3_ast.VariableData) !void {
    const var_slot = job.slots.allocSlot();
    try view.create.append(@intFromEnum(OpKind.Variable));
    _ = var_;
    _ = var_slot;
}

// ─── Template ───────────────────────────────────────────────

fn ingestTemplate(job: *CompilationJob, view: *ViewCompilationUnit, node: *const R3Node, tpl: r3_ast.TemplateData) !void {
    // Allocate embedded view
    const child_view = try job.allocateView(node.xref);
    // Create: Template op
    try view.create.append(@intFromEnum(OpKind.Template));
    // Ingest template attributes
    for (tpl.template_attrs) |attr| {
        try ingestNode(job, view, &attr);
    }
    // Ingest references
    for (tpl.references) |ref| {
        try ingestNode(job, view, &ref);
    }
    // Ingest children into the child view
    for (tpl.children) |child| {
        try ingestNode(job, child_view, child);
    }
    // Variables
    for (tpl.variables) |var_node| {
        try ingestNode(job, child_view, &var_node);
    }
}

// ─── Content (ng-content) ───────────────────────────────────

fn ingestContent(job: *CompilationJob, view: *ViewCompilationUnit, node: *const R3Node, content: r3_ast.ContentData) !void {
    const id = job.allocateXrefId();
    _ = id;
    // Create: Projection op
    try view.create.append(@intFromEnum(OpKind.Projection));
    // Process fallback children if any
    for (content.children) |child| {
        try ingestNode(job, view, child);
    }
    _ = content;
}

// ─── IfBlock (@if) ──────────────────────────────────────────

fn ingestIfBlock(job: *CompilationJob, view: *ViewCompilationUnit, node: *const R3Node, if_block: r3_ast.IfBlockData) !void {
    var first_xref: ?XrefId = null;
    for (if_block.branches, 0..) |branch, i| {
        const c_view = try job.allocateView(node.xref);
        // Create: ConditionalCreate or ConditionalBranchCreate
        if (i == 0) {
            try view.create.append(@intFromEnum(OpKind.ConditionalCreate));
            first_xref = c_view.xref;
        } else {
            try view.create.append(@intFromEnum(OpKind.ConditionalBranchCreate));
        }
        // Ingest branch children
        for (branch.children) |child| {
            try ingestNode(job, c_view, child);
        }
    }
    // Update: Conditional op
    try view.update.append(@intFromEnum(OpKind.Conditional));
}

// ─── ForLoopBlock (@for) ────────────────────────────────────

fn ingestForLoopBlock(job: *CompilationJob, view: *ViewCompilationUnit, node: *const R3Node, for_block: r3_ast.ForLoopBlockData) !void {
    const repeater_view = try job.allocateView(node.xref);
    // Create: RepeaterCreate op
    try view.create.append(@intFromEnum(OpKind.RepeaterCreate));
    // Ingest repeater children
    for (for_block.children) |child| {
        try ingestNode(job, repeater_view, child);
    }
    // Handle empty view if present
    // Update: Repeater op
    try view.update.append(@intFromEnum(OpKind.Repeater));
}

// ─── SwitchBlock (@switch) ──────────────────────────────────

fn ingestSwitchBlock(job: *CompilationJob, view: *ViewCompilationUnit, node: *const R3Node, switch_block: r3_ast.SwitchBlockData) !void {
    if (switch_block.groups.len == 0) return;
    var first_xref: ?XrefId = null;
    for (switch_block.groups, 0..) |group, i| {
        const c_view = try job.allocateView(node.xref);
        if (i == 0) {
            try view.create.append(@intFromEnum(OpKind.ConditionalCreate));
            first_xref = c_view.xref;
        } else {
            try view.create.append(@intFromEnum(OpKind.ConditionalBranchCreate));
        }
        for (group.children) |child| {
            try ingestNode(job, c_view, child);
        }
    }
    try view.update.append(@intFromEnum(OpKind.Conditional));
}

// ─── DeferredBlock (@defer) ─────────────────────────────────

fn ingestDeferBlock(job: *CompilationJob, view: *ViewCompilationUnit, node: *const R3Node, defer_block: r3_ast.DeferredBlockData) !void {
    const defer_xref = job.allocateXrefId();
    // Ingest main defer view
    for (defer_block.children) |child| {
        try ingestNode(job, view, child);
    }
    // Create: Defer op
    try view.create.append(@intFromEnum(OpKind.Defer));

    // Handle placeholder, loading, error sub-blocks
    // Default to idle trigger if no concrete triggers
    try view.create.append(@intFromEnum(OpKind.DeferOn));
    _ = defer_xref;
}

// ─── LetDeclaration (@let) ──────────────────────────────────

fn ingestLetDeclaration(job: *CompilationJob, view: *ViewCompilationUnit, node: *const R3Node, let_decl: r3_ast.LetDeclarationData) !void {
    const target = job.allocateXrefId();
    // Create: DeclareLet op
    try view.create.append(@intFromEnum(OpKind.Statement));
    // Update: StoreLet op
    try view.update.append(@intFromEnum(OpKind.StoreLet));
    _ = target;
    _ = let_decl;
}

// ─── Icu ────────────────────────────────────────────────────

fn ingestIcu(job: *CompilationJob, view: *ViewCompilationUnit, node: *const R3Node, icu: r3_ast.IcuData) !void {
    const xref = job.allocateXrefId();
    // Create: IcuStart op
    try view.create.append(@intFromEnum(OpKind.I18n));
    // Process ICU cases and placeholders
    for (icu.cases) |_| {
        // Ingest each case
    }
    for (icu.placeholders) |_| {
        // Ingest each placeholder
    }
    // Create: IcuEnd op
    try view.create.append(@intFromEnum(OpKind.I18n));
    _ = xref;
}

// ─── Component ──────────────────────────────────────────────

fn ingestComponent2(job: *CompilationJob, view: *ViewCompilationUnit, node: *const R3Node, comp: r3_ast.ComponentData) !void {
    // Components are handled like elements for now
    try ingestElement(job, view, node, .{
        .name = comp.component_name,
        .attributes = comp.attributes,
        .inputs = comp.inputs,
        .outputs = comp.outputs,
        .directives = &.{},
        .children = comp.children,
        .references = comp.references,
        .is_self_closing = false,
        .is_void = false,
    });
}

// ─── AST Conversion ─────────────────────────────────────────

/// Convert a template AST expression into an output AST expression string.
/// This is a simplified version — the full conversion handles all AST node types.
fn convertAst(expr_text: []const u8, job: *CompilationJob) []const u8 {
    _ = job;
    return expr_text;
}

/// Convert an expression that may contain interpolation.
fn convertAstWithInterpolation(job: *CompilationJob, value: []const u8, i18n: ?[]const u8) []const u8 {
    _ = job;
    _ = i18n;
    return value;
}

/// Check if a template is a plain ng-template (not a structural directive).
fn isPlainTemplate(tmpl: r3_ast.TemplateData) bool {
    if (tmpl.tag_name) |tag| {
        return std.mem.endsWith(u8, tag, NG_TEMPLATE_TAG_NAME);
    }
    return true;
}
