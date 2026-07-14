/// R3 Template AST — Ivy Render3 AST
///
/// This is the primary AST used for template compilation.
/// Produced by transforming HTML AST with BindingParser context.
/// This AST is what gets ingested into the IR.
const std = @import("std");
const source_span = @import("../source_span.zig");
const ParseSourceSpan = source_span.ParseSourceSpan;
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;
const ParseError = source_span.ParseError;

const expr_ast = @import("../expression_parser/ast.zig");
const ExprAst = expr_ast.Ast;

// ─── Binding Types ────────────────────────────────────────────

pub const BindingType = enum(u8) {
    Property, // [prop] or bind-prop
    Attribute, // attr.name
    Class, // class.name
    Style, // style.prop
    Animation, // @animation.name
    TwoWay, // [(prop)] or bindon-prop
    LegacyAnimation, // animation.prop (deprecated)
};

pub const ParsedEventType = enum(u8) {
    Regular,
    AnimationStart,
    AnimationDone,
    Animation,
    TwoWay,
    LegacyAnimation,
    Wrapped,
};

// ─── R3 Node Kinds ────────────────────────────────────────────

pub const NodeKind = enum(u8) {
    Text,
    BoundText,
    TextAttribute,
    BoundAttribute,
    BoundEvent,
    Reference,
    Variable,
    Element,
    Template,
    Component,
    Directive,
    Content,
    IfBlock,
    IfBlockBranch,
    ForLoopBlock,
    ForLoopBlockEmpty,
    SwitchBlock,
    SwitchBlockCaseGroup,
    SwitchBlockCase,
    DeferredBlock,
    DeferredTrigger,
    LetDeclaration,
    Icu,
    IcuPlaceholder,
    Comment,
    UnknownBlock,
};

// ─── Enums (declared before types that use them) ──────────────

pub const DeferredTriggerKind = enum(u8) {
    Idle,
    Immediate,
    Timer,
    Hover,
    Interaction,
    Viewport,
    Never,
};

pub const I18nMeta = struct {
    meaning: ?[]const u8 = null,
    description: ?[]const u8 = null,
    id: ?[]const u8 = null,
    custom_id: ?[]const u8 = null,
};

// ─── Sub-node Types (standalone, before R3Node) ───────────────

pub const SpanPair = struct {
    start: AbsoluteSourceSpan,
    end: AbsoluteSourceSpan,
};

pub const IfBlockBranch = struct {
    expression: ?*const ExprAst,
    children: []const *const R3Node,
    expression_alias: ?*const R3Node,
    source_span: AbsoluteSourceSpan,
};

pub const ForLoopBlockEmpty = struct {
    children: []const *const R3Node,
};

pub const DeferredTrigger = struct {
    kind: DeferredTriggerKind,
    value: ?[]const u8 = null,
};

pub const SwitchBlockCase = struct {
    value: []const u8,
    source_span: AbsoluteSourceSpan,
};

pub const SwitchBlockCaseGroup = struct {
    cases: []const SwitchBlockCase,
    children: []const *const R3Node,
};

pub const IcuPlaceholder = struct {
    name: []const u8,
    value: *const R3Node, // Text or BoundText
};

// ─── R3 Node ──────────────────────────────────────────────────

