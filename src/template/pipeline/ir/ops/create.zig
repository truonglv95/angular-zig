/// IR Create Ops — All creation-phase operation types for the Angular IR
///
/// Port of: template/pipeline/ir/src/ops/create.ts (2095 LoC)
///
/// This file defines all creation-phase operation types. Each op is a plain
/// struct with a kind discriminant and optional data. The operations are:
///   - Element: ElementStart, ElementEnd, Element, Container, ContainerStart, ContainerEnd
///   - Template: Template, ConditionalCreate, ConditionalBranchCreate, RepeaterCreate
///   - Content: Content, Projection, ProjectionDef, ForeignComponent
///   - Text: Text, Listener, TwoWayListener, AnimationListener
///   - Binding: DisableBindings, EnableBindings, ExtractedAttribute
///   - Defer: Defer, DeferOn, EnableIncrementalHydrationRuntime
///   - i18n: I18nMessage, I18n, I18nStart, I18nEnd, I18nContext, I18nAttributes
///   - ICU: IcuStart, IcuEnd, IcuPlaceholder
///   - Misc: Pipe, Variable, Namespace, DeclareLet, Statement, SourceLocation, ControlCreate
const std = @import("std");
const create_ops = @import("../create_ops.zig");
const ir_enums = @import("../enums.zig");

/// Re-export OpKind for convenience.
pub const OpKind = ir_enums.OpKind;

/// Re-export XrefId for convenience.
pub const XrefId = create_ops.XrefId;

/// Re-export types from create_ops.zig for backward compatibility.
pub const LocalRef = create_ops.LocalRef;
pub const ElementSourceLocation = create_ops.ElementSourceLocation;
pub const ElementOrContainerOpBase = create_ops.ElementOrContainerOpBase;
pub const ElementStartOp = create_ops.ElementStartOp;
pub const ElementOp = create_ops.ElementOp;
pub const ElementEndOp = create_ops.ElementEndOp;
pub const ContainerStartOp = create_ops.ContainerStartOp;
pub const ContainerOp = create_ops.ContainerOp;
pub const ContainerEndOp = create_ops.ContainerEndOp;
pub const TemplateOp = create_ops.TemplateOp;
pub const ConditionalCreateOp = create_ops.ConditionalCreateOp;
pub const ConditionalBranchCreateOp = create_ops.ConditionalBranchCreateOp;
pub const RepeaterCreateOp = create_ops.RepeaterCreateOp;
pub const RepeaterVarNames = create_ops.RepeaterVarNames;
pub const ForeignComponentOp = create_ops.ForeignComponentOp;
pub const ContentOp = create_ops.ContentOp;
pub const DisableBindingsOp = create_ops.DisableBindingsOp;
pub const EnableBindingsOp = create_ops.EnableBindingsOp;
pub const TextOp = create_ops.TextOp;
pub const ListenerOp = create_ops.ListenerOp;
pub const TwoWayListenerOp = create_ops.TwoWayListenerOp;
pub const AnimationListenerOp = create_ops.AnimationListenerOp;
pub const AnimationOp = create_ops.AnimationOp;
pub const AnimationStringOp = create_ops.AnimationStringOp;
pub const PipeOp = create_ops.PipeOp;
pub const NamespaceOp = create_ops.NamespaceOp;
pub const ProjectionDefOp = create_ops.ProjectionDefOp;
pub const ProjectionOp = create_ops.ProjectionOp;
pub const ExtractedAttributeOp = create_ops.ExtractedAttributeOp;
pub const DeferOp = create_ops.DeferOp;
pub const DeferOnOp = create_ops.DeferOnOp;
// Note: DeferTrigger is defined below as a tagged union
pub const DeclareLetOp = create_ops.DeclareLetOp;
// Note: I18nParamValue is defined below with I18nParamValueValue
pub const I18nMessageOp = create_ops.I18nMessageOp;
pub const I18nOpBase = create_ops.I18nOpBase;
pub const I18nOp = create_ops.I18nOp;
pub const I18nStartOp = create_ops.I18nStartOp;
pub const I18nEndOp = create_ops.I18nEndOp;
pub const IcuStartOp = create_ops.IcuStartOp;
pub const IcuEndOp = create_ops.IcuEndOp;
pub const IcuPlaceholderOp = create_ops.IcuPlaceholderOp;
pub const I18nContextOp = create_ops.I18nContextOp;
pub const I18nAttributesOp = create_ops.I18nAttributesOp;
pub const SourceLocationOp = create_ops.SourceLocationOp;
pub const ControlCreateOp = create_ops.ControlCreateOp;
pub const EnableIncrementalHydrationRuntimeOp = create_ops.EnableIncrementalHydrationRuntimeOp;

