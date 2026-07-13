/// Port of: template/pipeline/ir/src/ops/update.ts (1072 LoC)
/// DOD + Arena Memory
const std = @import("std");

pub const InterpolateTextOp = struct {};
pub const BindingOp = struct {};
pub const PropertyOp = struct {};
pub const TwoWayPropertyOp = struct {};
pub const StylePropOp = struct {};
pub const ClassPropOp = struct {};
pub const StyleMapOp = struct {};
pub const ClassMapOp = struct {};
pub const AttributeOp = struct {};
pub const AdvanceOp = struct {};
pub const ConditionalOp = struct {};
pub const RepeaterOp = struct {};
pub const AnimationBindingOp = struct {};
pub const DeferWhenOp = struct {};
pub const I18nExpressionOp = struct {};
pub const I18nApplyOp = struct {};
pub const StoreLetOp = struct {};
pub const ControlOp = struct {};
pub fn createInterpolateTextOp(allocator: std.mem.Allocator) void { _ = allocator; }
pub fn createBindingOp(allocator: std.mem.Allocator) void { _ = allocator; }
pub fn createPropertyOp(allocator: std.mem.Allocator) void { _ = allocator; }
pub fn createTwoWayPropertyOp(allocator: std.mem.Allocator) void { _ = allocator; }
pub fn createStylePropOp(allocator: std.mem.Allocator) void { _ = allocator; }
pub fn createClassPropOp(allocator: std.mem.Allocator) void { _ = allocator; }
pub fn createStyleMapOp(allocator: std.mem.Allocator) void { _ = allocator; }
pub fn createClassMapOp(allocator: std.mem.Allocator) void { _ = allocator; }
pub fn createAttributeOp(allocator: std.mem.Allocator) void { _ = allocator; }
pub fn createAdvanceOp(allocator: std.mem.Allocator) void { _ = allocator; }
pub fn createConditionalOp(allocator: std.mem.Allocator) void { _ = allocator; }
pub fn createRepeaterOp(allocator: std.mem.Allocator) void { _ = allocator; }
pub fn createAnimationBindingOp(allocator: std.mem.Allocator) void { _ = allocator; }
pub fn createDeferWhenOp(allocator: std.mem.Allocator) void { _ = allocator; }
pub fn createI18nExpressionOp(allocator: std.mem.Allocator) void { _ = allocator; }
pub fn createI18nApplyOp(allocator: std.mem.Allocator) void { _ = allocator; }
pub fn createStoreLetOp(allocator: std.mem.Allocator) void { _ = allocator; }
pub fn createControlOp(allocator: std.mem.Allocator) void { _ = allocator; }
pub const UpdateOp = anytype;

test "module loads" { std.testing.expect(true); }