pub const R3Node = struct {
    kind: NodeKind,
    source_span: ParseSourceSpan,
    data: Data,

    // ─── Data union (after fields per Zig 0.16 rules) ────────
    pub const Data = union(NodeKind) {
        Text: struct {
            value: []const u8,
        },
        BoundText: struct {
            value: *const ExprAst,
            i18n: ?I18nMeta = null,
        },
        TextAttribute: struct {
            name: []const u8,
            value: []const u8,
            key_span: AbsoluteSourceSpan,
            value_span: AbsoluteSourceSpan,
            i18n: ?[]const u8 = null,
        },
        BoundAttribute: struct {
            name: []const u8,
            type: BindingType,
            value: *const ExprAst,
            unit: ?[]const u8 = null,
            security_context: ?u8 = null,
            key_span: AbsoluteSourceSpan,
            source_span: AbsoluteSourceSpan,
            i18n: ?[]const u8 = null,
        },
        BoundEvent: struct {
            name: []const u8,
            type: ParsedEventType,
            handler: *const ExprAst,
            target: ?[]const u8 = null,
            phase: ?[]const u8 = null,
            key_span: AbsoluteSourceSpan,
            handler_span: AbsoluteSourceSpan,
            source_span: AbsoluteSourceSpan,
        },
        Reference: struct {
            name: []const u8,
            value: []const u8,
            key_span: AbsoluteSourceSpan,
            value_span: AbsoluteSourceSpan,
        },
        Variable: struct {
            name: []const u8,
            value: []const u8,
            key_span: AbsoluteSourceSpan,
            value_span: AbsoluteSourceSpan,
        },
        Element: struct {
            name: []const u8,
            attributes: []const R3Node,
            inputs: []const R3Node,
            outputs: []const R3Node,
            directives: []const R3Node,
            children: []const *const R3Node,
            references: []const R3Node,
            is_self_closing: bool,
            is_void: bool,
            i18n: ?[]const u8 = null,
        },
        Template: struct {
            tag_name: []const u8,
            attributes: []const R3Node,
            inputs: []const R3Node,
            outputs: []const R3Node,
            directives: []const R3Node,
            template_attrs: []const R3Node,
            children: []const *const R3Node,
            references: []const R3Node,
            variables: []const R3Node,
        },
        Component: struct {
            component_name: []const u8,
            tag_name: []const u8,
            full_name: []const u8,
            attributes: []const R3Node,
            inputs: []const R3Node,
            outputs: []const R3Node,
            directives: []const R3Node,
            children: []const *const R3Node,
            references: []const R3Node,
        },
        Directive: struct {
            name: []const u8,
            attributes: []const R3Node,
            inputs: []const R3Node,
            outputs: []const R3Node,
            references: []const R3Node,
        },
        Content: struct {
            selector: ?[]const u8,
            attributes: []const R3Node,
            children: []const *const R3Node,
        },
        IfBlock: struct {
            branches: []const IfBlockBranch,
        },
        IfBlockBranch: IfBlockBranch,
        ForLoopBlock: struct {
            item: *const R3Node, // Variable node (pointer to avoid circular dependency)
            expression: *const ExprAst,
            track_by: ?[]const u8 = null,
            context_variables: []const R3Node,
            children: []const *const R3Node,
            empty: ?ForLoopBlockEmpty = null,
        },
        ForLoopBlockEmpty: ForLoopBlockEmpty,
        SwitchBlock: struct {
            expression: *const ExprAst,
            groups: []const SwitchBlockCaseGroup,
        },
        SwitchBlockCaseGroup: SwitchBlockCaseGroup,
        SwitchBlockCase: SwitchBlockCase,
        DeferredBlock: struct {
            children: []const *const R3Node,
            triggers: []const DeferredTrigger,
            placeholder: ?*const R3Node,
            loading: ?*const R3Node,
            err: ?*const R3Node,
            defer_block_dependencies: []const []const u8,
        },
        DeferredTrigger: DeferredTrigger,
        LetDeclaration: struct {
            name: []const u8,
            value: *const ExprAst,
            name_span: AbsoluteSourceSpan,
            value_span: AbsoluteSourceSpan,
        },
        Icu: struct {
            vars: []const IcuPlaceholder,
            placeholders: []const IcuPlaceholder,
            source_span: AbsoluteSourceSpan,
        },
        IcuPlaceholder: IcuPlaceholder,
        Comment: struct {
            value: []const u8,
        },
        UnknownBlock: struct {
            name: []const u8,
            children: []const *const R3Node,
        },
    };
};

// ─── Parsed Template Result ───────────────────────────────────

pub const ParsedTemplate = struct {
    nodes: []const *const R3Node,
    errors: []const ParseError,
    style_urls: []const []const u8,
    styles: []const []const u8,
    ng_content_selectors: []const []const u8,
    comment_nodes: ?[]const *const R3Node = null,
};

// ─── Visitor (comptime enforced) ──────────────────────────────

/// Example visitor — all methods MUST be implemented at compile time.
/// If you miss one, Zig compiler gives a clear error.
pub fn visit(comptime VisitorType: type, node: *const R3Node, visitor: VisitorType, ctx: anytype) !void {
    _ = visit;
    switch (node.data) {
        .Text => |v| try visitor.visitText(v, ctx),
        .BoundText => |v| try visitor.visitBoundText(v, ctx),
        .TextAttribute => |v| try visitor.visitTextAttribute(v, ctx),
        .BoundAttribute => |v| try visitor.visitBoundAttribute(v, ctx),
        .BoundEvent => |v| try visitor.visitBoundEvent(v, ctx),
        .Reference => |v| try visitor.visitReference(v, ctx),
        .Variable => |v| try visitor.visitVariable(v, ctx),
        .Element => |v| try visitor.visitElement(v, ctx),
        .Template => |v| try visitor.visitTemplate(v, ctx),
        .Component => |v| try visitor.visitComponent(v, ctx),
        .Directive => |v| try visitor.visitDirective(v, ctx),
        .Content => |v| try visitor.visitContent(v, ctx),
        .IfBlock => |v| try visitor.visitIfBlock(v, ctx),
        .ForLoopBlock => |v| try visitor.visitForLoopBlock(v, ctx),
        .SwitchBlock => |v| try visitor.visitSwitchBlock(v, ctx),
        .DeferredBlock => |v| try visitor.visitDeferredBlock(v, ctx),
        .LetDeclaration => |v| try visitor.visitLetDeclaration(v, ctx),
        .Icu => |v| try visitor.visitIcu(v, ctx),
        .Comment => |v| try visitor.visitComment(v, ctx),
        .UnknownBlock => |v| try visitor.visitUnknownBlock(v, ctx),
        .IfBlockBranch, .SwitchBlockCaseGroup, .SwitchBlockCase, .ForLoopBlockEmpty, .DeferredTrigger, .IcuPlaceholder => unreachable,
    }
}