/// Re-export functions from create_ops.zig.
pub const isElementOrContainerOp = create_ops.isElementOrContainerOp;
pub const createElementStartOp = create_ops.createElementStartOp;
pub const createElementEndOp = create_ops.createElementEndOp;
pub const createContainerStartOp = create_ops.createContainerStartOp;
pub const createContainerEndOp = create_ops.createContainerEndOp;
pub const createTextOp = create_ops.createTextOp;
pub const createListenerOp = create_ops.createListenerOp;
pub const createPipeOp = create_ops.createPipeOp;
pub const createDisableBindingsOp = create_ops.createDisableBindingsOp;
pub const createEnableBindingsOp = create_ops.createEnableBindingsOp;
pub const createContentOp = create_ops.createContentOp;
pub const createForeignComponentOp = create_ops.createForeignComponentOp;
pub const createTemplateOp = create_ops.createTemplateOp;
pub const createConditionalCreateOp = create_ops.createConditionalCreateOp;
pub const createControlCreateOp = create_ops.createControlCreateOp;
pub const createProjectionDefOp = create_ops.createProjectionDefOp;
pub const createProjectionOp = create_ops.createProjectionOp;
pub const createNamespaceOp = create_ops.createNamespaceOp;
pub const createExtractedAttributeOp = create_ops.createExtractedAttributeOp;
pub const createDeferOp = create_ops.createDeferOp;
pub const createDeferOnOp = create_ops.createDeferOnOp;
pub const createDeclareLetOp = create_ops.createDeclareLetOp;
pub const createI18nStartOp = create_ops.createI18nStartOp;
pub const createI18nEndOp = create_ops.createI18nEndOp;
pub const createI18nMessageOp = create_ops.createI18nMessageOp;
pub const createIcuStartOp = create_ops.createIcuStartOp;
pub const createIcuEndOp = create_ops.createIcuEndOp;
pub const createIcuPlaceholderOp = create_ops.createIcuPlaceholderOp;
pub const createI18nContextOp = create_ops.createI18nContextOp;
pub const createI18nAttributesOp = create_ops.createI18nAttributesOp;
pub const createSourceLocationOp = create_ops.createSourceLocationOp;
pub const createAnimationOp = create_ops.createAnimationOp;
pub const createAnimationStringOp = create_ops.createAnimationStringOp;
pub const createAnimationListenerOp = create_ops.createAnimationListenerOp;
pub const createTwoWayListenerOp = create_ops.createTwoWayListenerOp;
pub const createEnableIncrementalHydrationRuntimeOp = create_ops.createEnableIncrementalHydrationRuntimeOp;

/// Re-export type aliases.
pub const CreateOp = create_ops.CreateOp;
pub const ElementOrContainerOps = create_ops.ElementOrContainerOps;
pub const ConstIndex = create_ops.ConstIndex;

/// SlotHandle — a handle to a slot in the LView.
pub const SlotHandle = create_ops.SlotHandle;

// ─── Additional types from create.ts not yet in create_ops.zig ──

/// CreateOp type union — represents any creation-phase operation.
/// In the TS source, this is a discriminated union of all CreateOp subtypes.
/// In our DOD model, we use the OpKind enum from ops.zig to discriminate.
pub const CreateOpKind = ir_enums.OpKind;

/// Check if an op kind is a creation-phase op.
pub fn isCreateOp(kind: CreateOpKind) bool {
    return ir_enums.isCreationOp(kind);
}

// ─── Defer trigger types (direct port from create.ts) ──────

/// DeferTriggerKind — kind of defer trigger.
/// Re-exported from ir_enums for convenience.
pub const DeferTriggerKind = ir_enums.DeferTriggerKind;

/// DeferTriggerBase — base for defer triggers.
/// Direct port of `DeferTriggerBase` interface in the TS source.
pub const DeferTriggerBase = struct {
    kind: DeferTriggerKind,
};

/// DeferTriggerWithTargetBase — base for defer triggers with a target.
/// Direct port of `DeferTriggerWithTargetBase` interface in the TS source.
pub const DeferTriggerWithTargetBase = struct {
    kind: DeferTriggerKind,
    target_name: ?[]const u8 = null,
    target_xref: ?XrefId = null,
    target_slot: ?SlotHandle = null,
    target_view: ?XrefId = null,
    target_slot_view_steps: ?i32 = null,
};

/// DeferIdleTrigger — fires when browser is idle.
/// Direct port of `DeferIdleTrigger` interface in the TS source.
pub const DeferIdleTrigger = struct {
    base: DeferTriggerBase,
    timeout: ?u32 = null,

    pub fn init(timeout: ?u32) DeferIdleTrigger {
        return .{
            .base = .{ .kind = .Idle },
            .timeout = timeout,
        };
    }
};

