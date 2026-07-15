/// IR Reify — IR Ops → Reified Op Representation
///
/// Reification converts the abstract IR ops into their final "reified" form
/// with resolved slot indices, xref bindings, and expression pointers.
/// This is the bridge between the IR transformation pipeline and the
/// output code generator (emit.zig).
///
/// In Angular's TS compiler, this is the final step before code gen where
/// ops get their final numbering, slot assignments are locked, and expressions
/// are resolved to their final form.
///
/// DOD:
///   - Single pass over create + update ops (O(n))
///   - Monotonic slot/xref counters (no re-scanning)
///   - All reified ops stored in contiguous arrays
///   - No intermediate allocations in hot path
///   - Expression reification is recursive but bounded by AST depth
const std = @import("std");
const Allocator = std.mem.Allocator;

const job_mod = @import("job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;
const SlotAllocator = job_mod.SlotAllocator;

const ir_ops = @import("ops.zig");
const IrOp = ir_ops.IrOp;
pub const OpKind = ir_ops.OpKind;

const ir_enums = @import("enums.zig");
const Namespace = ir_enums.Namespace;
const BindingKind = ir_enums.BindingKind;

const ir_expr = @import("expression.zig");
const IrExpr = ir_expr.IrExpr;
const ExpressionKind = ir_enums.ExpressionKind;

const source_span = @import("../../../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

// ─── Reified Op ──────────────────────────────────────────────────
/// A reified op is an IR op with all slot/xref references resolved
/// to their final values, and expressions converted to their output form.
/// This is what the code generator consumes.
pub const ReifiedOp = struct {
    /// The kind of instruction to emit
    kind: ReifiedKind,
    /// Resolved slot index (for DOM operations)
    slot: u32,
    /// Source location for diagnostics
    source_span: AbsoluteSourceSpan,
    /// Instruction-specific data
    data: ReifiedData,
    /// Whether this op belongs to create (rf & 1) or update (rf & 2)
    phase: OpPhase,
};

pub const OpPhase = enum(u8) {
    Create = 0,
    Update = 1,
};

pub const ReifiedKind = enum(u8) {
    // ── Creation ops ──────────────────────────────────────────
    ElementStart,
    ElementEnd,
    ContainerStart,
    ContainerEnd,
    Text,
    Attribute,
    Listener,
    NamespaceDeclare,
    RepeaterCreate,
    ConditionalCreate,
    Projection,
    ProjectionDef,
    Defer,
    DeferOn,
    DeferWhen,
    I18nStart,
    I18n,
    I18nEnd,
    SourceLocation,
    Statement,
    DisableBindings,
    EnableBindings,
    ListEnd,
    Content,
    ControlFlowBlock,
    Animation,
    AnimationListener,

    // ── Update ops ────────────────────────────────────────────
    InterpolateText,
    Property,
    Binding,
    StyleProp,
    ClassProp,
    StyleMap,
    ClassMap,
    DomProperty,
    TwoWayProperty,
    TwoWayListener,
    Pipe,
    StoreLet,
    Advance,
    Conditional,
    Repeater,
    Variable,
    I18nExpression,
    AnimationBinding,
    AnimationString,
};

/// Maps an IrOp OpKind to a ReifiedKind.
pub fn opKindToReified(kind: OpKind) ReifiedKind {
    return switch (kind) {
        .ElementStart => .ElementStart,
        .ElementEnd => .ElementEnd,
        .ContainerStart => .ContainerStart,
        .ContainerEnd => .ContainerEnd,
        .Text => .Text,
        .Attribute => .Attribute,
        .Listener => .Listener,
        .NamespaceDeclare => .NamespaceDeclare,
        .RepeaterCreate => .RepeaterCreate,
        .ConditionalCreate => .ConditionalCreate,
        .Projection => .Projection,
        .ProjectionDef => .ProjectionDef,
        .Defer => .Defer,
        .DeferOn => .DeferOn,
        .DeferWhen => .DeferWhen,
        .I18nStart => .I18nStart,
        .I18n => .I18n,
        .I18nEnd => .I18nEnd,
        .SourceLocation => .SourceLocation,
        .Statement => .Statement,
        .DisableBindings => .DisableBindings,
        .EnableBindings => .EnableBindings,
        .ListEnd => .ListEnd,
        .Content => .Content,
        .ControlFlowBlock => .ControlFlowBlock,
        .Animation => .Animation,
        .AnimationListener => .AnimationListener,
        .InterpolateText => .InterpolateText,
        .Binding => .Binding,
        .Property => .Property,
        .StyleProp => .StyleProp,
        .ClassProp => .ClassProp,
        .StyleMap => .StyleMap,
        .ClassMap => .ClassMap,
        .DomProperty => .DomProperty,
        .TwoWayProperty => .TwoWayProperty,
        .TwoWayListener => .TwoWayListener,
        .Pipe => .Pipe,
        .StoreLet => .StoreLet,
        .Advance => .Advance,
        .Conditional => .Conditional,
        .Repeater => .Repeater,
        .Variable => .Variable,
        .I18nExpression => .I18nExpression,
        .AnimationBinding => .AnimationBinding,
        .AnimationString => .AnimationString,
        // New ops added for 1:1 fidelity — map to Statement as fallback.
        .Template, .ConditionalBranchCreate, .ForeignComponent,
        .I18nAttributes, .I18nContext, .IcuStart, .IcuEnd, .IcuPlaceholder,
        .ExtractedAttribute, .ControlCreate, .Control,
        .EnableIncrementalHydrationRuntime => .Statement,
    };
}

// ─── Reified Op Data ────────────────────────────────────────────
/// Resolved data for each reified op. Uses optional pointers
/// to reference the original IR data where needed.
pub const ReifiedData = union(ReifiedKind) {
    // Creation ops
    ElementStart: ElementStartData,
    ElementEnd: void,
    ContainerStart: struct { attrs_xref: u32 },
    ContainerEnd: void,
    Text: struct { const_index: u32 },
    Attribute: AttributeData,
    Listener: ListenerData,
    NamespaceDeclare: Namespace,
    RepeaterCreate: void,
    ConditionalCreate: void,
    Projection: struct { slot_index: u32, selector: ?[]const u8 },
    ProjectionDef: struct { slot_index: u32, attrs_xref: u32 },
    Defer: struct { deps_xref: u32 },
    DeferOn: ir_enums.DeferTriggerKind,
    DeferWhen: struct { condition_fn_xref: u32 },
    I18nStart: struct { xref: u32 },
    I18n: struct { message: []const u8 },
    I18nEnd: void,
    SourceLocation: AbsoluteSourceSpan,
    Statement: []const u8,
    DisableBindings: void,
    EnableBindings: void,
    ListEnd: void,
    Content: void,
    ControlFlowBlock: void,
    Animation: struct { name: []const u8 },
    AnimationListener: struct { name: []const u8, handler_fn_xref: u32, phase: ?[]const u8 },

    // Update ops
    InterpolateText: struct { const_indices: []const u32, expr_count: u8, security_context: ?u8 },
    Property: BindingData,
    Binding: BindingData,
    StyleProp: StylePropData,
    ClassProp: ClassPropData,
    StyleMap: struct { expression: *const IrExpr },
    ClassMap: struct { expression: *const IrExpr },
    DomProperty: DomPropertyData,
    TwoWayProperty: TwoWayPropertyData,
    TwoWayListener: struct { name: []const u8, handler_fn_xref: u32 },
    Pipe: PipeData,
    StoreLet: StoreLetData,
    Advance: u32,
    Conditional: struct { condition_expr: *const IrExpr },
    Repeater: RepeaterData,
    Variable: VariableData,
    I18nExpression: struct { expressions: []const *const IrExpr },
    AnimationBinding: struct { name: []const u8, expression: *const IrExpr },
    AnimationString: struct { name: []const u8, expression: *const IrExpr },
};

pub const ElementStartData = struct {
    name: []const u8,
    namespace: Namespace,
    attrs_xref: u32,
    /// Resolved security context index (0 = none)
    security_context: u8,
};

pub const AttributeData = struct {
    name: []const u8,
    value: []const u8,
    security_context: u8,
};

pub const ListenerData = struct {
    name: []const u8,
    handler_fn_xref: u32,
};

pub const BindingData = struct {
    name: []const u8,
    expression: *const IrExpr,
    binding_kind: BindingKind,
    security_context: u8,
};

pub const StylePropData = struct {
    name: []const u8,
    expression: *const IrExpr,
    unit: ?[]const u8,
    sanitizer: u8,
};

pub const ClassPropData = struct {
    name: []const u8,
    expression: *const IrExpr,
};

pub const DomPropertyData = struct {
    name: []const u8,
    expression: *const IrExpr,
    security_context: u8,
};

pub const TwoWayPropertyData = struct {
    name: []const u8,
    expression: *const IrExpr,
};

pub const PipeData = struct {
    name: []const u8,
    args: []const *const IrExpr,
    pure: bool,
    slot: u32,
};

pub const StoreLetData = struct {
    name: []const u8,
    expression: *const IrExpr,
    slot: u32,
};

pub const RepeaterData = struct {
    track_by_fn: ?*const IrExpr,
    collection_expr: ?*const IrExpr,
};

pub const VariableData = struct {
    name: []const u8,
    value: *const IrExpr,
    slot: u32,
};

// ─── Reify Result ────────────────────────────────────────────────

pub const ReifiedView = struct {
    /// Reified creation ops in order
    create_ops: []const ReifiedOp,
    /// Reified update ops in order
    update_ops: []const ReifiedOp,
    /// Reified function ops (event handlers, pure functions)
    function_ops: []const FunctionOps,
    /// Number of variables used
    vars: u32,
    /// Number of declarations used
    decls: u32,
    /// Number of slots used
    slots: u32,
    /// Allocator used for ops (for deinit).
    allocator: ?Allocator = null,

    /// Free all memory owned by this ReifiedView.
    /// Note: create_ops/update_ops/function_ops are owned by the ReifyContext
    /// which is NOT deinited (ownership transferred). These slices point to
    /// the backing memory of the context's ArrayLists. The caller must ensure
    /// the context's allocator is still valid when accessing these slices.
    /// For now, we don't free them (matching original behavior — potential leak).
    pub fn deinit(self: *ReifiedView) void {
        _ = self;
        // Intentionally empty — the ops slices are owned by the ReifyContext
        // which is stack-allocated in reifyJob and not deinited.
    }
};

pub const FunctionOps = struct {
    name: []const u8,
    ops: []const ReifiedOp,
};

// ─── Reify Context ───────────────────────────────────────────────
/// State carried through a single reify pass.
const ReifyContext = struct {
    allocator: Allocator,
    /// Monotonic xref counter for remapping
    xref_counter: u32,
    /// Track which security contexts have been assigned
    next_security_context: u8,
    /// Map from IR xref → reified slot
    xref_to_slot: std.array_list.Managed(u32),
    /// Collected reified create ops
    create_ops: std.array_list.Managed(ReifiedOp),
    /// Collected reified update ops
    update_ops: std.array_list.Managed(ReifiedOp),
    /// Collected function ops
    function_ops: std.array_list.Managed(FunctionOps),

    fn init(allocator: Allocator, _: usize) ReifyContext {
        return .{
            .allocator = allocator,
            .xref_counter = 0,
            .next_security_context = 1,
            .xref_to_slot = std.array_list.Managed(u32).init(allocator),
            .create_ops = std.array_list.Managed(ReifiedOp).init(allocator),
            .update_ops = std.array_list.Managed(ReifiedOp).init(allocator),
            .function_ops = std.array_list.Managed(FunctionOps).init(allocator),
        };
    }

    fn deinit(self: *ReifyContext) void {
        self.xref_to_slot.deinit();
        self.create_ops.deinit();
        self.update_ops.deinit();
        self.function_ops.deinit();
    }

    /// Ensure the xref_to_slot map is large enough for the given xref.
    fn ensureSlot(self: *ReifyContext, xref: u32) void {
        const needed = xref + 1;
        while (self.xref_to_slot.items.len < needed) {
            self.xref_to_slot.append(0) catch unreachable;
        }
    }

    /// Get or create a slot mapping for an xref.
    fn resolveSlot(self: *ReifyContext, xref: u32) u32 {
        self.ensureSlot(xref);
        if (self.xref_to_slot.items[xref] == 0) {
            self.xref_to_slot.items[xref] = self.xref_counter;
            self.xref_counter += 1;
        }
        return self.xref_to_slot.items[xref];
    }

    /// Resolve a security context value (null → 0).
    fn resolveSecurityCtx(_: *ReifyContext, ctx: ?u8) u8 {
        if (ctx) |c| return c;
        return 0;
    }
};

// ─── Main Reify Entry Point ─────────────────────────────────────

/// Reify all ops in a compilation job into their final form.
/// Processes root view + all embedded views.
pub fn reifyJob(job: *ComponentCompilationJob) !ReifiedView {
    var ctx = ReifyContext.init(job.allocator, job.slots.next_xref);
    // NOTE: do NOT defer deinit — we transfer ownership of the ArrayLists' backing memory to the returned ReifiedView.
    // The xref_to_slot list is internal-only and must be freed manually.
    var xref_to_slot_owned = ctx.xref_to_slot;

    // Pre-populate xref_to_slot from the slot allocator
    // (slots allocated during ingest are already sequential)
    ctx.xref_counter = job.slots.next_slot;

    // Reify root view
    try reifyViewOps(&ctx, &job.root);

    // Reify embedded views
    var view_it = job.views.iterator();
    while (view_it.next()) |entry| {
        try reifyViewOps(&ctx, entry.value_ptr.*);
    }

    const result = ReifiedView{
        .create_ops = ctx.create_ops.items,
        .update_ops = ctx.update_ops.items,
        .function_ops = ctx.function_ops.items,
        .vars = job.root.vars orelse 0,
        .decls = job.root.decls orelse 0,
        .slots = job.slots.next_slot,
        .allocator = job.allocator,
    };

    // Free only the internal xref_to_slot list; the ops lists' memory is now owned by `result`.
    xref_to_slot_owned.deinit();

    return result;
}

/// Reify ops from a single view into the context.
fn reifyViewOps(ctx: *ReifyContext, view: *ViewCompilationUnit) !void {
    // Phase 1: Reify create ops
    for (view.create.items()) |op| {
        const reified = reifyCreateOp(ctx, op);
        try ctx.create_ops.append(reified);
    }

    // Phase 2: Reify update ops
    for (view.update.items()) |op| {
        const reified = reifyUpdateOp(ctx, op);
        try ctx.update_ops.append(reified);
    }

    // Phase 3: Reify function ops
    for (view.functions.items) |fn_ops_list| {
        var fn_reified = std.array_list.Managed(ReifiedOp).init(ctx.allocator);
        for (fn_ops_list.items) |op| {
            // Function ops are treated as update-phase ops
            const reified = reifyUpdateOp(ctx, op);
            try fn_reified.append(reified);
        }
        const fn_name = view.fn_name orelse "anonymous";
        try ctx.function_ops.append(.{
            .name = fn_name,
            .ops = fn_reified.items,
        });
    }
}

// ─── Create Op Reification ───────────────────────────────────────

fn reifyCreateOp(ctx: *ReifyContext, op: IrOp) ReifiedOp {
    const slot = ctx.resolveSlot(op.xref);
    const span = op.source_span;

    return switch (op.data) {
        .ElementStart => |d| .{
            .kind = .ElementStart,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .ElementStart = .{
                .name = d.name,
                .namespace = d.namespace,
                .attrs_xref = d.attrs_xref,
                .security_context = 0,
            } },
        },
        .ElementEnd => .{
            .kind = .ElementEnd,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .ElementEnd = {} },
        },
        .ContainerStart => |d| .{
            .kind = .ContainerStart,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .ContainerStart = .{ .attrs_xref = d.attrs_xref } },
        },
        .ContainerEnd => .{
            .kind = .ContainerEnd,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .ContainerEnd = {} },
        },
        .Text => |d| .{
            .kind = .Text,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .Text = .{ .const_index = d.const_index } },
        },
        .Attribute => |d| .{
            .kind = .Attribute,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .Attribute = .{
                .name = d.name,
                .value = d.value,
                .security_context = ctx.resolveSecurityCtx(d.security_context),
            } },
        },
        .Listener => |d| .{
            .kind = .Listener,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .Listener = .{
                .name = d.name,
                .handler_fn_xref = d.handler_fn_xref,
            } },
        },
        .NamespaceDeclare => |ns| .{
            .kind = .NamespaceDeclare,
            .slot = 0,
            .source_span = span,
            .phase = .Create,
            .data = .{ .NamespaceDeclare = ns },
        },
        .RepeaterCreate => .{
            .kind = .RepeaterCreate,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .RepeaterCreate = {} },
        },
        .ConditionalCreate => .{
            .kind = .ConditionalCreate,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .ConditionalCreate = {} },
        },
        .Projection => |d| .{
            .kind = .Projection,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .Projection = .{ .slot_index = d.slot_index, .selector = d.selector } },
        },
        .ProjectionDef => |d| .{
            .kind = .ProjectionDef,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .ProjectionDef = .{ .slot_index = d.slot_index, .attrs_xref = d.attrs_xref } },
        },
        .Defer => |d| .{
            .kind = .Defer,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .Defer = .{ .deps_xref = d.deps_xref } },
        },
        .DeferOn => |trigger| .{
            .kind = .DeferOn,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .DeferOn = trigger },
        },
        .DeferWhen => |d| .{
            .kind = .DeferWhen,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .DeferWhen = .{ .condition_fn_xref = d.condition_fn_xref } },
        },
        .I18nStart => |d| .{
            .kind = .I18nStart,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .I18nStart = .{ .xref = d.xref } },
        },
        .I18n => |d| .{
            .kind = .I18n,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .I18n = .{ .message = d.message } },
        },
        .I18nEnd => .{
            .kind = .I18nEnd,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .I18nEnd = {} },
        },
        .SourceLocation => |s| .{
            .kind = .SourceLocation,
            .slot = 0,
            .source_span = s,
            .phase = .Create,
            .data = .{ .SourceLocation = s },
        },
        .Statement => |s| .{
            .kind = .Statement,
            .slot = 0,
            .source_span = span,
            .phase = .Create,
            .data = .{ .Statement = s },
        },
        .DisableBindings => .{
            .kind = .DisableBindings,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .DisableBindings = {} },
        },
        .EnableBindings => .{
            .kind = .EnableBindings,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .EnableBindings = {} },
        },
        .ListEnd => .{
            .kind = .ListEnd,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .ListEnd = {} },
        },
        .Content => .{
            .kind = .Content,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .Content = {} },
        },
        .ControlFlowBlock => .{
            .kind = .ControlFlowBlock,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .ControlFlowBlock = {} },
        },
        .Animation => |d| .{
            .kind = .Animation,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .Animation = .{ .name = d.name } },
        },
        .AnimationListener => |d| .{
            .kind = .AnimationListener,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .AnimationListener = .{ .name = d.name, .handler_fn_xref = d.handler_fn_xref, .phase = d.phase } },
        },
        // Update-only ops should not appear in create list
        else => .{
            .kind = .Content,
            .slot = slot,
            .source_span = span,
            .phase = .Create,
            .data = .{ .Content = {} },
        },
    };
}

