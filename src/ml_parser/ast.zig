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

    /// Free the root_nodes slice (allocated by `mergeAdjacentTextNodes`).
    /// Call this when the parse result is no longer needed.
    pub fn deinit(self: *ParseTreeResult, allocator: std.mem.Allocator) void {
        if (self.root_nodes.len > 0) {
            allocator.free(self.root_nodes);
        }
    }
};

// ─── Serialization ────────────────────────────────────────────

/// Serialize a single node to its HTML string representation.
pub fn serializeNode(allocator: std.mem.Allocator, node: *const Node) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();
    try serializeNodeInto(&buf, node);
    return buf.toOwnedSlice();
}

/// Serialize multiple nodes to a single HTML string.
pub fn serializeNodes(allocator: std.mem.Allocator, nodes: []const *const Node) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();
    for (nodes) |n| {
        try serializeNodeInto(&buf, n);
    }
    return buf.toOwnedSlice();
}

fn serializeNodeInto(buf: *std.array_list.Managed(u8), node: *const Node) !void {
    switch (node.data) {
        .Element => |e| {
            try buf.append('<');
            try buf.appendSlice(e.name);
            for (e.attrs) |attr| {
                try buf.append(' ');
                try buf.appendSlice(attr.name);
                if (attr.value.len > 0) {
                    try buf.append('=');
                    try buf.append('"');
                    try buf.appendSlice(attr.value);
                    try buf.append('"');
                }
            }
            if (e.is_void or e.is_self_closing) {
                try buf.appendSlice("/>");
                return;
            }
            try buf.append('>');
            for (e.children) |child| {
                try serializeNodeInto(buf, child);
            }
            try buf.appendSlice("</");
            try buf.appendSlice(e.name);
            try buf.append('>');
        },
        .Text => |t| {
            try buf.appendSlice(t.value);
        },
        .Comment => |c| {
            try buf.appendSlice("<!--");
            try buf.appendSlice(c.value);
            try buf.appendSlice("-->");
        },
        .Attribute => |a| {
            try buf.appendSlice(a.name);
            if (a.value.len > 0) {
                try buf.append('=');
                try buf.append('"');
                try buf.appendSlice(a.value);
                try buf.append('"');
            }
        },
        .Cdata => |c| {
            try buf.appendSlice("<![CDATA[");
            try buf.appendSlice(c.value);
            try buf.appendSlice("]]>");
        },
        .DocType => |d| {
            try buf.appendSlice("<!DOCTYPE ");
            try buf.appendSlice(d.value);
            try buf.append('>');
        },
        .Block => |b| {
            try buf.append('@');
            try buf.appendSlice(b.name);
            if (b.parameters.len > 0) {
                try buf.appendSlice(" (");
                for (b.parameters, 0..) |p, i| {
                    if (i > 0) try buf.appendSlice("; ");
                    try buf.appendSlice(p.expression);
                }
                try buf.append(')');
            }
            try buf.append('{');
            for (b.children) |child| {
                try serializeNodeInto(buf, child);
            }
            try buf.append('}');
        },
        .Expansion => |exp| {
            try buf.append('{');
            try buf.appendSlice(exp.switch_value);
            try buf.appendSlice(", ");
            try buf.appendSlice(exp.type);
            try buf.append(',');
            for (exp.cases) |case| {
                try serializeNodeInto(buf, case);
            }
            try buf.append('}');
        },
        .ExpansionCase => |c| {
            try buf.append(' ');
            try buf.appendSlice(c.value);
            try buf.appendSlice(" {");
            for (c.children) |child| {
                try serializeNodeInto(buf, child);
            }
            try buf.append('}');
        },
        .BlockParameter => |p| {
            try buf.appendSlice(p.expression);
        },
    }
}

// ─── Tests ────────────────────────────────────────────────────

test "Node size" {
    comptime {}
    // Should be reasonable
    try std.testing.expect(@sizeOf(Node) < 256);
}