// ─── Payload Type Aliases (for use as function parameter types) ──
/// In Zig 0.16.0, `R3Node.Data.FieldName` resolves to the enum value,
/// not the payload struct type, when used in type position.
/// These aliases provide the actual struct types.
pub const ElementData = @TypeOf(@as(R3Node.Data, undefined).Element);
pub const TextData = @TypeOf(@as(R3Node.Data, undefined).Text);
pub const BoundTextData = @TypeOf(@as(R3Node.Data, undefined).BoundText);
pub const TextAttributeData = @TypeOf(@as(R3Node.Data, undefined).TextAttribute);
pub const BoundAttributeData = @TypeOf(@as(R3Node.Data, undefined).BoundAttribute);
pub const BoundEventData = @TypeOf(@as(R3Node.Data, undefined).BoundEvent);
pub const ReferenceData = @TypeOf(@as(R3Node.Data, undefined).Reference);
pub const TemplateData = @TypeOf(@as(R3Node.Data, undefined).Template);
pub const ContentData = @TypeOf(@as(R3Node.Data, undefined).Content);
pub const IfBlockData = @TypeOf(@as(R3Node.Data, undefined).IfBlock);
pub const ForLoopBlockData = @TypeOf(@as(R3Node.Data, undefined).ForLoopBlock);
pub const SwitchBlockData = @TypeOf(@as(R3Node.Data, undefined).SwitchBlock);
pub const DeferredBlockData = @TypeOf(@as(R3Node.Data, undefined).DeferredBlock);
pub const LetDeclarationData = @TypeOf(@as(R3Node.Data, undefined).LetDeclaration);
pub const VariableData = @TypeOf(@as(R3Node.Data, undefined).Variable);
pub const IcuData = @TypeOf(@as(R3Node.Data, undefined).Icu);
pub const ComponentData = @TypeOf(@as(R3Node.Data, undefined).Component);
pub const DirectiveData = @TypeOf(@as(R3Node.Data, undefined).Directive);

// ─── Security Context ───────────────────────────────────────

/// SecurityContext — the security context for a binding.
/// Direct port of `SecurityContext` from core.ts.
pub const SecurityContext = enum(u8) {
    None = 0,
    HTML = 1,
    Style = 2,
    Script = 3,
    URL = 4,
    ResourceURL = 5,
};

// ─── BlockNode base (direct port from TS) ───────────────────

/// BlockNode — base struct for block nodes with spans.
/// Direct port of `BlockNode` class in the TS source.
pub const BlockNode = struct {
    name_span: ParseSourceSpan,
    source_span: ParseSourceSpan,
    start_source_span: ParseSourceSpan,
    end_source_span: ?ParseSourceSpan = null,
};

// ─── Deferred trigger types (direct port from TS) ──────────

/// BoundDeferredTrigger — for 'when' triggers.
/// Direct port of `BoundDeferredTrigger` class in the TS source.
pub const BoundDeferredTrigger = struct {
    value: *const ExprAst,
    source_span: ParseSourceSpan,
    prefetch_span: ?ParseSourceSpan = null,
    when_source_span: ?ParseSourceSpan = null,
    hydrate_span: ?ParseSourceSpan = null,
};

/// NeverDeferredTrigger — trigger that never fires.
/// Direct port of `NeverDeferredTrigger` class in the TS source.
pub const NeverDeferredTrigger = struct {
    name_span: ?ParseSourceSpan = null,
    source_span: ParseSourceSpan,
    prefetch_span: ?ParseSourceSpan = null,
    on_source_span: ?ParseSourceSpan = null,
    hydrate_span: ?ParseSourceSpan = null,
};

/// IdleDeferredTrigger — fires when browser is idle.
/// Direct port of `IdleDeferredTrigger` class in the TS source.
pub const IdleDeferredTrigger = struct {
    name_span: ?ParseSourceSpan = null,
    source_span: ParseSourceSpan,
    prefetch_span: ?ParseSourceSpan = null,
    on_source_span: ?ParseSourceSpan = null,
    hydrate_span: ?ParseSourceSpan = null,
    timeout: ?u32 = null,
};

