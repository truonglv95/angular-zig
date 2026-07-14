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
pub const DeferTrigger = create_ops.DeferTrigger;
pub const DeclareLetOp = create_ops.DeclareLetOp;
pub const I18nParamValue = create_ops.I18nParamValue;
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
