/// IR Operations — The heart of the compilation pipeline
///
/// Each op is a single instruction in the IR.
/// Creation ops build the DOM tree, Update ops apply bindings.
///
/// DOD: Ops stored in contiguous OpList arrays.
/// Two separate lists (create/update) = better cache locality
/// during each phase of rendering.
const std = @import("std");
const enums = @import("enums.zig");
pub const OpKind = enums.OpKind;
pub const Namespace = enums.Namespace;
const BindingKind = enums.BindingKind;
const DeferTriggerKind = enums.DeferTriggerKind;
const expression_mod = @import("expression.zig");
const IrExpr = expression_mod.IrExpr;
const source_span = @import("../../../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

// ─── IR Operation ────────────────────────────────────────────

pub const IrOp = struct {
    kind: OpKind,
    /// Slot xref for creation ops, variable ref for update ops
    xref: u32,
    source_span: AbsoluteSourceSpan,
    data: OpData,
};

// ─── Op Data (Tagged Union) ──────────────────────────────────
/// Each variant corresponds to an OpKind value.
/// The Zig compiler ensures we handle all cases.
pub const OpData = union(OpKind) {
    // ── Creation Ops ─────────────────────────────────────────
    ElementStart: struct {
        name: []const u8,
        namespace: Namespace,
        attrs_xref: u32,
    },
    ElementEnd: void,
    ContainerStart: struct {
        attrs_xref: u32,
    },
    ContainerEnd: void,
    Text: struct {
        const_index: u32,
    },
    Attribute: struct {
        name: []const u8,
        value: []const u8,
        security_context: ?u8,
    },
    Projection: struct {
        slot_index: u32,
        selector: ?[]const u8,
    },
    ProjectionDef: struct {
        slot_index: u32,
        attrs_xref: u32,
    },
    Listener: struct {
        name: []const u8,
        handler_fn_xref: u32,
    },
    NamespaceDeclare: Namespace,
    RepeaterCreate: void,
    ConditionalCreate: void,
    Animation: struct {
        name: []const u8,
        expr: *IrExpr,
    },
    AnimationListener: struct {
        name: []const u8,
        handler_fn_xref: u32,
        phase: ?[]const u8,
    },
    Defer: struct {
        deps_xref: u32,
    },
    DeferOn: DeferTriggerKind,
    DeferWhen: struct {
        condition_fn_xref: u32,
    },
    I18nStart: struct {
        xref: u32,
    },
    I18n: struct {
        message: []const u8,
    },
    I18nEnd: void,
    Statement: []const u8,
    SourceLocation: AbsoluteSourceSpan,
    ListEnd: void,
    Content: void,
    DisableBindings: void,
    EnableBindings: void,
    ControlFlowBlock: void,

    // ── Update Ops ───────────────────────────────────────────
    InterpolateText: struct {
        const_indices: []const u32,
        expressions: []const *IrExpr,
        security_context: ?u8,
    },
    Binding: struct {
        name: []const u8,
        expression: *IrExpr,
        binding_kind: BindingKind,
    },
    Property: struct {
        name: []const u8,
        expression: *IrExpr,
        security_context: ?u8,
    },
    StyleProp: struct {
        name: []const u8,
        expression: *IrExpr,
        unit: ?[]const u8,
        sanitizer: ?u8,
    },
    ClassProp: struct {
        name: []const u8,
        expression: *IrExpr,
    },
    StyleMap: struct {
        expression: *IrExpr,
    },
    ClassMap: struct {
        expression: *IrExpr,
    },
    DomProperty: struct {
        name: []const u8,
        expression: *IrExpr,
        security_context: ?u8,
    },
    TwoWayProperty: struct {
        name: []const u8,
        expression: *IrExpr,
    },
    TwoWayListener: struct {
        name: []const u8,
        handler_fn_xref: u32,
    },
    Pipe: struct {
        name: []const u8,
        args: []const *IrExpr,
        pure: bool,
    },
    StoreLet: struct {
        name: []const u8,
        expression: *IrExpr,
    },
    Advance: u32,
    Conditional: struct {
        condition_expr: *IrExpr,
    },
    Repeater: struct {
        track_by_fn: ?*IrExpr,
        collection_expr: ?*IrExpr,
    },
    Variable: struct {
        name: []const u8,
        value: *IrExpr,
    },
    I18nExpression: struct {
        expressions: []const *IrExpr,
    },
    AnimationBinding: struct {
        name: []const u8,
        expression: *IrExpr,
    },
    AnimationString: struct {
        name: []const u8,
        expression: *IrExpr,
    },
};

// ─── Op List ──────────────────────────────────────────────────
/// Contiguous array of ops — DOD pattern for cache-friendly iteration.
/// Separate create/update lists = phase-specific sequential access.
pub fn OpList(comptime T: type) type {
    return struct {
        ops: std.array_list.Managed(T),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{ .ops = std.array_list.Managed(T).init(allocator), .allocator = allocator };
        }

        pub fn deinit(self: *@This()) void {
            self.ops.deinit();
        }

        pub fn append(self: *@This(), op: T) !void {
            try self.ops.append(op);
        }

        pub fn items(self: *const @This()) []const T {
            return self.ops.items;
        }

        pub fn len(self: *const @This()) usize {
            return self.ops.items.len;
        }

        pub fn clear(self: *@This()) void {
            self.ops.clearRetainingCapacity();
        }
    };
}