/// DeferImmediateTrigger — fires immediately.
/// Direct port of `DeferImmediateTrigger` interface in the TS source.
pub const DeferImmediateTrigger = struct {
    base: DeferTriggerBase,

    pub fn init() DeferImmediateTrigger {
        return .{ .base = .{ .kind = .Immediate } };
    }
};

/// DeferNeverTrigger — never fires.
/// Direct port of `DeferNeverTrigger` interface in the TS source.
pub const DeferNeverTrigger = struct {
    base: DeferTriggerBase,

    pub fn init() DeferNeverTrigger {
        return .{ .base = .{ .kind = .Never } };
    }
};

/// DeferHoverTrigger — fires on hover.
/// Direct port of `DeferHoverTrigger` interface in the TS source.
pub const DeferHoverTrigger = struct {
    base: DeferTriggerWithTargetBase,

    pub fn init(target_name: ?[]const u8) DeferHoverTrigger {
        return .{
            .base = .{
                .kind = .Hover,
                .target_name = target_name,
            },
        };
    }
};

/// DeferTimerTrigger — fires after a delay.
/// Direct port of `DeferTimerTrigger` interface in the TS source.
pub const DeferTimerTrigger = struct {
    base: DeferTriggerBase,
    delay: u32,

    pub fn init(delay: u32) DeferTimerTrigger {
        return .{
            .base = .{ .kind = .Timer },
            .delay = delay,
        };
    }
};

/// DeferInteractionTrigger — fires on interaction.
/// Direct port of `DeferInteractionTrigger` interface in the TS source.
pub const DeferInteractionTrigger = struct {
    base: DeferTriggerWithTargetBase,

    pub fn init(target_name: ?[]const u8) DeferInteractionTrigger {
        return .{
            .base = .{
                .kind = .Interaction,
                .target_name = target_name,
            },
        };
    }
};

/// DeferViewportTrigger — fires when in viewport.
/// Direct port of `DeferViewportTrigger` interface in the TS source.
pub const DeferViewportTrigger = struct {
    base: DeferTriggerWithTargetBase,
    options: ?[]const u8 = null,

    pub fn init(target_name: ?[]const u8, options: ?[]const u8) DeferViewportTrigger {
        return .{
            .base = .{
                .kind = .Viewport,
                .target_name = target_name,
            },
            .options = options,
        };
    }
};

/// DeferTrigger — tagged union of all defer trigger types.
/// Direct port of `DeferTrigger` type in the TS source.
pub const DeferTrigger = union(DeferTriggerKind) {
    Idle: DeferIdleTrigger,
    Immediate: DeferImmediateTrigger,
    Timer: DeferTimerTrigger,
    Hover: DeferHoverTrigger,
    Interaction: DeferInteractionTrigger,
    Viewport: DeferViewportTrigger,
    Never: DeferNeverTrigger,
};

/// DeferOpModifierKind — modifier on a defer trigger.
/// Direct port of `DeferOpModifierKind` from enums.ts.
pub const DeferOpModifierKind = ir_enums.DeferOpModifierKind;

// ─── I18nParamValue (direct port from create.ts) ───────────

/// I18nParamValueFlags — flags for an i18n param value.
/// Direct port of `I18nParamValueFlags` from enums.ts.
pub const I18nParamValueFlags = ir_enums.I18nParamValueFlags;

/// I18nParamValue — a single value in an i18n param map.
/// Direct port of `I18nParamValue` interface in the TS source.
pub const I18nParamValue = struct {
    /// The value: either a slot number, special string, or compound value.
    value: I18nParamValueValue,
    /// The sub-template index associated with the value.
    sub_template_index: ?u32 = null,
    /// Flags associated with the value.
    flags: I18nParamValueFlags = .None,
};

/// I18nParamValueValue — the value of an i18n param.
pub const I18nParamValueValue = union(enum) {
    string: []const u8,
    number: u32,
    compound: struct {
        element: u32,
        template: u32,
    },
};

// ─── I18nContextKind (direct port from enums.ts) ───────────

/// I18nContextKind — kind of i18n context.
pub const I18nContextKind = ir_enums.I18nContextKind;

// ─── AnimationKind (direct port from enums.ts) ─────────────

/// AnimationKind — kind of animation (enter or leave).
pub const AnimationKind = ir_enums.AnimationKind;

// ─── TemplateKind (direct port from enums.ts) ──────────────

/// TemplateKind — kind of template.
pub const TemplateKind = ir_enums.TemplateKind;

// ─── TDeferDetailsFlags (direct port from enums.ts) ────────

/// TDeferDetailsFlags — flags for defer details.
pub const TDeferDetailsFlags = ir_enums.TDeferDetailsFlags;

// ─── SecurityContext ───────────────────────────────────────