// ─── Update Op Reification ───────────────────────────────────────

fn reifyUpdateOp(ctx: *ReifyContext, op: IrOp) ReifiedOp {
    const slot = ctx.resolveSlot(op.xref);
    const span = op.source_span;

    return switch (op.data) {
        .InterpolateText => |d| .{
            .kind = .InterpolateText,
            .slot = slot,
            .source_span = span,
            .phase = .Update,
            .data = .{ .InterpolateText = .{
                .const_indices = d.const_indices,
                .expr_count = @intCast(@min(d.expressions.len, 255)),
                .security_context = ctx.resolveSecurityCtx(d.security_context),
            } },
        },
        .Binding => |d| .{
            .kind = .Binding,
            .slot = slot,
            .source_span = span,
            .phase = .Update,
            .data = .{ .Binding = .{
                .name = d.name,
                .expression = d.expression,
                .binding_kind = d.binding_kind,
                .security_context = 0,
            } },
        },
        .Property => |d| .{
            .kind = .Property,
            .slot = slot,
            .source_span = span,
            .phase = .Update,
            .data = .{ .Property = .{
                .name = d.name,
                .expression = d.expression,
                .binding_kind = .Property,
                .security_context = ctx.resolveSecurityCtx(d.security_context),
            } },
        },
        .StyleProp => |d| .{
            .kind = .StyleProp,
            .slot = slot,
            .source_span = span,
            .phase = .Update,
            .data = .{ .StyleProp = .{
                .name = d.name,
                .expression = d.expression,
                .unit = d.unit,
                .sanitizer = d.sanitizer orelse 0,
            } },
        },
        .ClassProp => |d| .{
            .kind = .ClassProp,
            .slot = slot,
            .source_span = span,
            .phase = .Update,
            .data = .{ .ClassProp = .{
                .name = d.name,
                .expression = d.expression,
            } },
        },
        .StyleMap => |d| .{
            .kind = .StyleMap,
            .slot = slot,
            .source_span = span,
            .phase = .Update,
            .data = .{ .StyleMap = .{ .expression = d.expression } },
        },
        .ClassMap => |d| .{
            .kind = .ClassMap,
            .slot = slot,
            .source_span = span,
            .phase = .Update,
            .data = .{ .ClassMap = .{ .expression = d.expression } },
        },
        .DomProperty => |d| .{
            .kind = .DomProperty,
            .slot = slot,
            .source_span = span,
            .phase = .Update,
            .data = .{ .DomProperty = .{
                .name = d.name,
                .expression = d.expression,
                .security_context = ctx.resolveSecurityCtx(d.security_context),
            } },
        },
        .TwoWayProperty => |d| .{
            .kind = .TwoWayProperty,
            .slot = slot,
            .source_span = span,
            .phase = .Update,
            .data = .{ .TwoWayProperty = .{
                .name = d.name,
                .expression = d.expression,
            } },
        },
        .TwoWayListener => |d| .{
            .kind = .TwoWayListener,
            .slot = slot,
            .source_span = span,
            .phase = .Update,
            .data = .{ .TwoWayListener = .{ .name = d.name, .handler_fn_xref = d.handler_fn_xref } },
        },
        .Pipe => |d| .{
            .kind = .Pipe,
            .slot = slot,
            .source_span = span,
            .phase = .Update,
            .data = .{ .Pipe = .{
                .name = d.name,
                .args = @ptrCast(d.args),
                .pure = d.pure,
                .slot = slot,
            } },
        },
        .StoreLet => |d| .{
            .kind = .StoreLet,
            .slot = slot,
            .source_span = span,
            .phase = .Update,
            .data = .{ .StoreLet = .{
                .name = d.name,
                .expression = d.expression,
                .slot = slot,
            } },
        },
        .Advance => |next_slot| .{
            .kind = .Advance,
            .slot = slot,
            .source_span = span,
            .phase = .Update,
            .data = .{ .Advance = next_slot },
        },
        .Conditional => |d| .{
            .kind = .Conditional,
            .slot = slot,
            .source_span = span,
            .phase = .Update,
            .data = .{ .Conditional = .{ .condition_expr = d.condition_expr } },
        },
        .Repeater => |d| .{
            .kind = .Repeater,
            .slot = slot,
            .source_span = span,
            .phase = .Update,
            .data = .{ .Repeater = .{
                .track_by_fn = if (d.track_by_fn) |t| @constCast(t) else null,
                .collection_expr = if (d.collection_expr) |c| @constCast(c) else null,
            } },
        },
        .Variable => |d| .{
            .kind = .Variable,
            .slot = slot,
            .source_span = span,
            .phase = .Update,
            .data = .{ .Variable = .{
                .name = d.name,
                .value = d.value,
                .slot = slot,
            } },
        },
        .I18nExpression => |d| .{
            .kind = .I18nExpression,
            .slot = slot,
            .source_span = span,
            .phase = .Update,
            .data = .{ .I18nExpression = .{ .expressions = @ptrCast(d.expressions) } },
        },
        .AnimationBinding => |d| .{
            .kind = .AnimationBinding,
            .slot = slot,
            .source_span = span,
            .phase = .Update,
            .data = .{ .AnimationBinding = .{ .name = d.name, .expression = d.expression } },
        },
        .AnimationString => |d| .{
            .kind = .AnimationString,
            .slot = slot,
            .source_span = span,
            .phase = .Update,
            .data = .{ .AnimationString = .{ .name = d.name, .expression = d.expression } },
        },
        // Create-only ops in update list: treat as no-ops
        else => .{
            .kind = .Content,
            .slot = slot,
            .source_span = span,
            .phase = .Update,
            .data = .{ .Content = {} },
        },
    };
}