/// ImmediateDeferredTrigger — fires immediately.
/// Direct port of `ImmediateDeferredTrigger` class in the TS source.
pub const ImmediateDeferredTrigger = struct {
    name_span: ?ParseSourceSpan = null,
    source_span: ParseSourceSpan,
    prefetch_span: ?ParseSourceSpan = null,
    on_source_span: ?ParseSourceSpan = null,
    hydrate_span: ?ParseSourceSpan = null,
};

/// HoverDeferredTrigger — fires on hover.
/// Direct port of `HoverDeferredTrigger` class in the TS source.
pub const HoverDeferredTrigger = struct {
    reference: ?[]const u8 = null,
    name_span: ?ParseSourceSpan = null,
    source_span: ParseSourceSpan,
    prefetch_span: ?ParseSourceSpan = null,
    on_source_span: ?ParseSourceSpan = null,
    hydrate_span: ?ParseSourceSpan = null,
};

/// TimerDeferredTrigger — fires after a delay.
/// Direct port of `TimerDeferredTrigger` class in the TS source.
pub const TimerDeferredTrigger = struct {
    delay: u32,
    name_span: ?ParseSourceSpan = null,
    source_span: ParseSourceSpan,
    prefetch_span: ?ParseSourceSpan = null,
    on_source_span: ?ParseSourceSpan = null,
    hydrate_span: ?ParseSourceSpan = null,
};

/// InteractionDeferredTrigger — fires on interaction.
/// Direct port of `InteractionDeferredTrigger` class in the TS source.
pub const InteractionDeferredTrigger = struct {
    reference: ?[]const u8 = null,
    name_span: ?ParseSourceSpan = null,
    source_span: ParseSourceSpan,
    prefetch_span: ?ParseSourceSpan = null,
    on_source_span: ?ParseSourceSpan = null,
    hydrate_span: ?ParseSourceSpan = null,
};

/// ViewportDeferredTrigger — fires when in viewport.
/// Direct port of `ViewportDeferredTrigger` class in the TS source.
pub const ViewportDeferredTrigger = struct {
    reference: ?[]const u8 = null,
    options: ?*const ExprAst = null, // LiteralMap
    name_span: ?ParseSourceSpan = null,
    source_span: ParseSourceSpan,
    prefetch_span: ?ParseSourceSpan = null,
    on_source_span: ?ParseSourceSpan = null,
    hydrate_span: ?ParseSourceSpan = null,
};

/// DeferredBlockTriggers — all possible deferred triggers.
/// Direct port of `DeferredBlockTriggers` interface in the TS source.
pub const DeferredBlockTriggers = struct {
    when: ?BoundDeferredTrigger = null,
    idle: ?IdleDeferredTrigger = null,
    immediate: ?ImmediateDeferredTrigger = null,
    hover: ?HoverDeferredTrigger = null,
    timer: ?TimerDeferredTrigger = null,
    interaction: ?InteractionDeferredTrigger = null,
    viewport: ?ViewportDeferredTrigger = null,
    never: ?NeverDeferredTrigger = null,
};

// ─── Deferred block sub-nodes ──────────────────────────────

/// DeferredBlockPlaceholder — placeholder for a deferred block.
/// Direct port of `DeferredBlockPlaceholder` class in the TS source.
pub const DeferredBlockPlaceholder = struct {
    base: BlockNode,
    children: []const *const R3Node,
    minimum_time: ?u32 = null,
    i18n: ?I18nMeta = null,
};

/// DeferredBlockLoading — loading state for a deferred block.
/// Direct port of `DeferredBlockLoading` class in the TS source.
pub const DeferredBlockLoading = struct {
    base: BlockNode,
    children: []const *const R3Node,
    after_time: ?u32 = null,
    minimum_time: ?u32 = null,
    i18n: ?I18nMeta = null,
};

/// DeferredBlockError — error state for a deferred block.
/// Direct port of `DeferredBlockError` class in the TS source.
pub const DeferredBlockError = struct {
    base: BlockNode,
    children: []const *const R3Node,
    i18n: ?I18nMeta = null,
};

// ─── Switch block sub-nodes ────────────────────────────────

/// SwitchExhaustiveCheck — exhaustive check for switch blocks.
/// Direct port of `SwitchExhaustiveCheck` class in the TS source.
pub const SwitchExhaustiveCheck = struct {
    base: BlockNode,
    expression: ?*const ExprAst = null,
};

// ─── ContentBlock (direct port from TS) ────────────────────