/// SecurityContext — the security context for a binding.
pub const SecurityContext = enum(u8) {
    None = 0,
    HTML = 1,
    Style = 2,
    Script = 3,
    URL = 4,
    ResourceURL = 5,
};

// ─── Helper functions for defer triggers ───────────────────

/// Create a DeferIdleTrigger.
pub fn createDeferIdleTrigger(timeout: ?u32) DeferIdleTrigger {
    return DeferIdleTrigger.init(timeout);
}

/// Create a DeferImmediateTrigger.
pub fn createDeferImmediateTrigger() DeferImmediateTrigger {
    return DeferImmediateTrigger.init();
}

/// Create a DeferNeverTrigger.
pub fn createDeferNeverTrigger() DeferNeverTrigger {
    return DeferNeverTrigger.init();
}

/// Create a DeferHoverTrigger.
pub fn createDeferHoverTrigger(target_name: ?[]const u8) DeferHoverTrigger {
    return DeferHoverTrigger.init(target_name);
}

/// Create a DeferTimerTrigger.
pub fn createDeferTimerTrigger(delay: u32) DeferTimerTrigger {
    return DeferTimerTrigger.init(delay);
}

/// Create a DeferInteractionTrigger.
pub fn createDeferInteractionTrigger(target_name: ?[]const u8) DeferInteractionTrigger {
    return DeferInteractionTrigger.init(target_name);
}

/// Create a DeferViewportTrigger.
pub fn createDeferViewportTrigger(target_name: ?[]const u8, options: ?[]const u8) DeferViewportTrigger {
    return DeferViewportTrigger.init(target_name, options);
}

/// Check if a defer trigger has a target.
pub fn deferTriggerHasTarget(trigger: DeferTrigger) bool {
    return switch (trigger) {
        .Hover => |h| h.base.target_name != null,
        .Interaction => |i| i.base.target_name != null,
        .Viewport => |v| v.base.target_name != null,
        else => false,
    };
}

/// Get the kind of a defer trigger.
pub fn getDeferTriggerKind(trigger: DeferTrigger) DeferTriggerKind {
    return switch (trigger) {
        .Idle => .Idle,
        .Immediate => .Immediate,
        .Timer => .Timer,
        .Hover => .Hover,
        .Interaction => .Interaction,
        .Viewport => .Viewport,
        .Never => .Never,
    };
}

// ─── Element/container op kind checking ────────────────────

/// Set of op kinds that represent element or container creation.
const element_container_op_kinds = [_]OpKind{
    .ElementStart,
    .ContainerStart,
    .Template,
    .RepeaterCreate,
    .ConditionalCreate,
    .ConditionalBranchCreate,
};

/// Check if an op kind is an element or container op.
pub fn isElementOrContainerOpKind(kind: OpKind) bool {
    for (element_container_op_kinds) |k| {
        if (k == kind) return true;
    }
    return false;
}

// ─── I18n op kind checking ─────────────────────────────────

/// Check if an op kind is an i18n-related op.
pub fn isI18nOp(kind: OpKind) bool {
    return switch (kind) {
        .I18n, .I18nStart, .I18nEnd, .I18nContext, .I18nAttributes => true,
        else => false,
    };
}

/// Check if an op kind is an ICU-related op.
pub fn isIcuOp(kind: OpKind) bool {
    return switch (kind) {
        .IcuStart, .IcuEnd, .IcuPlaceholder => true,
        else => false,
    };
}

/// Check if an op kind is a defer-related op.
pub fn isDeferOp(kind: OpKind) bool {
    return switch (kind) {
        .Defer, .DeferOn, .EnableIncrementalHydrationRuntime => true,
        else => false,
    };
}

/// Check if an op kind is an animation-related op.
pub fn isAnimationOp(kind: OpKind) bool {
    return switch (kind) {
        .Animation, .AnimationString, .AnimationListener => true,
        else => false,
    };
}

/// Check if an op kind is a listener op.
pub fn isListenerOp(kind: OpKind) bool {
    return switch (kind) {
        .Listener, .TwoWayListener, .AnimationListener => true,
        else => false,
    };
}

/// Check if an op kind consumes a slot.
pub fn consumesSlot(kind: OpKind) bool {
    return switch (kind) {
        .ElementStart, .ContainerStart, .Template,
        .RepeaterCreate, .ConditionalCreate, .ConditionalBranchCreate,
        .Text, .Projection, .Defer,
        .I18n, .I18nStart, .I18nAttributes,
        => true,
        else => false,
    };
}

/// Check if an op kind consumes vars.
pub fn consumesVars(kind: OpKind) bool {
    return switch (kind) {
        .RepeaterCreate => true,
        else => false,
    };
}

// ─── Op grouping helpers ───────────────────────────────────

