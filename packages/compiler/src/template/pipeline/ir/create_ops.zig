/// IR Create Ops — All creation-phase operation types for the Angular IR
///
/// Port of: compiler/src/template/pipeline/ir/src/ops/create.ts (2095 LoC)
///
/// DOD patterns:
///   - All ops are plain structs (no class hierarchy)
///   - Tagged union via OpKind for dispatch
///   - Arena-allocated via CompilationJob
///   - Zero-copy strings ([]const u8 slices)
///   - Contiguous OpList for cache-friendly iteration
const std = @import("std");
const ir_enums = @import("enums.zig");
const OpKind = ir_enums.OpKind;
const Namespace = ir_enums.Namespace;
const BindingKind = ir_enums.BindingKind;
const DeferTriggerKind = ir_enums.DeferTriggerKind;

const source_span = @import("../../../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

// ─── Base Types ─────────────────────────────────────────────

/// XrefId — cross-reference ID for linking ops across views.
pub const XrefId = u32;

/// SlotHandle — handle to an allocated slot in the view's data array.
pub const SlotHandle = struct { slot: ?u32 = null };

/// ConstIndex — index into the constant pool (branded number).
pub const ConstIndex = u32;

/// ParseSourceSpan — source location in the original template.
pub const ParseSourceSpan = AbsoluteSourceSpan;

/// LocalRef — a local reference declared on an element.
pub const LocalRef = struct {
    name: []const u8,
    slot: ?u32 = null,
    initializers: []const u8 = "",
};

/// ElementSourceLocation — source location for an element.
pub const ElementSourceLocation = struct {
    name: []const u8,
    source_span: ?ParseSourceSpan = null,
};

// ─── Element/Container Base ──────────────────────────────────

/// ElementOrContainerOpBase — base for element and container ops.
/// DOD: flat struct, no inheritance.
pub const ElementOrContainerOpBase = struct {
    kind: OpKind,
    xref: XrefId,
    slot: SlotHandle = .{},
    source_span: ?ParseSourceSpan = null,
    tag: ?[]const u8 = null,
    namespace: Namespace = .HTML,
    attrs_xref: ?u32 = null,
    local_refs: []const LocalRef = &.{},
    non_bBindable: bool = false,
};

/// ElementStartOp — begins rendering of an element.
pub const ElementStartOp = struct {
    base: ElementOrContainerOpBase,
    // kind = .ElementStart
};

/// ElementOp — renders an element with no children (self-closing).
pub const ElementOp = struct {
    base: ElementOrContainerOpBase,
    // kind = .Element
};

/// ElementEndOp — ends rendering of an element.
pub const ElementEndOp = struct {
    kind: OpKind = .ElementEnd,
    xref: XrefId,
    source_span: ?ParseSourceSpan = null,
};

/// ContainerStartOp — begins an ng-container.
pub const ContainerStartOp = struct {
    base: ElementOrContainerOpBase,
    // kind = .ContainerStart
};

/// ContainerOp — ng-container with no children.
pub const ContainerOp = struct {
    base: ElementOrContainerOpBase,
    // kind = .Container
};

/// ContainerEndOp — ends an ng-container.
pub const ContainerEndOp = struct {
    kind: OpKind = .ContainerEnd,
    xref: XrefId,
    source_span: ?ParseSourceSpan = null,
};

// ─── Template / Conditional / Repeater ─────────────────────

/// TemplateOp — declares an embedded view (ng-template).
pub const TemplateOp = struct {
    base: ElementOrContainerOpBase,
    // kind = .Template
    template_kind: u8 = 0, // TemplateKind
    is_inline: bool = false,
};

/// ConditionalCreateOp — creates a conditional (@if) block.
pub const ConditionalCreateOp = struct {
    base: ElementOrContainerOpBase,
    // kind = .ConditionalCreate
    is_branch: bool = false,
};

/// ConditionalBranchCreateOp — creates a branch of a conditional.
pub const ConditionalBranchCreateOp = struct {
    base: ElementOrContainerOpBase,
    // kind = .ConditionalBranchCreate
};

/// RepeaterCreateOp — creates a repeater (@for) block.
pub const RepeaterCreateOp = struct {
    base: ElementOrContainerOpBase,
    // kind = .RepeaterCreate
    track: ?[]const u8 = null,
    track_by_fn: ?[]const u8 = null,
    collection: ?[]const u8 = null,
    context_vars: []const RepeaterVarNames = &.{},
};

/// RepeaterVarNames — variable names for @for context.
pub const RepeaterVarNames = struct {
    name: []const u8,
    slot: ?u32 = null,
};

// ─── Foreign Component ──────────────────────────────────────

/// ForeignComponentOp — renders a foreign (non-Angular) component.
pub const ForeignComponentOp = struct {
    kind: OpKind = .ForeignComponent,
    xref: XrefId,
    slot: SlotHandle = .{},
    source_span: ?ParseSourceSpan = null,
};

// ─── Content / Projection ───────────────────────────────────

/// ContentOp — renders an ng-content slot.
pub const ContentOp = struct {
    kind: OpKind = .Content,
    xref: XrefId,
    slot: u32 = 0,
    selector: ?[]const u8 = null,
    attrs_xref: ?u32 = null,
    fallback_view: ?u32 = null,
    source_span: ParseSourceSpan,
};

// ─── Bindings ───────────────────────────────────────────────

/// DisableBindingsOp — disables bindings for ngNonBindable descendants.
pub const DisableBindingsOp = struct {
    kind: OpKind = .DisableBindings,
    xref: XrefId,
};

/// EnableBindingsOp — re-enables bindings after ngNonBindable.
pub const EnableBindingsOp = struct {
    kind: OpKind = .EnableBindings,
    xref: XrefId,
};

// ─── Text ───────────────────────────────────────────────────

/// TextOp — renders a text node.
pub const TextOp = struct {
    kind: OpKind = .Text,
    xref: XrefId,
    slot: SlotHandle = .{},
    source_span: ?ParseSourceSpan = null,
    const_index: ?ConstIndex = null,
    i18n: ?u32 = null,
};

// ─── Animation ──────────────────────────────────────────────

/// AnimationStringOp — animation string binding.
pub const AnimationStringOp = struct {
    kind: OpKind = .AnimationString,
    xref: XrefId,
    name: []const u8,
    phase: []const u8 = "",
    value: ?[]const u8 = null,
    slot: SlotHandle = .{},
    source_span: ?ParseSourceSpan = null,
};

/// AnimationOp — animation trigger.
pub const AnimationOp = struct {
    kind: OpKind = .Animation,
    xref: XrefId,
    slot: SlotHandle = .{},
    source_span: ?ParseSourceSpan = null,
    name: []const u8,
    animation_kind: u8 = 0, // AnimationKind
    expr: ?[]const u8 = null,
    handler_fn_name: ?[]const u8 = null,
};

/// AnimationListenerOp — animation event listener.
pub const AnimationListenerOp = struct {
    kind: OpKind = .AnimationListener,
    xref: XrefId,
    name: []const u8,
    phase: []const u8 = "",
    handler_fn_xref: u32 = 0,
    target_slot: SlotHandle = .{},
    host_listener: bool = false,
    handler_fn_name: ?[]const u8 = null,
    source_span: ?ParseSourceSpan = null,
};

// ─── Listener ───────────────────────────────────────────────

/// ListenerOp — event listener for an element.
pub const ListenerOp = struct {
    kind: OpKind = .Listener,
    xref: XrefId,
    name: []const u8,
    handler_fn_xref: u32 = 0,
    target_slot: SlotHandle = .{},
    host_listener: bool = false,
    handler_fn_name: ?[]const u8 = null,
    consumes_dollar_event: bool = false,
    is_legacy_animation_listener: bool = false,
    legacy_animation_phase: ?[]const u8 = null,
    source_span: ?ParseSourceSpan = null,
};

/// TwoWayListenerOp — two-way binding listener ([(ngModel)]).
pub const TwoWayListenerOp = struct {
    kind: OpKind = .TwoWayListener,
    xref: XrefId,
    name: []const u8,
    handler_fn_xref: u32 = 0,
    target_slot: SlotHandle = .{},
    handler_fn_name: ?[]const u8 = null,
    source_span: ?ParseSourceSpan = null,
};

// ─── Pipe ───────────────────────────────────────────────────

/// PipeOp — instantiates a pipe.
pub const PipeOp = struct {
    kind: OpKind = .Pipe,
    xref: XrefId,
    slot: SlotHandle = .{},
    name: []const u8,
    source_span: ?ParseSourceSpan = null,
};

// ─── Variable ───────────────────────────────────────────────

/// VariableOp — declares a SemanticVariable.
pub const VariableOp = struct {
    kind: OpKind = .Variable,
    xref: XrefId,
    name: []const u8,
    value: ?[]const u8 = null,
    slot: SlotHandle = .{},
    source_span: ?ParseSourceSpan = null,
};

// ─── Namespace ──────────────────────────────────────────────

/// NamespaceOp — declares a namespace change (SVG, MathML).
pub const NamespaceOp = struct {
    kind: OpKind = .NamespaceDeclare,
    xref: XrefId,
    namespace: Namespace = .HTML,
};

// ─── Projection ─────────────────────────────────────────────

/// ProjectionDefOp — declares a projection definition.
pub const ProjectionDefOp = struct {
    kind: OpKind = .ProjectionDef,
    xref: XrefId,
    slot: SlotHandle = .{},
    selectors: []const []const u8 = &.{},
};

/// ProjectionOp — renders a projection (ng-content usage).
pub const ProjectionOp = struct {
    kind: OpKind = .Projection,
    xref: XrefId,
    slot: u32 = 0,
    source_span: ?ParseSourceSpan = null,
};

// ─── ExtractedAttribute ─────────────────────────────────────

/// ExtractedAttributeOp — attribute extracted for consts array.
pub const ExtractedAttributeOp = struct {
    kind: OpKind = .ExtractedAttribute,
    xref: XrefId,
    name: []const u8,
    value: ?[]const u8 = null,
    source_span: ?ParseSourceSpan = null,
};

// ─── Defer ──────────────────────────────────────────────────

/// DeferOp — configures a @defer block.
pub const DeferOp = struct {
    kind: OpKind = .Defer,
    xref: XrefId,
    slot: SlotHandle = .{},
    primary_deps: []const u32 = &.{},
    secondary_deps: []const u32 = &.{},
    primary_template: ?u32 = null,
    placeholder_template: ?u32 = null,
    loading_template: ?u32 = null,
    error_template: ?u32 = null,
    source_span: ?ParseSourceSpan = null,
};

/// DeferOnOp — controls when a @defer loads via trigger.
pub const DeferOnOp = struct {
    kind: OpKind = .DeferOn,
    xref: XrefId,
    trigger: DeferTriggerKind = .Idle,
    parameter: ?[]const u8 = null,
    is_prefetch: bool = false,
    source_span: ?ParseSourceSpan = null,
};

/// DeferTrigger — union of defer trigger types.
pub const DeferTrigger = union(enum) {
    on: DeferOnOp,
    when: []const u8,
    never: void,
};

// ─── DeclareLet ─────────────────────────────────────────────

/// DeclareLetOp — declares a @let variable.
pub const DeclareLetOp = struct {
    kind: OpKind = .Statement,
    xref: XrefId,
    slot: SlotHandle = .{},
    name: []const u8,
    source_span: ?ParseSourceSpan = null,
};

// ─── I18n ───────────────────────────────────────────────────

/// I18nParamValue — a parameter value in an i18n message.
pub const I18nParamValue = struct {
    expression: ?[]const u8 = null,
    flags: u8 = 0, // I18nParamValueFlags
};

/// I18nMessageOp — i18n message extracted for consts array.
pub const I18nMessageOp = struct {
    kind: OpKind = .I18n,
    xref: XrefId,
    source_span: ?ParseSourceSpan = null,
    message: ?[]const u8 = null,
    params: []const I18nParamValue = &.{},
    placeholders: []const []const u8 = &.{},
};

/// I18nOpBase — base for i18n ops.
pub const I18nOpBase = struct {
    kind: OpKind,
    xref: XrefId,
    slot: SlotHandle = .{},
    source_span: ?ParseSourceSpan = null,
    context: u32 = 0,
    message: ?[]const u8 = null,
    params: []const I18nParamValue = &.{},
    index: ?u32 = null,
};

/// I18nOp — i18n operation.
pub const I18nOp = struct { base: I18nOpBase };
/// I18nStartOp — starts an i18n block.
pub const I18nStartOp = struct { base: I18nOpBase };
/// I18nEndOp — ends an i18n block.
pub const I18nEndOp = struct {
    kind: OpKind = .I18nEnd,
    xref: XrefId,
    source_span: ?ParseSourceSpan = null,
};

/// IcuStartOp — starts an ICU expression.
pub const IcuStartOp = struct {
    kind: OpKind = .Icu,
    xref: XrefId,
    slot: SlotHandle = .{},
    source_span: ?ParseSourceSpan = null,
    switch_type: []const u8 = "",
    cases: []const []const u8 = &.{},
};

/// IcuEndOp — ends an ICU expression.
pub const IcuEndOp = struct {
    kind: OpKind = .Icu,
    xref: XrefId,
};

/// IcuPlaceholderOp — ICU placeholder in an i18n block.
pub const IcuPlaceholderOp = struct {
    kind: OpKind = .Icu,
    xref: XrefId,
    source_span: ?ParseSourceSpan = null,
    name: []const u8,
    post_render: ?[]const u8 = null,
};

/// I18nContextOp — i18n context definition.
pub const I18nContextOp = struct {
    kind: OpKind = .Statement,
    xref: XrefId,
    context_kind: u8 = 0, // I18nContextKind
    root: u32 = 0,
    message: ?[]const u8 = null,
    params: []const I18nParamValue = &.{},
};

/// I18nAttributesOp — i18n attributes for an element.
pub const I18nAttributesOp = struct {
    kind: OpKind = .Statement,
    xref: XrefId,
    slot: SlotHandle = .{},
    source_span: ?ParseSourceSpan = null,
    i18n_attrs: []const u8 = "",
};

// ─── Source Location / Control ──────────────────────────────

/// SourceLocationOp — attaches source location metadata.
pub const SourceLocationOp = struct {
    kind: OpKind = .SourceLocation,
    xref: XrefId,
    location: ElementSourceLocation,
};

/// ControlCreateOp — control flow block creation.
pub const ControlCreateOp = struct {
    kind: OpKind = .ControlFlowBlock,
    xref: XrefId,
    source_span: ?ParseSourceSpan = null,
};

// ─── Helper Functions ───────────────────────────────────────

/// Check if an op kind is an element or container op.
pub fn isElementOrContainerOp(kind: OpKind) bool {
    return switch (kind) {
        .ElementStart, .ContainerStart,
        .Template, .RepeaterCreate, .ConditionalCreate,
        .ConditionalBranchCreate => true,
        else => false,
    };
}

/// Create an ElementStartOp.
pub fn createElementStartOp(tag: []const u8, xref: XrefId, namespace: Namespace) ElementStartOp {
    return .{
        .base = .{
            .kind = .ElementStart,
            .xref = xref,
            .tag = tag,
            .namespace = namespace,
        },
    };
}

/// Create an ElementEndOp.
pub fn createElementEndOp(xref: XrefId) ElementEndOp {
    return .{ .xref = xref };
}

/// Create a ContainerStartOp.
pub fn createContainerStartOp(xref: XrefId) ContainerStartOp {
    return .{ .base = .{ .kind = .ContainerStart, .xref = xref } };
}

/// Create a ContainerEndOp.
pub fn createContainerEndOp(xref: XrefId) ContainerEndOp {
    return .{ .xref = xref };
}

/// Create a TextOp.
pub fn createTextOp(xref: XrefId) TextOp {
    return .{ .xref = xref };
}

/// Create a ListenerOp.
pub fn createListenerOp(name: []const u8, xref: XrefId, handler_fn_xref: u32) ListenerOp {
    return .{
        .name = name,
        .xref = xref,
        .handler_fn_xref = handler_fn_xref,
    };
}

/// Create a PipeOp.
pub fn createPipeOp(name: []const u8, xref: XrefId) PipeOp {
    return .{ .name = name, .xref = xref };
}

/// Create a DisableBindingsOp.
pub fn createDisableBindingsOp(xref: XrefId) DisableBindingsOp {
    return .{ .xref = xref };
}

/// Create an EnableBindingsOp.
pub fn createEnableBindingsOp(xref: XrefId) EnableBindingsOp {
    return .{ .xref = xref };
}

/// Create a ContentOp.
pub fn createContentOp(xref: XrefId, slot: u32, selector: ?[]const u8, src_span: ParseSourceSpan) ContentOp {
    return .{
        .xref = xref,
        .slot = slot,
        .selector = selector,
        .source_span = src_span,
    };
}

/// Create a ForeignComponentOp.
pub fn createForeignComponentOp(xref: XrefId) ForeignComponentOp {
    return .{ .xref = xref };
}

/// Create a TemplateOp.
pub fn createTemplateOp(xref: XrefId, tag: ?[]const u8, namespace: Namespace) TemplateOp {
    return .{
        .base = .{
            .kind = .Template,
            .xref = xref,
            .tag = tag,
            .namespace = namespace,
        },
    };
}

/// Create a ConditionalCreateOp.
pub fn createConditionalCreateOp(xref: XrefId, tag: ?[]const u8, namespace: Namespace) ConditionalCreateOp {
    return .{
        .base = .{
            .kind = .ConditionalCreate,
            .xref = xref,
            .tag = tag,
            .namespace = namespace,
        },
    };
}

/// Create a DeferOp.
pub fn createDeferOp(xref: XrefId) DeferOp {
    return .{ .xref = xref };
}

/// Create a DeferOnOp.
pub fn createDeferOnOp(xref: XrefId, trigger: DeferTriggerKind) DeferOnOp {
    return .{ .xref = xref, .trigger = trigger };
}

/// Create an I18nStartOp.
pub fn createI18nStartOp(xref: XrefId) I18nStartOp {
    return .{ .base = .{ .kind = .I18nStart, .xref = xref } };
}

/// Create an I18nEndOp.
pub fn createI18nEndOp(xref: XrefId) I18nEndOp {
    return .{ .xref = xref };
}

/// Create a SourceLocationOp.
pub fn createSourceLocationOp(xref: XrefId, location: ElementSourceLocation) SourceLocationOp {
    return .{ .xref = xref, .location = location };
}

/// Create a ControlCreateOp.
pub fn createControlCreateOp(src_span: ParseSourceSpan) ControlCreateOp {
    return .{ .source_span = src_span };
}

/// Create a NamespaceOp.
pub fn createNamespaceOp(xref: XrefId, namespace: Namespace) NamespaceOp {
    return .{ .xref = xref, .namespace = namespace };
}

/// Create a ProjectionDefOp.
pub fn createProjectionDefOp(xref: XrefId, selectors: []const []const u8) ProjectionDefOp {
    return .{ .xref = xref, .selectors = selectors };
}

/// Create a ProjectionOp.
pub fn createProjectionOp(xref: XrefId, slot: u32) ProjectionOp {
    return .{ .xref = xref, .slot = slot };
}

/// Create a VariableOp.
pub fn createVariableOp(xref: XrefId, name: []const u8) VariableOp {
    return .{ .xref = xref, .name = name };
}

/// Create a DeclareLetOp.
pub fn createDeclareLetOp(xref: XrefId, name: []const u8) DeclareLetOp {
    return .{ .xref = xref, .name = name };
}

/// Create an I18nMessageOp.
pub fn createI18nMessageOp(xref: XrefId) I18nMessageOp {
    return .{ .xref = xref };
}

/// Create an I18nContextOp.
pub fn createI18nContextOp(xref: XrefId) I18nContextOp {
    return .{ .xref = xref };
}

/// Create an I18nAttributesOp.
pub fn createI18nAttributesOp(xref: XrefId) I18nAttributesOp {
    return .{ .xref = xref };
}

/// Create an IcuStartOp.
pub fn createIcuStartOp(xref: XrefId, switch_type: []const u8) IcuStartOp {
    return .{ .xref = xref, .switch_type = switch_type };
}

/// Create an IcuEndOp.
pub fn createIcuEndOp(xref: XrefId) IcuEndOp {
    return .{ .xref = xref };
}

/// Create an IcuPlaceholderOp.
pub fn createIcuPlaceholderOp(xref: XrefId, name: []const u8) IcuPlaceholderOp {
    return .{ .xref = xref, .name = name };
}

/// Create an ExtractedAttributeOp.
pub fn createExtractedAttributeOp(xref: XrefId, name: []const u8, value: ?[]const u8) ExtractedAttributeOp {
    return .{ .xref = xref, .name = name, .value = value };
}

/// Create an AnimationOp.
pub fn createAnimationOp(xref: XrefId, name: []const u8) AnimationOp {
    return .{ .xref = xref, .name = name };
}

/// Create an AnimationStringOp.
pub fn createAnimationStringOp(xref: XrefId, name: []const u8) AnimationStringOp {
    return .{ .xref = xref, .name = name };
}

/// Create an AnimationListenerOp.
pub fn createAnimationListenerOp(xref: XrefId, name: []const u8) AnimationListenerOp {
    return .{ .xref = xref, .name = name };
}

/// Create a TwoWayListenerOp.
pub fn createTwoWayListenerOp(xref: XrefId, name: []const u8, handler_fn_xref: u32) TwoWayListenerOp {
    return .{ .xref = xref, .name = name, .handler_fn_xref = handler_fn_xref };
}

/// Create a RepeaterCreateOp.
pub fn createRepeaterCreateOp(xref: XrefId, tag: ?[]const u8, track: ?[]const u8) RepeaterCreateOp {
    return .{
        .base = .{ .kind = .RepeaterCreate, .xref = xref, .tag = tag },
        .track = track,
    };
}

/// Create a ConditionalBranchCreateOp.
pub fn createConditionalBranchCreateOp(xref: XrefId, tag: ?[]const u8, namespace: Namespace) ConditionalBranchCreateOp {
    return .{
        .base = .{ .kind = .ConditionalBranchCreate, .xref = xref, .tag = tag, .namespace = namespace },
    };
}

test "isElementOrContainerOp" {
    try std.testing.expect(isElementOrContainerOp(.ElementStart));
    try std.testing.expect(isElementOrContainerOp(.ContainerStart));
    try std.testing.expect(!isElementOrContainerOp(.Text));
}

test "createElementStartOp" {
    const op = createElementStartOp("div", 0, .HTML);
    try std.testing.expectEqualStrings("div", op.base.tag.?);
    try std.testing.expectEqual(@as(u32, 0), op.base.xref);
}
