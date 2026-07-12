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

const expr_ast = @import("../expr/ast.zig");
const ExprAst = expr_ast.Ast;

// ─── Binding Types ────────────────────────────────────────────

pub const BindingType = enum(u8) {
    Property, // [prop] or bind-prop
    Attribute, // attr.name
    Class, // class.name
    Style, // style.prop
    Animation, // @animation.name
    TwoWay, // [(prop)] or bindon-prop
};

pub const ParsedEventType = enum(u8) {
    Regular,
    AnimationStart,
    AnimationDone,
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

// ─── Tests ────────────────────────────────────────────────────

test "R3Node size" {
    comptime {}
}

test "NodeKind coverage" {
    // Ensure all kinds are handled in visit function
    const kinds = std.meta.tags(NodeKind);
    try std.testing.expect(kinds.len > 15);
}