/// Get the group name for an op kind.
pub fn getOpGroup(kind: OpKind) []const u8 {
    return switch (kind) {
        .ElementStart, .ElementEnd, .ContainerStart, .ContainerEnd => "element",
        .Template, .ConditionalCreate, .ConditionalBranchCreate, .RepeaterCreate => "template",
        .Text => "text",
        .Listener, .AnimationListener => "listener",
        .Projection, .ProjectionDef, .Content => "projection",
        .Defer, .DeferOn, .DeferWhen, .EnableIncrementalHydrationRuntime => "defer",
        .I18n, .I18nStart, .I18nEnd, .I18nContext, .I18nAttributes => "i18n",
        .IcuStart, .IcuEnd, .IcuPlaceholder => "icu",
        .NamespaceDeclare => "namespace",
        .DisableBindings, .EnableBindings => "bindings",
        .ExtractedAttribute => "attribute",
        .Animation => "animation",
        .SourceLocation => "source",
        .ControlCreate, .Control => "control",
        .ForeignComponent => "foreign",
        else => "other",
    };
}

// ─── SecurityContext helpers ───────────────────────────────

/// Convert SecurityContext to string.
pub fn securityContextToString(ctx: SecurityContext) []const u8 {
    return switch (ctx) {
        .None => "None",
        .HTML => "HTML",
        .Style => "Style",
        .Script => "Script",
        .URL => "URL",
        .ResourceURL => "ResourceURL",
    };
}

/// Convert string to SecurityContext.
pub fn stringToSecurityContext(s: []const u8) ?SecurityContext {
    if (std.mem.eql(u8, s, "None")) return .None;
    if (std.mem.eql(u8, s, "HTML")) return .HTML;
    if (std.mem.eql(u8, s, "Style")) return .Style;
    if (std.mem.eql(u8, s, "Script")) return .Script;
    if (std.mem.eql(u8, s, "URL")) return .URL;
    if (std.mem.eql(u8, s, "ResourceURL")) return .ResourceURL;
    return null;
}

// ─── AnimationKind helpers ─────────────────────────────────

/// Convert AnimationKind to string.
pub fn animationKindToString(kind: AnimationKind) []const u8 {
    return switch (kind) {
        .ENTER => "Enter",
        .LEAVE => "Leave",
    };
}

// ─── TemplateKind helpers ──────────────────────────────────

/// Convert TemplateKind to string.
pub fn templateKindToString(kind: TemplateKind) []const u8 {
    return switch (kind) {
        .NgTemplate => "NgTemplate",
        .Structural => "Structural",
        .Block => "Block",
    };
}

// ─── I18nContextKind helpers ───────────────────────────────

/// Convert I18nContextKind to string.
pub fn i18nContextKindToString(kind: I18nContextKind) []const u8 {
    return switch (kind) {
        .RootI18n => "Block",
        .Icu => "Icu",
        .Attr => "Attr",
    };
}

// ─── DeferTriggerKind helpers ──────────────────────────────

/// Convert DeferTriggerKind to string.
pub fn deferTriggerKindToString(kind: DeferTriggerKind) []const u8 {
    return switch (kind) {
        .Idle => "Idle",
        .Immediate => "Immediate",
        .Timer => "Timer",
        .Hover => "Hover",
        .Interaction => "Interaction",
        .Viewport => "Viewport",
        .Never => "Never",
    };
}

// ─── DeferOpModifierKind helpers ───────────────────────────

/// Convert DeferOpModifierKind to string.
pub fn deferOpModifierKindToString(kind: DeferOpModifierKind) []const u8 {
    return switch (kind) {
        .NONE => "Normal",
        .PREFETCH => "Prefetch",
        .HYDRATE => "Hydrate",
    };
}

// ─── Tests ──────────────────────────────────────────────────

test "isElementOrContainerOp" {
    try std.testing.expect(isElementOrContainerOp(.ElementStart));
    try std.testing.expect(isElementOrContainerOp(.ContainerStart));
    try std.testing.expect(!isElementOrContainerOp(.Text));
}

test "isCreateOp" {
    try std.testing.expect(isCreateOp(.ElementStart));
    try std.testing.expect(isCreateOp(.Text));
    try std.testing.expect(isCreateOp(.Listener));
    try std.testing.expect(!isCreateOp(.Property));
    try std.testing.expect(!isCreateOp(.Binding));
}

test "CreateOpKind is OpKind" {
    try std.testing.expectEqual(CreateOpKind.ElementStart, .ElementStart);
}

test "isElementOrContainerOpKind — all element/container kinds" {
    try std.testing.expect(isElementOrContainerOpKind(.ElementStart));
    try std.testing.expect(isElementOrContainerOpKind(.ContainerStart));
    try std.testing.expect(isElementOrContainerOpKind(.Template));
    try std.testing.expect(isElementOrContainerOpKind(.RepeaterCreate));
    try std.testing.expect(isElementOrContainerOpKind(.ConditionalCreate));
    try std.testing.expect(isElementOrContainerOpKind(.ConditionalBranchCreate));
}