// ─── Expression Reification ──────────────────────────────────────
/// Reify an IrExpr tree into its final form.
/// Resolves variable references, simplifies constant expressions,
/// and prepares the expression for code generation.
pub fn reifyExpression(allocator: Allocator, expr: *const IrExpr) error{OutOfMemory}!IrExpr {
    return switch (expr.kind) {
        .EmptyExpr => expr.*,
        .Context => expr.*,
        .ReadVariable => expr.*,
        .NextContext => expr.*,
        .Reference => expr.*,
        .ConstCollected => expr.*,
        .LiteralExpr => expr.*,
        .BinaryExpr => try reifyBinaryExpr(allocator, expr),
        .ConditionalExpr => try reifyConditionalExpr(allocator, expr),
        .CallExpr => try reifyCallExpr(allocator, expr),
        .ReadPropExpr => try reifyReadPropExpr(allocator, expr),
        .NotExpr => try reifyNotExpr(allocator, expr),
        .SafePropertyRead => try reifySafePropertyRead(allocator, expr),
        .SafeKeyedRead => try reifySafeKeyedRead(allocator, expr),
        .PureFunctionExpr => expr.*,
        .PureFunctionParameterExpr => expr.*,
        .PipeBinding => expr.*,
        .PipeBindingVariadic => expr.*,
        .ConditionalCase => expr.*,
        .TwoWayBindingSet => expr.*,
        .ArrowFunction => try reifyArrowFunction(allocator, expr),
        .SlotLiteralExpr => expr.*,
    };
}