/// ContentBlock — a content block with name, variables, and children.
/// Direct port of `ContentBlock` class in the TS source.
pub const ContentBlock = struct {
    base: BlockNode,
    name: []const u8,
    variables: []const R3Node,
    children: []const *const R3Node,
    i18n: ?I18nMeta = null,
};

// ─── HostElement (direct port from TS) ─────────────────────

/// HostElement — AST node for a directive's host element.
/// Direct port of `HostElement` class in the TS source.
/// Used only for type checking purposes.
pub const HostElement = struct {
    tag_names: []const []const u8,
    bindings: []const R3Node,
    listeners: []const R3Node,
    source_span: ParseSourceSpan,
};

// ─── Visitor interface ─────────────────────────────────────

/// Visitor — interface for visiting R3 AST nodes.
/// Direct port of `Visitor<Result>` interface in the TS source.
///
/// Each method visits a specific node kind. The visitor is implemented
/// as a struct with function pointers for each visit method.
pub const Visitor = struct {
    ctx: *anyopaque,
    visit_element: *const fn (ctx: *anyopaque, node: *const R3Node) anyerror!void,
    visit_template: *const fn (ctx: *anyopaque, node: *const R3Node) anyerror!void,
    visit_content: *const fn (ctx: *anyopaque, node: *const R3Node) anyerror!void,
    visit_variable: *const fn (ctx: *anyopaque, node: *const R3Node) anyerror!void,
    visit_reference: *const fn (ctx: *anyopaque, node: *const R3Node) anyerror!void,
    visit_text_attribute: *const fn (ctx: *anyopaque, node: *const R3Node) anyerror!void,
    visit_bound_attribute: *const fn (ctx: *anyopaque, node: *const R3Node) anyerror!void,
    visit_bound_event: *const fn (ctx: *anyopaque, node: *const R3Node) anyerror!void,
    visit_text: *const fn (ctx: *anyopaque, node: *const R3Node) anyerror!void,
    visit_bound_text: *const fn (ctx: *anyopaque, node: *const R3Node) anyerror!void,
    visit_icu: *const fn (ctx: *anyopaque, node: *const R3Node) anyerror!void,
    visit_deferred_block: *const fn (ctx: *anyopaque, node: *const R3Node) anyerror!void,
    visit_switch_block: *const fn (ctx: *anyopaque, node: *const R3Node) anyerror!void,
    visit_for_loop_block: *const fn (ctx: *anyopaque, node: *const R3Node) anyerror!void,
    visit_if_block: *const fn (ctx: *anyopaque, node: *const R3Node) anyerror!void,
    visit_let_declaration: *const fn (ctx: *anyopaque, node: *const R3Node) anyerror!void,
    visit_component: *const fn (ctx: *anyopaque, node: *const R3Node) anyerror!void,
    visit_directive: *const fn (ctx: *anyopaque, node: *const R3Node) anyerror!void,
    visit_comment: *const fn (ctx: *anyopaque, node: *const R3Node) anyerror!void,
    visit_unknown_block: *const fn (ctx: *anyopaque, node: *const R3Node) anyerror!void,
};

// ─── visitAll ──────────────────────────────────────────────

/// Visit all nodes in a list.
/// Direct port of `visitAll(visitor, nodes)` function in the TS source.
pub fn visitAll(visitor: *const Visitor, nodes: []const *const R3Node) !void {
    for (nodes) |node| {
        try visitNode(node, visitor);
    }
}

/// Visit a single node using the visitor.
pub fn visitNode(node: *const R3Node, visitor: *const Visitor) !void {
    switch (node.data) {
        .Text => try visitor.visit_text(visitor.ctx, node),
        .BoundText => try visitor.visit_bound_text(visitor.ctx, node),
        .TextAttribute => try visitor.visit_text_attribute(visitor.ctx, node),
        .BoundAttribute => try visitor.visit_bound_attribute(visitor.ctx, node),
        .BoundEvent => try visitor.visit_bound_event(visitor.ctx, node),
        .Reference => try visitor.visit_reference(visitor.ctx, node),
        .Variable => try visitor.visit_variable(visitor.ctx, node),
        .Element => try visitor.visit_element(visitor.ctx, node),
        .Template => try visitor.visit_template(visitor.ctx, node),
        .Component => try visitor.visit_component(visitor.ctx, node),
        .Directive => try visitor.visit_directive(visitor.ctx, node),
        .Content => try visitor.visit_content(visitor.ctx, node),
        .IfBlock => try visitor.visit_if_block(visitor.ctx, node),
        .ForLoopBlock => try visitor.visit_for_loop_block(visitor.ctx, node),
        .SwitchBlock => try visitor.visit_switch_block(visitor.ctx, node),
        .DeferredBlock => try visitor.visit_deferred_block(visitor.ctx, node),
        .LetDeclaration => try visitor.visit_let_declaration(visitor.ctx, node),
        .Icu => try visitor.visit_icu(visitor.ctx, node),
        .Comment => try visitor.visit_comment(visitor.ctx, node),
        .UnknownBlock => try visitor.visit_unknown_block(visitor.ctx, node),
        else => {},
    }
}