test "isElementOrContainerOpKind — non-element kinds" {
    try std.testing.expect(!isElementOrContainerOpKind(.Text));
    try std.testing.expect(!isElementOrContainerOpKind(.Listener));
    try std.testing.expect(!isElementOrContainerOpKind(.Property));
}

test "isI18nOp — i18n kinds" {
    try std.testing.expect(isI18nOp(.I18n));
    try std.testing.expect(isI18nOp(.I18nStart));
    try std.testing.expect(isI18nOp(.I18nEnd));
    try std.testing.expect(isI18nOp(.I18nContext));
    try std.testing.expect(isI18nOp(.I18nAttributes));
}

test "isI18nOp — non-i18n kinds" {
    try std.testing.expect(!isI18nOp(.Text));
    try std.testing.expect(!isI18nOp(.ElementStart));
}

test "isIcuOp — icu kinds" {
    try std.testing.expect(isIcuOp(.IcuStart));
    try std.testing.expect(isIcuOp(.IcuEnd));
    try std.testing.expect(isIcuOp(.IcuPlaceholder));
}

test "isIcuOp — non-icu kinds" {
    try std.testing.expect(!isIcuOp(.Text));
    try std.testing.expect(!isIcuOp(.I18n));
}

test "isDeferOp — defer kinds" {
    try std.testing.expect(isDeferOp(.Defer));
    try std.testing.expect(isDeferOp(.DeferOn));
    try std.testing.expect(isDeferOp(.EnableIncrementalHydrationRuntime));
}

test "isDeferOp — non-defer kinds" {
    try std.testing.expect(!isDeferOp(.Text));
    try std.testing.expect(!isDeferOp(.ElementStart));
}

test "isAnimationOp — animation kinds" {
    try std.testing.expect(isAnimationOp(.Animation));
    try std.testing.expect(isAnimationOp(.AnimationString));
    try std.testing.expect(isAnimationOp(.AnimationListener));
}

test "isAnimationOp — non-animation kinds" {
    try std.testing.expect(!isAnimationOp(.Text));
    try std.testing.expect(!isAnimationOp(.Listener));
}

test "isListenerOp — listener kinds" {
    try std.testing.expect(isListenerOp(.Listener));
    try std.testing.expect(isListenerOp(.AnimationListener));
}

test "isListenerOp — non-listener kinds" {
    try std.testing.expect(!isListenerOp(.Text));
    try std.testing.expect(!isListenerOp(.ElementStart));
}

test "consumesSlot — slot-consuming kinds" {
    try std.testing.expect(consumesSlot(.ElementStart));
    try std.testing.expect(consumesSlot(.Text));
    try std.testing.expect(consumesSlot(.Defer));
}

test "consumesSlot — non-slot kinds" {
    try std.testing.expect(!consumesSlot(.ElementEnd));
    try std.testing.expect(!consumesSlot(.Listener));
    try std.testing.expect(!consumesSlot(.NamespaceDeclare));
}

test "consumesVars — vars-consuming kinds" {
    try std.testing.expect(consumesVars(.RepeaterCreate));
}

test "consumesVars — non-vars kinds" {
    try std.testing.expect(!consumesVars(.ElementStart));
    try std.testing.expect(!consumesVars(.Text));
}

test "getOpGroup — element group" {
    try std.testing.expectEqualStrings("element", getOpGroup(.ElementStart));
    try std.testing.expectEqualStrings("element", getOpGroup(.ElementEnd));
    try std.testing.expectEqualStrings("element", getOpGroup(.ContainerStart));
    try std.testing.expectEqualStrings("element", getOpGroup(.ContainerEnd));
}

test "getOpGroup — template group" {
    try std.testing.expectEqualStrings("template", getOpGroup(.Template));
    try std.testing.expectEqualStrings("template", getOpGroup(.RepeaterCreate));
    try std.testing.expectEqualStrings("template", getOpGroup(.ConditionalCreate));
}

test "getOpGroup — i18n group" {
    try std.testing.expectEqualStrings("i18n", getOpGroup(.I18n));
    try std.testing.expectEqualStrings("i18n", getOpGroup(.I18nStart));
}

test "getOpGroup — icu group" {
    try std.testing.expectEqualStrings("icu", getOpGroup(.IcuStart));
    try std.testing.expectEqualStrings("icu", getOpGroup(.IcuEnd));
}

test "getOpGroup — defer group" {
    try std.testing.expectEqualStrings("defer", getOpGroup(.Defer));
    try std.testing.expectEqualStrings("defer", getOpGroup(.DeferOn));
}