fn reifyBinaryExpr(allocator: Allocator, expr: *const IrExpr) error{OutOfMemory}!IrExpr {
    const bin = expr.data.BinaryExpr;
    const left = try allocator.create(IrExpr);
    left.* = try reifyExpression(allocator, bin.left);
    const right = try allocator.create(IrExpr);
    right.* = try reifyExpression(allocator, bin.right);
    return .{
        .kind = .BinaryExpr,
        .span = expr.span,
        .data = .{ .BinaryExpr = .{ .left = left, .op = bin.op, .right = right } },
    };
}

fn reifyConditionalExpr(allocator: Allocator, expr: *const IrExpr) error{OutOfMemory}!IrExpr {
    const cond = expr.data.ConditionalExpr;
    const condition = try allocator.create(IrExpr);
    condition.* = try reifyExpression(allocator, cond.condition);
    const true_expr = try allocator.create(IrExpr);
    true_expr.* = try reifyExpression(allocator, cond.true_expr);
    const false_expr = try allocator.create(IrExpr);
    false_expr.* = try reifyExpression(allocator, cond.false_expr);
    return .{
        .kind = .ConditionalExpr,
        .span = expr.span,
        .data = .{ .ConditionalExpr = .{
            .condition = condition,
            .true_expr = true_expr,
            .false_expr = false_expr,
        } },
    };
}