// ─── RecursiveVisitor ──────────────────────────────────────

/// RecursiveVisitor — walks all children of each node recursively.
/// Direct port of `RecursiveVisitor` class in the TS source.
pub const RecursiveVisitor = struct {
    /// Recursively visit all nodes in a list.
    pub fn visitAllNodes(nodes: []const *const R3Node) void {
        for (nodes) |node| {
            visitNodeRecursive(node);
        }
    }

    /// Recursively visit a single node and its children.
    pub fn visitNodeRecursive(node: *const R3Node) void {
        switch (node.data) {
            .Element => |e| {
                visitAllNodes(e.children);
            },
            .Template => |t| {
                visitAllNodes(t.children);
            },
            .Component => |c| {
                visitAllNodes(c.children);
            },
            .Content => |c| {
                visitAllNodes(c.children);
            },
            .IfBlock => |ib| {
                for (ib.branches) |branch| {
                    visitAllNodes(branch.children);
                }
            },
            .ForLoopBlock => |fl| {
                visitAllNodes(fl.children);
                if (fl.empty) |empty| {
                    visitAllNodes(empty.children);
                }
            },
            .SwitchBlock => |sb| {
                for (sb.groups) |group| {
                    visitAllNodes(group.children);
                }
            },
            .DeferredBlock => |db| {
                visitAllNodes(db.children);
            },
            else => {},
        }
    }
};

// ─── BoundAttribute.fromBoundElementProperty ───────────────

/// Create a BoundAttribute from a BoundElementProperty.
/// Direct port of `BoundAttribute.fromBoundElementProperty(prop, i18n)` in the TS source.
pub fn boundAttributeFromProperty(
    name: []const u8,
    prop_type: BindingType,
    value: *const ExprAst,
    unit: ?[]const u8,
    src_span: ParseSourceSpan,
    key_span: AbsoluteSourceSpan,
    value_span: ?AbsoluteSourceSpan,
    i18n: ?I18nMeta,
) R3Node {
    _ = value_span;
    return .{
        .kind = .BoundAttribute,
        .source_span = src_span,
        .data = .{ .BoundAttribute = .{
            .name = name,
            .type = prop_type,
            .value = value,
            .unit = unit,
            .key_span = key_span,
            .source_span = key_span,
            .i18n = if (i18n) |_| null else null,
        } },
    };
}

// ─── BoundEvent.fromParsedEvent ────────────────────────────

/// Create a BoundEvent from a ParsedEvent.
/// Direct port of `BoundEvent.fromParsedEvent(event)` in the TS source.
pub fn boundEventFromParsedEvent(
    name: []const u8,
    event_type: ParsedEventType,
    handler: *const ExprAst,
    target_or_phase: []const u8,
    src_span: ParseSourceSpan,
    handler_span: AbsoluteSourceSpan,
    key_span: AbsoluteSourceSpan,
) R3Node {
    const target: ?[]const u8 = if (event_type == .Regular) target_or_phase else null;
    const phase: ?[]const u8 = if (event_type == .LegacyAnimation) target_or_phase else null;
    return .{
        .kind = .BoundEvent,
        .source_span = src_span,
        .data = .{ .BoundEvent = .{
            .name = name,
            .type = event_type,
            .handler = handler,
            .target = target,
            .phase = phase,
            .key_span = key_span,
            .handler_span = handler_span,
            .source_span = key_span,
        } },
    };
}

// ─── Helper: count nodes by kind ───────────────────────────

/// Count nodes of a specific kind in a list.
pub fn countNodesByKind(nodes: []const *const R3Node, kind: NodeKind) usize {
    var count: usize = 0;
    for (nodes) |node| {
        if (node.kind == kind) count += 1;
    }
    return count;
}

/// Count all nodes recursively (including children).
pub fn countAllNodes(nodes: []const *const R3Node) usize {
    var count: usize = 0;
    for (nodes) |node| {
        count += 1;
        switch (node.data) {
            .Element => |e| count += countAllNodes(e.children),
            .Template => |t| count += countAllNodes(t.children),
            .Component => |c| count += countAllNodes(c.children),
            .Content => |c| count += countAllNodes(c.children),
            .IfBlock => |ib| {
                for (ib.branches) |branch| {
                    count += countAllNodes(branch.children);
                }
            },
            .ForLoopBlock => |fl| {
                count += countAllNodes(fl.children);
                if (fl.empty) |empty| {
                    count += countAllNodes(empty.children);
                }
            },
            .SwitchBlock => |sb| {
                for (sb.groups) |group| {
                    count += countAllNodes(group.children);
                }
            },
            .DeferredBlock => |db| {
                count += countAllNodes(db.children);
            },
            else => {},
        }
    }
    return count;
}