test "securityContextToString" {
    try std.testing.expectEqualStrings("None", securityContextToString(.None));
    try std.testing.expectEqualStrings("HTML", securityContextToString(.HTML));
    try std.testing.expectEqualStrings("Style", securityContextToString(.Style));
    try std.testing.expectEqualStrings("Script", securityContextToString(.Script));
    try std.testing.expectEqualStrings("URL", securityContextToString(.URL));
    try std.testing.expectEqualStrings("ResourceURL", securityContextToString(.ResourceURL));
}

test "stringToSecurityContext — valid strings" {
    try std.testing.expectEqual(SecurityContext.None, stringToSecurityContext("None").?);
    try std.testing.expectEqual(SecurityContext.HTML, stringToSecurityContext("HTML").?);
    try std.testing.expectEqual(SecurityContext.URL, stringToSecurityContext("URL").?);
}

test "stringToSecurityContext — invalid string" {
    try std.testing.expect(stringToSecurityContext("Invalid") == null);
}

test "SecurityContext enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(SecurityContext.None));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(SecurityContext.HTML));
    try std.testing.expectEqual(@as(u8, 5), @intFromEnum(SecurityContext.ResourceURL));
}

// ─── Defer trigger tests ───────────────────────────────────

test "DeferIdleTrigger init" {
    const trigger = createDeferIdleTrigger(1000);
    try std.testing.expectEqual(DeferTriggerKind.Idle, trigger.base.kind);
    try std.testing.expectEqual(@as(u32, 1000), trigger.timeout.?);
}

test "DeferIdleTrigger init — no timeout" {
    const trigger = createDeferIdleTrigger(null);
    try std.testing.expectEqual(DeferTriggerKind.Idle, trigger.base.kind);
    try std.testing.expect(trigger.timeout == null);
}

test "DeferImmediateTrigger init" {
    const trigger = createDeferImmediateTrigger();
    try std.testing.expectEqual(DeferTriggerKind.Immediate, trigger.base.kind);
}

test "DeferNeverTrigger init" {
    const trigger = createDeferNeverTrigger();
    try std.testing.expectEqual(DeferTriggerKind.Never, trigger.base.kind);
}

test "DeferHoverTrigger init — with target" {
    const trigger = createDeferHoverTrigger("myButton");
    try std.testing.expectEqual(DeferTriggerKind.Hover, trigger.base.kind);
    try std.testing.expectEqualStrings("myButton", trigger.base.target_name.?);
}

test "DeferHoverTrigger init — no target" {
    const trigger = createDeferHoverTrigger(null);
    try std.testing.expectEqual(DeferTriggerKind.Hover, trigger.base.kind);
    try std.testing.expect(trigger.base.target_name == null);
}

test "DeferTimerTrigger init" {
    const trigger = createDeferTimerTrigger(500);
    try std.testing.expectEqual(DeferTriggerKind.Timer, trigger.base.kind);
    try std.testing.expectEqual(@as(u32, 500), trigger.delay);
}

test "DeferInteractionTrigger init" {
    const trigger = createDeferInteractionTrigger("myInput");
    try std.testing.expectEqual(DeferTriggerKind.Interaction, trigger.base.kind);
    try std.testing.expectEqualStrings("myInput", trigger.base.target_name.?);
}

test "DeferViewportTrigger init" {
    const trigger = createDeferViewportTrigger("myElement", "options");
    try std.testing.expectEqual(DeferTriggerKind.Viewport, trigger.base.kind);
    try std.testing.expectEqualStrings("myElement", trigger.base.target_name.?);
    try std.testing.expectEqualStrings("options", trigger.options.?);
}

test "DeferViewportTrigger init — no options" {
    const trigger = createDeferViewportTrigger(null, null);
    try std.testing.expectEqual(DeferTriggerKind.Viewport, trigger.base.kind);
    try std.testing.expect(trigger.base.target_name == null);
    try std.testing.expect(trigger.options == null);
}

test "DeferTrigger union — Idle" {
    const trigger = DeferTrigger{ .Idle = createDeferIdleTrigger(500) };
    try std.testing.expectEqual(DeferTriggerKind.Idle, getDeferTriggerKind(trigger));
}

test "DeferTrigger union — Immediate" {
    const trigger = DeferTrigger{ .Immediate = createDeferImmediateTrigger() };
    try std.testing.expectEqual(DeferTriggerKind.Immediate, getDeferTriggerKind(trigger));
}

test "DeferTrigger union — Timer" {
    const trigger = DeferTrigger{ .Timer = createDeferTimerTrigger(200) };
    try std.testing.expectEqual(DeferTriggerKind.Timer, getDeferTriggerKind(trigger));
}