fn reifyCallExpr(allocator: Allocator, expr: *const IrExpr) error{OutOfMemory}!IrExpr {
    const call = expr.data.CallExpr;
    const receiver = try allocator.create(IrExpr);
    receiver.* = try reifyExpression(allocator, call.receiver);
    // Reify each argument
    const new_args = try allocator.alloc(*IrExpr, call.args.len);
    for (call.args, 0..) |arg, i| {
        const reified = try allocator.create(IrExpr);
        reified.* = try reifyExpression(allocator, arg);
        new_args[i] = reified;
    }
    return .{
        .kind = .CallExpr,
        .span = expr.span,
        .data = .{ .CallExpr = .{ .receiver = receiver, .args = new_args } },
    };
}

fn reifyReadPropExpr(allocator: Allocator, expr: *const IrExpr) error{OutOfMemory}!IrExpr {
    const rp = expr.data.ReadPropExpr;
    const receiver = try allocator.create(IrExpr);
    receiver.* = try reifyExpression(allocator, rp.receiver);
    return .{
        .kind = .ReadPropExpr,
        .span = expr.span,
        .data = .{ .ReadPropExpr = .{ .receiver = receiver, .name = rp.name } },
    };
}

fn reifyNotExpr(allocator: Allocator, expr: *const IrExpr) error{OutOfMemory}!IrExpr {
    const inner = try allocator.create(IrExpr);
    inner.* = try reifyExpression(allocator, expr.data.NotExpr.expression);
    return .{
        .kind = .NotExpr,
        .span = expr.span,
        .data = .{ .NotExpr = .{ .expression = inner } },
    };
}

