/// HTML AST — Tagged Union Design for HTML Parse Tree
///
/// Angular's ml_parser produces a tree of HTML nodes.
/// Zig tagged union = single allocation per node, no vtable.
const std = @import("std");
const source_span = @import("../source_span.zig");
const ParseSourceSpan = source_span.ParseSourceSpan;
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;
const ParseError = source_span.ParseError;

pub const NodeKind = enum(u8) {
    Text,
    Attribute,
    Element,
    Comment,
    Expansion,
    ExpansionCase,
    Block,
    BlockParameter,
    DocType,
    Cdata,
};

// ─── Interpolation Boundary ───────────────────────────────────
/// Tracks {{ }} boundaries within text/attributes
pub const InterpolationBoundary = struct {
    start: u32,
    end: u32,
    is_expression: bool,
};

// ─── Text Node ────────────────────────────────────────────────

pub const TextNode = struct {
    value: []const u8,
    /// Interpolation boundaries (empty if no {{ }})
    interpolation_boundaries: []const InterpolationBoundary = &[_]InterpolationBoundary{},
};

// ─── Attribute Node ───────────────────────────────────────────

pub const AttributeNode = struct {
    name: []const u8,
    value: []const u8,
    key_span: AbsoluteSourceSpan,
    value_span: AbsoluteSourceSpan,
    /// Interpolation boundaries in attribute value
    interpolation_boundaries: []const InterpolationBoundary = &[_]InterpolationBoundary{},
    i18n: ?[]const u8 = null, // i18n attribute value if present
};

// ─── Element Node ─────────────────────────────────────────────

pub const ElementNode = struct {
    name: []const u8,
    attrs: []const AttributeNode,
    children: []const *const Node,
    start_span: AbsoluteSourceSpan,
    end_span: ?AbsoluteSourceSpan = null,
    end_source_span: ?ParseSourceSpan = null,
    is_self_closing: bool = false,
    is_void: bool = false,
    i18n: ?[]const u8 = null,
};

// ─── Comment Node ─────────────────────────────────────────────

pub const CommentNode = struct {
    value: []const u8,
};

// ─── Expansion (i18n {plural/select}) ──────────────────────────

pub const ExpansionNode = struct {
    switch_value: []const u8,
    type: []const u8, // "plural" or "select"
    cases: []const *const Node, // ExpansionCase nodes
};

pub const ExpansionCaseNode = struct {
    value: []const u8,
    expression: []const u8,
    children: []const *const Node,
};

// ─── Block (@if, @for, @switch) ───────────────────────────────

pub const BlockNode = struct {
    name: []const u8, // "if", "for", "switch"
    parameters: []const BlockParameter,
    children: []const *const Node,
    i18n: ?[]const u8 = null,
};

pub const BlockParameter = struct {
    expression: []const u8,
    source_span: AbsoluteSourceSpan,
    value_span: ?AbsoluteSourceSpan = null,
};

// ─── DocType / CData ──────────────────────────────────────────

pub const DocTypeNode = struct {
    value: []const u8,
};

pub const CdataNode = struct {
    value: []const u8,
};

// ─── Unified Node (Tagged Union) ──────────────────────────────

pub const Node = struct {
    kind: NodeKind,
    source_span: ParseSourceSpan,
    data: NodeData,

    pub const NodeData = union(NodeKind) {
        Text: TextNode,
        Attribute: AttributeNode,
        Element: ElementNode,
        Comment: CommentNode,
        Expansion: ExpansionNode,
        ExpansionCase: ExpansionCaseNode,
        Block: BlockNode,
        BlockParameter: BlockParameter,
        DocType: DocTypeNode,
        Cdata: CdataNode,
    };

    // ─── Visitor Pattern (comptime type-safe) ───────────────

    pub fn visit(self: *const Node, visitor: anytype, ctx: anytype) !@TypeOf(visitor).Result {
        return switch (self.data) {
            .Text => |v| try visitor.visitText(v, ctx),
            .Attribute => |v| try visitor.visitAttribute(v, ctx),
            .Element => |v| try visitor.visitElement(v, ctx),
            .Comment => |v| try visitor.visitComment(v, ctx),
            .Expansion => |v| try visitor.visitExpansion(v, ctx),
            .ExpansionCase => |v| try visitor.visitExpansionCase(v, ctx),
            .Block => |v| try visitor.visitBlock(v, ctx),
            .BlockParameter => |v| try visitor.visitBlockParameter(v, ctx),
            .DocType => |v| try visitor.visitDocType(v, ctx),
            .Cdata => |v| try visitor.visitCdata(v, ctx),
        };
    }
};

// ─── Parse Result ─────────────────────────────────────────────

pub const ParseTreeResult = struct {
    root_nodes: []const *const Node,
    errors: []const ParseError,
};

// ─── Tests ────────────────────────────────────────────────────

test "Node size" {
    comptime {}
    // Should be reasonable
    try std.testing.expect(@sizeOf(Node) < 256);
}