test "DeferTrigger union — Hover" {
    const trigger = DeferTrigger{ .Hover = createDeferHoverTrigger("target") };
    try std.testing.expectEqual(DeferTriggerKind.Hover, getDeferTriggerKind(trigger));
}

test "DeferTrigger union — Never" {
    const trigger = DeferTrigger{ .Never = createDeferNeverTrigger() };
    try std.testing.expectEqual(DeferTriggerKind.Never, getDeferTriggerKind(trigger));
}

test "deferTriggerHasTarget — Hover with target" {
    const trigger = DeferTrigger{ .Hover = createDeferHoverTrigger("myTarget") };
    try std.testing.expect(deferTriggerHasTarget(trigger));
}

test "deferTriggerHasTarget — Hover without target" {
    const trigger = DeferTrigger{ .Hover = createDeferHoverTrigger(null) };
    try std.testing.expect(!deferTriggerHasTarget(trigger));
}

test "deferTriggerHasTarget — Idle (no target)" {
    const trigger = DeferTrigger{ .Idle = createDeferIdleTrigger(null) };
    try std.testing.expect(!deferTriggerHasTarget(trigger));
}

test "deferTriggerHasTarget — Interaction with target" {
    const trigger = DeferTrigger{ .Interaction = createDeferInteractionTrigger("myInput") };
    try std.testing.expect(deferTriggerHasTarget(trigger));
}

test "deferTriggerHasTarget — Viewport with target" {
    const trigger = DeferTrigger{ .Viewport = createDeferViewportTrigger("myDiv", null) };
    try std.testing.expect(deferTriggerHasTarget(trigger));
}

test "deferTriggerKindToString" {
    try std.testing.expectEqualStrings("Idle", deferTriggerKindToString(.Idle));
    try std.testing.expectEqualStrings("Immediate", deferTriggerKindToString(.Immediate));
    try std.testing.expectEqualStrings("Timer", deferTriggerKindToString(.Timer));
    try std.testing.expectEqualStrings("Hover", deferTriggerKindToString(.Hover));
    try std.testing.expectEqualStrings("Interaction", deferTriggerKindToString(.Interaction));
    try std.testing.expectEqualStrings("Viewport", deferTriggerKindToString(.Viewport));
    try std.testing.expectEqualStrings("Never", deferTriggerKindToString(.Never));
}

test "deferOpModifierKindToString" {
    try std.testing.expectEqualStrings("Normal", deferOpModifierKindToString(.NONE));
    try std.testing.expectEqualStrings("Prefetch", deferOpModifierKindToString(.PREFETCH));
    try std.testing.expectEqualStrings("Hydrate", deferOpModifierKindToString(.HYDRATE));
}

// ─── I18nParamValue tests ──────────────────────────────────

test "I18nParamValue — string value" {
    const pv = I18nParamValue{
        .value = .{ .string = "hello" },
    };
    try std.testing.expectEqualStrings("hello", pv.value.string);
    try std.testing.expect(pv.sub_template_index == null);
}

test "I18nParamValue — number value" {
    const pv = I18nParamValue{
        .value = .{ .number = 42 },
    };
    try std.testing.expectEqual(@as(u32, 42), pv.value.number);
}

test "I18nParamValue — compound value" {
    const pv = I18nParamValue{
        .value = .{ .compound = .{ .element = 1, .template = 2 } },
    };
    try std.testing.expectEqual(@as(u32, 1), pv.value.compound.element);
    try std.testing.expectEqual(@as(u32, 2), pv.value.compound.template);
}

test "I18nParamValue — with sub_template_index" {
    const pv = I18nParamValue{
        .value = .{ .number = 10 },
        .sub_template_index = 3,
    };
    try std.testing.expectEqual(@as(u32, 3), pv.sub_template_index.?);
}

// ─── AnimationKind tests ───────────────────────────────────

test "animationKindToString" {
    try std.testing.expectEqualStrings("Enter", animationKindToString(.ENTER));
    try std.testing.expectEqualStrings("Leave", animationKindToString(.LEAVE));
}

// ─── TemplateKind tests ────────────────────────────────────

test "templateKindToString" {
    try std.testing.expectEqualStrings("NgTemplate", templateKindToString(.NgTemplate));
    try std.testing.expectEqualStrings("Structural", templateKindToString(.Structural));
    try std.testing.expectEqualStrings("Block", templateKindToString(.Block));
}

// ─── I18nContextKind tests ─────────────────────────────────

test "i18nContextKindToString" {
    try std.testing.expectEqualStrings("Block", i18nContextKindToString(.RootI18n));
    try std.testing.expectEqualStrings("Icu", i18nContextKindToString(.Icu));
    try std.testing.expectEqualStrings("Attr", i18nContextKindToString(.Attr));
}