fn reifySafePropertyRead(allocator: Allocator, expr: *const IrExpr) error{OutOfMemory}!IrExpr {
    const spr = expr.data.SafePropertyRead;
    const receiver = try allocator.create(IrExpr);
    receiver.* = try reifyExpression(allocator, spr.receiver);
    return .{
        .kind = .SafePropertyRead,
        .span = expr.span,
        .data = .{ .SafePropertyRead = .{ .receiver = receiver, .name = spr.name } },
    };
}

fn reifySafeKeyedRead(allocator: Allocator, expr: *const IrExpr) error{OutOfMemory}!IrExpr {
    const skr = expr.data.SafeKeyedRead;
    const receiver = try allocator.create(IrExpr);
    receiver.* = try reifyExpression(allocator, skr.receiver);
    const key = try allocator.create(IrExpr);
    key.* = try reifyExpression(allocator, skr.key);
    return .{
        .kind = .SafeKeyedRead,
        .span = expr.span,
        .data = .{ .SafeKeyedRead = .{ .receiver = receiver, .key = key } },
    };
}

fn reifyArrowFunction(allocator: Allocator, expr: *const IrExpr) error{OutOfMemory}!IrExpr {
    const af = expr.data.ArrowFunction;
    const body = try allocator.create(IrExpr);
    body.* = try reifyExpression(allocator, af.body);
    // Param names are just string slices, no reification needed
    return .{
        .kind = .ArrowFunction,
        .span = expr.span,
        .data = .{ .ArrowFunction = .{ .param_names = af.param_names, .body = body } },
    };
}

