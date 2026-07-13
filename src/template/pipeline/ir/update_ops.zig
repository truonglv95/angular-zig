/// IR Update Ops — All update-phase operation types for the Angular IR
///
/// Port of: compiler/src/template/pipeline/ir/src/ops/update.ts (1072 LoC)
///
/// DOD patterns:
///   - All ops as plain structs (no class hierarchy)
///   - Arena-allocated, zero-copy strings
///   - SlotHandle for slot references
///   - Contiguous OpList for cache-friendly iteration
const std = @import("std");
const ir_enums = @import("../enums.zig");
const OpKind = ir_enums.OpKind;
const BindingKind = ir_enums.BindingKind;
const create_ops = @import("create_ops.zig");
const XrefId = create_ops.XrefId;
const SlotHandle = create_ops.SlotHandle;
const ConstIndex = create_ops.ConstIndex;
const ParseSourceSpan = create_ops.ParseSourceSpan;

// ─── InterpolateText ────────────────────────────────────────

/// InterpolateTextOp — interpolate text into a text node.
pub const InterpolateTextOp = struct {
    kind: OpKind = .InterpolateText,
    xref: XrefId,
    source_span: ?ParseSourceSpan = null,
    const_indices: []const ConstIndex = &.{},
    expressions: []const u8 = "",
    security_context: ?u8 = null,
    i18n: ?u32 = null,
};

pub fn createInterpolateTextOp(xref: XrefId) InterpolateTextOp {
    return .{ .xref = xref };
}

// ─── Binding ────────────────────────────────────────────────

/// BindingOp — intermediate binding op (not yet specialized).
pub const BindingOp = struct {
    kind: OpKind = .Binding,
    xref: XrefId,
    source_span: ?ParseSourceSpan = null,
    binding_kind: BindingKind,
    name: []const u8,
    expression: ?[]const u8 = null,
    security_context: ?u8 = null,
    unit: ?[]const u8 = null,
    i18n_message: ?[]const u8 = null,
    i18n_context: ?u32 = null,
};

pub fn createBindingOp(xref: XrefId, binding_kind: BindingKind, name: []const u8) BindingOp {
    return .{ .xref = xref, .binding_kind = binding_kind, .name = name };
}

// ─── Property ───────────────────────────────────────────────

/// PropertyOp — bind an expression to a DOM property.
pub const PropertyOp = struct {
    kind: OpKind = .Property,
    xref: XrefId,
    source_span: ?ParseSourceSpan = null,
    name: []const u8,
    expression: ?[]const u8 = null,
    binding_kind: BindingKind = .Property,
    security_context: ?u8 = null,
    unit: ?[]const u8 = null,
    i18n_message: ?[]const u8 = null,
    i18n_context: ?u32 = null,
    slot: SlotHandle = .{},
};

pub fn createPropertyOp(xref: XrefId, name: []const u8) PropertyOp {
    return .{ .xref = xref, .name = name };
}

// ─── TwoWayProperty ─────────────────────────────────────────

/// TwoWayPropertyOp — two-way property binding ([(ngModel)]).
pub const TwoWayPropertyOp = struct {
    kind: OpKind = .TwoWayProperty,
    xref: XrefId,
    source_span: ?ParseSourceSpan = null,
    name: []const u8,
    expression: ?[]const u8 = null,
    binding_kind: BindingKind = .TwoWayProperty,
    slot: SlotHandle = .{},
    listener_xref: ?u32 = null,
};

pub fn createTwoWayPropertyOp(xref: XrefId, name: []const u8) TwoWayPropertyOp {
    return .{ .xref = xref, .name = name };
}

// ─── StyleProp ──────────────────────────────────────────────

/// StylePropOp — bind a style property (style.color, style.width.px).
pub const StylePropOp = struct {
    kind: OpKind = .StyleProp,
    xref: XrefId,
    source_span: ?ParseSourceSpan = null,
    name: []const u8,
    expression: ?[]const u8 = null,
    unit: ?[]const u8 = null,
    binding_kind: BindingKind = .StyleProp,
    slot: SlotHandle = .{},
};

pub fn createStylePropOp(xref: XrefId, name: []const u8) StylePropOp {
    return .{ .xref = xref, .name = name };
}

// ─── ClassProp ──────────────────────────────────────────────

/// ClassPropOp — bind a class property (class.active).
pub const ClassPropOp = struct {
    kind: OpKind = .ClassProp,
    xref: XrefId,
    source_span: ?ParseSourceSpan = null,
    name: []const u8,
    expression: ?[]const u8 = null,
    binding_kind: BindingKind = .ClassProp,
    slot: SlotHandle = .{},
};

pub fn createClassPropOp(xref: XrefId, name: []const u8) ClassPropOp {
    return .{ .xref = xref, .name = name };
}

// ─── StyleMap ───────────────────────────────────────────────

/// StyleMapOp — bind a style map (style="color: red; font-size: 12px").
pub const StyleMapOp = struct {
    kind: OpKind = .StyleMap,
    xref: XrefId,
    source_span: ?ParseSourceSpan = null,
    expression: ?[]const u8 = null,
    binding_kind: BindingKind = .StyleMap,
    slot: SlotHandle = .{},
};

pub fn createStyleMapOp(xref: XrefId) StyleMapOp {
    return .{ .xref = xref };
}

// ─── ClassMap ───────────────────────────────────────────────

/// ClassMapOp — bind a class map (class="active highlight").
pub const ClassMapOp = struct {
    kind: OpKind = .ClassMap,
    xref: XrefId,
    source_span: ?ParseSourceSpan = null,
    expression: ?[]const u8 = null,
    binding_kind: BindingKind = .ClassMap,
    slot: SlotHandle = .{},
};