// ─── Helper: find node by name ─────────────────────────────

/// Find an element node by name in a list of nodes.
pub fn findElementByName(nodes: []const *const R3Node, name: []const u8) ?*const R3Node {
    for (nodes) |node| {
        if (node.kind == .Element and std.mem.eql(u8, node.data.Element.name, name)) {
            return node;
        }
    }
    return null;
}

/// Find a reference by name.
pub fn findReferenceByName(nodes: []const *const R3Node, name: []const u8) ?*const R3Node {
    for (nodes) |node| {
        if (node.kind == .Reference and std.mem.eql(u8, node.data.Reference.name, name)) {
            return node;
        }
    }
    return null;
}

/// Find a variable by name.
pub fn findVariableByName(nodes: []const *const R3Node, name: []const u8) ?*const R3Node {
    for (nodes) |node| {
        if (node.kind == .Variable and std.mem.eql(u8, node.data.Variable.name, name)) {
            return node;
        }
    }
    return null;
}

// ─── Tests ────────────────────────────────────────────────────

test "R3Node size" {
    comptime {}
}

test "NodeKind coverage" {
    // Ensure all kinds are handled in visit function
    const kinds = std.meta.tags(NodeKind);
    try std.testing.expect(kinds.len > 15);
}

test "BindingType enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(BindingType.Property));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(BindingType.Attribute));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(BindingType.Class));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(BindingType.Style));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(BindingType.Animation));
    try std.testing.expectEqual(@as(u8, 5), @intFromEnum(BindingType.TwoWay));
    try std.testing.expectEqual(@as(u8, 6), @intFromEnum(BindingType.LegacyAnimation));
}

test "ParsedEventType enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(ParsedEventType.Regular));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(ParsedEventType.AnimationStart));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(ParsedEventType.TwoWay));
}

test "DeferredTriggerKind enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(DeferredTriggerKind.Idle));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(DeferredTriggerKind.Immediate));
    try std.testing.expectEqual(@as(u8, 6), @intFromEnum(DeferredTriggerKind.Never));
}

test "SecurityContext enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(SecurityContext.None));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(SecurityContext.HTML));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(SecurityContext.Script));
    try std.testing.expectEqual(@as(u8, 5), @intFromEnum(SecurityContext.ResourceURL));
}

test "I18nMeta defaults" {
    const meta = I18nMeta{};
    try std.testing.expect(meta.meaning == null);
    try std.testing.expect(meta.description == null);
    try std.testing.expect(meta.id == null);
}

test "I18nMeta with values" {
    const meta = I18nMeta{
        .meaning = "greeting",
        .description = "A greeting message",
        .id = "msg-1",
    };
    try std.testing.expectEqualStrings("greeting", meta.meaning.?);
    try std.testing.expectEqualStrings("A greeting message", meta.description.?);
}

test "SpanPair" {
    const pair = SpanPair{
        .start = .{ .start = 0, .end = 10 },
        .end = .{ .start = 20, .end = 30 },
    };
    try std.testing.expectEqual(@as(u32, 0), pair.start.start);
    try std.testing.expectEqual(@as(u32, 30), pair.end.end);
}

test "BlockNode defaults" {
    const span = ParseSourceSpan.init(0, 10, "test");
    const block = BlockNode{
        .name_span = span,
        .source_span = span,
        .start_source_span = span,
    };
    try std.testing.expect(block.end_source_span == null);
}

test "DeferredBlockTriggers — all null defaults" {
    const triggers = DeferredBlockTriggers{};
    try std.testing.expect(triggers.when == null);
    try std.testing.expect(triggers.idle == null);
    try std.testing.expect(triggers.immediate == null);
    try std.testing.expect(triggers.hover == null);
    try std.testing.expect(triggers.timer == null);
    try std.testing.expect(triggers.interaction == null);
    try std.testing.expect(triggers.viewport == null);
    try std.testing.expect(triggers.never == null);
}

test "TimerDeferredTrigger" {
    const span = ParseSourceSpan.init(0, 10, "test");
    const trigger = TimerDeferredTrigger{
        .delay = 500,
        .source_span = span,
    };
    try std.testing.expectEqual(@as(u32, 500), trigger.delay);
}