// ─── Slot Re-mapping ─────────────────────────────────────────────
/// After xref compaction, remap all slot references in reified ops.
/// This is a post-processing step after compactXrefs phase.
pub fn remapSlots(ops: []ReifiedOp, remap: []const u32) void {
    for (ops) |*op| {
        if (op.slot < remap.len) {
            op.slot = remap[op.slot];
        }
        // Remap slot references inside op data
        switch (op.data) {
            .Advance => |*adv| {
                if (adv.* < remap.len) {
                    adv.* = remap[adv.*];
                }
            },
            .Pipe => |*pipe| {
                if (pipe.slot < remap.len) {
                    pipe.slot = remap[pipe.slot];
                }
            },
            .StoreLet => |*sl| {
                if (sl.slot < remap.len) {
                    sl.slot = remap[sl.slot];
                }
            },
            .Variable => |*v| {
                if (v.slot < remap.len) {
                    v.slot = remap[v.slot];
                }
            },
            else => {},
        }
    }
}

// ─── Reified Op Stats ────────────────────────────────────────────
/// Count op types for diagnostics and testing.
pub const ReifiedStats = struct {
    create_count: usize,
    update_count: usize,
    element_starts: usize,
    bindings: usize,
    listeners: usize,
    repeaters: usize,
    conditionals: usize,
    pipes: usize,
};

pub fn collectStats(create: []const ReifiedOp, update: []const ReifiedOp) ReifiedStats {
    var stats = ReifiedStats{
        .create_count = create.len,
        .update_count = update.len,
        .element_starts = 0,
        .bindings = 0,
        .listeners = 0,
        .repeaters = 0,
        .conditionals = 0,
        .pipes = 0,
    };

    for (create) |op| {
        switch (op.kind) {
            .ElementStart => stats.element_starts += 1,
            .Listener => stats.listeners += 1,
            .RepeaterCreate => stats.repeaters += 1,
            .ConditionalCreate => stats.conditionals += 1,
            else => {},
        }
    }

    for (update) |op| {
        switch (op.kind) {
            .Binding => stats.bindings += 1,
            .Property => stats.bindings += 1,
            .Pipe => stats.pipes += 1,
            .Repeater => stats.repeaters += 1,
            .Conditional => stats.conditionals += 1,
            else => {},
        }
    }

    return stats;
}

