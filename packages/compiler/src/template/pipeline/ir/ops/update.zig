/// IR Update Ops — All update-phase operation types for the Angular IR
///
/// Port of: template/pipeline/ir/src/ops/update.ts (1072 LoC)
///
/// This file defines all update-phase operation types. Each op is a plain
/// struct with a kind discriminant and optional data. The operations are:
///   - Text: InterpolateText
///   - Binding: Binding, Property, TwoWayProperty, Attribute
///   - Style: StyleProp, ClassProp, StyleMap, ClassMap
///   - Control: Advance, Conditional, Repeater, Control
///   - Animation: AnimationBinding
///   - Defer: DeferWhen
///   - i18n: I18nExpression, I18nApply
///   - Let: StoreLet
const std = @import("std");
const update_ops = @import("../update_ops.zig");
const ir_enums = @import("../enums.zig");

/// Re-export types from update_ops.zig.
pub const Interpolation = update_ops.Interpolation;
pub const InterpolateTextOp = update_ops.InterpolateTextOp;
pub const BindingOp = update_ops.BindingOp;
pub const PropertyOp = update_ops.PropertyOp;
pub const TwoWayPropertyOp = update_ops.TwoWayPropertyOp;
pub const StylePropOp = update_ops.StylePropOp;
pub const ClassPropOp = update_ops.ClassPropOp;
pub const StyleMapOp = update_ops.StyleMapOp;
pub const ClassMapOp = update_ops.ClassMapOp;
pub const AttributeOp = update_ops.AttributeOp;
pub const AdvanceOp = update_ops.AdvanceOp;
pub const ConditionalOp = update_ops.ConditionalOp;
pub const RepeaterOp = update_ops.RepeaterOp;
pub const AnimationBindingOp = update_ops.AnimationBindingOp;
pub const DeferWhenOp = update_ops.DeferWhenOp;
pub const I18nExpressionOp = update_ops.I18nExpressionOp;
pub const I18nApplyOp = update_ops.I18nApplyOp;
pub const StoreLetOp = update_ops.StoreLetOp;
pub const ControlOp = update_ops.ControlOp;

/// Re-export factory functions from update_ops.zig.
pub const createInterpolateTextOp = update_ops.createInterpolateTextOp;
pub const createBindingOp = update_ops.createBindingOp;
pub const createAdvanceOp = update_ops.createAdvanceOp;
pub const createConditionalOp = update_ops.createConditionalOp;
pub const createRepeaterOp = update_ops.createRepeaterOp;

/// UpdateOp type alias.
pub const UpdateOp = update_ops.UpdateOp;

/// UpdateOpKind — the kind of an update-phase operation.
pub const UpdateOpKind = ir_enums.OpKind;

/// Check if an op kind is an update-phase op.
pub fn isUpdateOp(kind: UpdateOpKind) bool {
    return ir_enums.isUpdateOp(kind);
}

/// Check if an op kind is a binding op (Property, Binding, StyleProp, etc.).
pub fn isBindingOp(kind: UpdateOpKind) bool {
    return switch (kind) {
        .Binding, .Property, .StyleProp, .ClassProp, .StyleMap, .ClassMap, .DomProperty, .TwoWayProperty, .Attribute => true,
        else => false,
    };
}

/// Check if an op kind is an i18n update op.
pub fn isI18nUpdateOp(kind: UpdateOpKind) bool {
    return switch (kind) {
        .I18nExpression => true,
        else => false,
    };
}

// ─── Tests ──────────────────────────────────────────────────

test "isUpdateOp" {
    try std.testing.expect(isUpdateOp(.Property));
    try std.testing.expect(isUpdateOp(.Binding));
    try std.testing.expect(isUpdateOp(.InterpolateText));
    try std.testing.expect(isUpdateOp(.Conditional));
    try std.testing.expect(!isUpdateOp(.ElementStart));
    try std.testing.expect(!isUpdateOp(.Text));
}

test "isBindingOp" {
    try std.testing.expect(isBindingOp(.Property));
    try std.testing.expect(isBindingOp(.Binding));
    try std.testing.expect(isBindingOp(.StyleProp));
    try std.testing.expect(isBindingOp(.ClassProp));
    try std.testing.expect(isBindingOp(.TwoWayProperty));
    try std.testing.expect(!isBindingOp(.Conditional));
    try std.testing.expect(!isBindingOp(.Advance));
}

test "isI18nUpdateOp" {
    try std.testing.expect(isI18nUpdateOp(.I18nExpression));
    try std.testing.expect(!isI18nUpdateOp(.Property));
    try std.testing.expect(!isI18nUpdateOp(.Binding));
}