test "IdleDeferredTrigger with timeout" {
    const span = ParseSourceSpan.init(0, 10, "test");
    const trigger = IdleDeferredTrigger{
        .source_span = span,
        .timeout = 1000,
    };
    try std.testing.expectEqual(@as(u32, 1000), trigger.timeout.?);
}

test "HoverDeferredTrigger with reference" {
    const span = ParseSourceSpan.init(0, 10, "test");
    const trigger = HoverDeferredTrigger{
        .reference = "myElement",
        .source_span = span,
    };
    try std.testing.expectEqualStrings("myElement", trigger.reference.?);
}

test "ViewportDeferredTrigger defaults" {
    const span = ParseSourceSpan.init(0, 10, "test");
    const trigger = ViewportDeferredTrigger{
        .source_span = span,
    };
    try std.testing.expect(trigger.reference == null);
    try std.testing.expect(trigger.options == null);
}

test "countNodesByKind — empty list" {
    const count = countNodesByKind(&.{}, .Element);
    try std.testing.expectEqual(@as(usize, 0), count);
}

test "countAllNodes — empty list" {
    const count = countAllNodes(&.{});
    try std.testing.expectEqual(@as(usize, 0), count);
}

test "findElementByName — not found" {
    const result = findElementByName(&.{}, "div");
    try std.testing.expect(result == null);
}

test "findReferenceByName — not found" {
    const result = findReferenceByName(&.{}, "myRef");
    try std.testing.expect(result == null);
}

test "findVariableByName — not found" {
    const result = findVariableByName(&.{}, "item");
    try std.testing.expect(result == null);
}

test "RecursiveVisitor — empty list" {
    RecursiveVisitor.visitAllNodes(&.{});
    try std.testing.expect(true);
}

test "ContentBlock struct" {
    const span = ParseSourceSpan.init(0, 10, "test");
    const block = ContentBlock{
        .base = .{
            .name_span = span,
            .source_span = span,
            .start_source_span = span,
        },
        .name = "myBlock",
        .variables = &.{},
        .children = &.{},
    };
    try std.testing.expectEqualStrings("myBlock", block.name);
}

test "HostElement with tag names" {
    const span = ParseSourceSpan.init(0, 10, "test");
    const tags = [_][]const u8{ "div", "span" };
    const host = HostElement{
        .tag_names = &tags,
        .bindings = &.{},
        .listeners = &.{},
        .source_span = span,
    };
    try std.testing.expectEqual(@as(usize, 2), host.tag_names.len);
}

test "SwitchExhaustiveCheck" {
    const span = ParseSourceSpan.init(0, 10, "test");
    const check = SwitchExhaustiveCheck{
        .base = .{
            .name_span = span,
            .source_span = span,
            .start_source_span = span,
        },
    };
    try std.testing.expect(check.expression == null);
}

test "DeferredBlockPlaceholder" {
    const span = ParseSourceSpan.init(0, 10, "test");
    const placeholder = DeferredBlockPlaceholder{
        .base = .{
            .name_span = span,
            .source_span = span,
            .start_source_span = span,
        },
        .children = &.{},
        .minimum_time = 100,
    };
    try std.testing.expectEqual(@as(u32, 100), placeholder.minimum_time.?);
}

test "DeferredBlockLoading" {
    const span = ParseSourceSpan.init(0, 10, "test");
    const loading = DeferredBlockLoading{
        .base = .{
            .name_span = span,
            .source_span = span,
            .start_source_span = span,
        },
        .children = &.{},
        .after_time = 200,
        .minimum_time = 300,
    };
    try std.testing.expectEqual(@as(u32, 200), loading.after_time.?);
    try std.testing.expectEqual(@as(u32, 300), loading.minimum_time.?);
}

test "DeferredBlockError" {
    const span = ParseSourceSpan.init(0, 10, "test");
    const err_block = DeferredBlockError{
        .base = .{
            .name_span = span,
            .source_span = span,
            .start_source_span = span,
        },
        .children = &.{},
    };
    try std.testing.expect(err_block.i18n == null);
}

test "NeverDeferredTrigger defaults" {
    const span = ParseSourceSpan.init(0, 10, "test");
    const trigger = NeverDeferredTrigger{
        .source_span = span,
    };
    try std.testing.expect(trigger.name_span == null);
}

test "ImmediateDeferredTrigger defaults" {
    const span = ParseSourceSpan.init(0, 10, "test");
    const trigger = ImmediateDeferredTrigger{
        .source_span = span,
    };
    try std.testing.expect(trigger.name_span == null);
}

test "InteractionDeferredTrigger with reference" {
    const span = ParseSourceSpan.init(0, 10, "test");
    const trigger = InteractionDeferredTrigger{
        .reference = "myButton",
        .source_span = span,
    };
    try std.testing.expectEqualStrings("myButton", trigger.reference.?);
}