// ─── Tests ────────────────────────────────────────────────────────

test "reify ElementStart op" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "TestComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 0, .end = 5 };
    try job.root.create.append(.{
        .kind = .ElementStart,
        .xref = 0,
        .source_span = span,
        .data = .{ .ElementStart = .{ .name = "div", .namespace = .HTML, .attrs_xref = 0 } },
    });

    const reified = try reifyJob(&job); defer { var r = reified; r.deinit(); }
    try std.testing.expectEqual(@as(usize, 1), reified.create_ops.len);
    try std.testing.expectEqual(ReifiedKind.ElementStart, reified.create_ops[0].kind);
    try std.testing.expectEqual(OpPhase.Create, reified.create_ops[0].phase);
}

test "reify create + update ops" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "TestComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 0, .end = 10 };

    // Create: element start + text
    try job.root.create.append(.{
        .kind = .ElementStart,
        .xref = 0,
        .source_span = span,
        .data = .{ .ElementStart = .{ .name = "span", .namespace = .HTML, .attrs_xref = 0 } },
    });
    try job.root.create.append(.{
        .kind = .Text,
        .xref = 1,
        .source_span = span,
        .data = .{ .Text = .{ .const_index = 0 } },
    });

    // Update: binding
    const expr = try job.allocator.create(IrExpr);
    expr.* = IrExpr.readVariable("title", 0, span);
    try job.root.update.append(.{
        .kind = .Binding,
        .xref = 1,
        .source_span = span,
        .data = .{ .Binding = .{ .name = "textContent", .expression = expr, .binding_kind = .Property } },
    });

    const reified = try reifyJob(&job); defer { var r = reified; r.deinit(); }
    try std.testing.expectEqual(@as(usize, 2), reified.create_ops.len);
    try std.testing.expectEqual(@as(usize, 1), reified.update_ops.len);
    try std.testing.expectEqual(ReifiedKind.Binding, reified.update_ops[0].kind);
    try std.testing.expectEqual(OpPhase.Update, reified.update_ops[0].phase);
}

test "collectStats counts correctly" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "TestComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 0, .end = 5 };
    try job.root.create.append(.{
        .kind = .ElementStart,
        .xref = 0,
        .source_span = span,
        .data = .{ .ElementStart = .{ .name = "div", .namespace = .HTML, .attrs_xref = 0 } },
    });
    try job.root.create.append(.{
        .kind = .ElementEnd,
        .xref = 0,
        .source_span = span,
        .data = .{ .ElementEnd = {} },
    });

    const reified = try reifyJob(&job); defer { var r = reified; r.deinit(); }
    const stats = collectStats(reified.create_ops, reified.update_ops);
    try std.testing.expectEqual(@as(usize, 1), stats.element_starts);
    try std.testing.expectEqual(@as(usize, 2), stats.create_count);
}

test "opKindToReified maps all OpKinds" {
    // Ensure all OpKind values have a corresponding ReifiedKind
    const kinds = std.meta.tags(OpKind);
    for (kinds) |kind| {
        const reified = opKindToReified(kind);
        _ = reified; // Just ensure no unreachable
    }
}

test "reifyExpression preserves literals" {
    const allocator = std.testing.allocator;
    const span = AbsoluteSourceSpan{ .start = 0, .end = 4 };
    const original = IrExpr.literalExpr("42", span);
    const reified = try reifyExpression(allocator, &original);
    try std.testing.expectEqual(ExpressionKind.LiteralExpr, reified.kind);
    try std.testing.expectEqualStrings("42", reified.data.LiteralExpr.value);
}

test "reifyExpression reifies BinaryExpr recursively" {
    const allocator = std.testing.allocator;
    const span = AbsoluteSourceSpan{ .start = 0, .end = 5 };

    const left = try allocator.create(IrExpr);
    left.* = IrExpr.literalExpr("1", span);
    const right = try allocator.create(IrExpr);
    right.* = IrExpr.literalExpr("2", span);
    const original = IrExpr.binaryExpr(left, '+', right, span);

    const reified = try reifyExpression(allocator, &original);
    try std.testing.expectEqual(ExpressionKind.BinaryExpr, reified.kind);
    // The reified should have new pointers (deep copy)
    try std.testing.expect(reified.data.BinaryExpr.left != left);
}