pub const CreateOpList = OpList(IrOp);
pub const UpdateOpList = OpList(IrOp);

// ─── Trait System (comptime) ──────────────────────────────────
/// Op traits let phases query capabilities of ops without switching.
/// comptime fn generates a lookup table at compile time.
pub const OpTrait = enum {
    is_element_start,
    is_element_end,
    has_name,
    has_expression,
    is_conditional,
    is_listener,
    is_binding,
    is_textual,
};

/// comptime: build a trait table as a packed bits struct per OpKind.
/// Each OpKind gets a u16 where each bit = a trait.
pub fn hasTrait(kind: OpKind, trait: OpTrait) bool {
    const traits = comptime blk: {
        // Compute table size from max enum value
        var max_val: u16 = 0;
        for (@typeInfo(OpKind).@"enum".fields) |f| {
            if (f.value > max_val) max_val = f.value;
        }
        var table: [max_val + 1]u16 = [_]u16{0} ** (max_val + 1);
        const fields = @typeInfo(OpKind).@"enum".fields;
        for (fields) |f| {
            const k: OpKind = @enumFromInt(f.value);
            var bits: u16 = 0;
            switch (k) {
                .ElementStart => {
                    bits |= @as(u16, 1) << @intFromEnum(OpTrait.is_element_start);
                    bits |= @as(u16, 1) << @intFromEnum(OpTrait.has_name);
                },
                .ElementEnd => {
                    bits |= @as(u16, 1) << @intFromEnum(OpTrait.is_element_end);
                },
                .Binding, .Property, .StyleProp, .ClassProp, .DomProperty => {
                    bits |= @as(u16, 1) << @intFromEnum(OpTrait.has_name);
                    bits |= @as(u16, 1) << @intFromEnum(OpTrait.has_expression);
                    bits |= @as(u16, 1) << @intFromEnum(OpTrait.is_binding);
                },
                .Listener => {
                    bits |= @as(u16, 1) << @intFromEnum(OpTrait.is_listener);
                    bits |= @as(u16, 1) << @intFromEnum(OpTrait.has_name);
                },
                .Text, .InterpolateText => {
                    bits |= @as(u16, 1) << @intFromEnum(OpTrait.is_textual);
                },
                .ConditionalCreate, .Conditional => {
                    bits |= @as(u16, 1) << @intFromEnum(OpTrait.is_conditional);
                },
                else => {},
            }
            table[@intFromEnum(k)] = bits;
        }
        break :blk table;
    };

    const bit = @as(u16, 1) << @intFromEnum(trait);
    const idx = @intFromEnum(kind);
    if (idx >= traits.len) return false;
    return (traits[idx] & bit) != 0;
}

// ─── Tests ────────────────────────────────────────────────────

test "op trait system" {
    try std.testing.expect(hasTrait(.ElementStart, .is_element_start));
    try std.testing.expect(hasTrait(.ElementStart, .has_name));
    try std.testing.expect(!hasTrait(.ElementStart, .is_listener));

    try std.testing.expect(hasTrait(.Binding, .is_binding));
    try std.testing.expect(hasTrait(.Binding, .has_expression));

    try std.testing.expect(hasTrait(.Text, .is_textual));
    try std.testing.expect(hasTrait(.Listener, .is_listener));
    try std.testing.expect(hasTrait(.Conditional, .is_conditional));
}

test "OpList basic operations" {
    const allocator = std.testing.allocator;
    var list = CreateOpList.init(allocator);
    defer list.deinit();

    const span = AbsoluteSourceSpan{ .start = 0, .end = 5 };
    try list.append(.{
        .kind = .ElementStart,
        .xref = 0,
        .source_span = span,
        .data = .{ .ElementStart = .{
            .name = "div",
            .namespace = .HTML,
            .attrs_xref = 0,
        } },
    });
    try list.append(.{
        .kind = .Text,
        .xref = 1,
        .source_span = span,
        .data = .{ .Text = .{ .const_index = 0 } },
    });
    try list.append(.{
        .kind = .ElementEnd,
        .xref = 0,
        .source_span = span,
        .data = .{ .ElementEnd = {} },
    });

    try std.testing.expectEqual(@as(usize, 3), list.len());
}

test "IrOp size" {
    comptime {}
}