pub fn createClassMapOp(xref: XrefId) ClassMapOp {
    return .{ .xref = xref };
}

// ─── Attribute ──────────────────────────────────────────────

/// AttributeOp — bind an attribute (attr.aria-label).
pub const AttributeOp = struct {
    kind: OpKind = .Attribute,
    xref: XrefId,
    source_span: ?ParseSourceSpan = null,
    name: []const u8,
    expression: ?[]const u8 = null,
    binding_kind: BindingKind = .Attribute,
    unit: ?[]const u8 = null,
    security_context: ?u8 = null,
};

pub fn createAttributeOp(xref: XrefId, name: []const u8) AttributeOp {
    return .{ .xref = xref, .name = name };
}

// ─── Advance ────────────────────────────────────────────────

/// AdvanceOp — advance the runtime's implicit slot context.
pub const AdvanceOp = struct {
    kind: OpKind = .Advance,
    xref: XrefId = 0,
    source_span: ?ParseSourceSpan = null,
    delta: u32 = 1,
};

pub fn createAdvanceOp(delta: u32) AdvanceOp {
    return .{ .delta = delta };
}

// ─── Conditional ────────────────────────────────────────────

/// ConditionalOp — conditional rendering (@if in update phase).
pub const ConditionalOp = struct {
    kind: OpKind = .Conditional,
    xref: XrefId,
    source_span: ?ParseSourceSpan = null,
    condition: ?[]const u8 = null,
    true_view: ?u32 = null,
    false_view: ?u32 = null,
    create_views: []const u32 = &.{},
    cases: []const ConditionalCase = &.{},
};

pub const ConditionalCase = struct {
    condition: ?[]const u8 = null,
    view: u32,
};

pub fn createConditionalOp(xref: XrefId) ConditionalOp {
    return .{ .xref = xref };
}

// ─── Repeater ───────────────────────────────────────────────

/// RepeaterOp — repeater (@for) in update phase.
pub const RepeaterOp = struct {
    kind: OpKind = .Repeater,
    xref: XrefId,
    source_span: ?ParseSourceSpan = null,
    track: ?[]const u8 = null,
    collection: ?[]const u8 = null,
    slot: SlotHandle = .{},
};

pub fn createRepeaterOp(xref: XrefId) RepeaterOp {
    return .{ .xref = xref };
}

// ─── AnimationBinding ───────────────────────────────────────

/// AnimationBindingOp — animation binding in update phase.
pub const AnimationBindingOp = struct {
    kind: OpKind = .AnimationBinding,
    xref: XrefId,
    source_span: ?ParseSourceSpan = null,
    name: []const u8,
    expression: ?[]const u8 = null,
    binding_kind: BindingKind = .Animation,
    slot: SlotHandle = .{},
};

pub fn createAnimationBindingOp(xref: XrefId, name: []const u8) AnimationBindingOp {
    return .{ .xref = xref, .name = name };
}

// ─── DeferWhen ──────────────────────────────────────────────

/// DeferWhenOp — defer with when condition.
pub const DeferWhenOp = struct {
    kind: OpKind = .DeferWhen,
    xref: XrefId,
    source_span: ?ParseSourceSpan = null,
    condition: ?[]const u8 = null,
    is_prefetch: bool = false,
};

pub fn createDeferWhenOp(xref: XrefId, condition: []const u8) DeferWhenOp {
    return .{ .xref = xref, .condition = condition };
}

// ─── I18nExpression ─────────────────────────────────────────

/// I18nExpressionOp — i18n expression in update phase.
pub const I18nExpressionOp = struct {
    kind: OpKind = .I18nExpression,
    xref: XrefId,
    source_span: ?ParseSourceSpan = null,
    context: u32 = 0,
    message: ?[]const u8 = null,
    expressions: []const u8 = "",
    params: []const u8 = "",
    flags: u8 = 0,
    i18n_param_resolution_time: u8 = 0,
};

pub fn createI18nExpressionOp(xref: XrefId) I18nExpressionOp {
    return .{ .xref = xref };
}

// ─── I18nApply ──────────────────────────────────────────────

/// I18nApplyOp — apply i18n translations.
pub const I18nApplyOp = struct {
    kind: OpKind = .Statement,
    xref: XrefId,
    source_span: ?ParseSourceSpan = null,
    context: u32 = 0,
};

pub fn createI18nApplyOp(xref: XrefId) I18nApplyOp {
    return .{ .xref = xref };
}

// ─── StoreLet ───────────────────────────────────────────────

/// StoreLetOp — store a @let variable value.
pub const StoreLetOp = struct {
    kind: OpKind = .StoreLet,
    xref: XrefId,
    source_span: ?ParseSourceSpan = null,
    name: []const u8,
    expression: ?[]const u8 = null,
    slot: SlotHandle = .{},
};

pub fn createStoreLetOp(xref: XrefId, name: []const u8) StoreLetOp {
    return .{ .xref = xref, .name = name };
}

// ─── Control ────────────────────────────────────────────────

/// ControlOp — control flow instruction in update phase.
pub const ControlOp = struct {
    kind: OpKind = .Conditional,
    xref: XrefId,
    source_span: ?ParseSourceSpan = null,
    target: XrefId,
};

pub fn createControlOp(target: XrefId) ControlOp {
    return .{ .target = target };
}

test "createPropertyOp" {
    const op = createPropertyOp(0, "value");
    try std.testing.expectEqualStrings("value", op.name);
    try std.testing.expectEqual(@as(u32, 0), op.xref);
}

test "createAdvanceOp" {
    const op = createAdvanceOp(3);
    try std.testing.expectEqual(@as(u32, 3), op.delta);
}
