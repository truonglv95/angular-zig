/// i18n AST — Message and Node types for internationalization
///
/// Port of: compiler/src/i18n/i18n_ast.ts
///
/// Defines the i18n message structure used for translation extraction.
/// A Message contains a tree of Nodes (Text, Placeholder, TagPlaceholder, Icu).
const std = @import("std");

const source_span = @import("../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

// ─── MessageSpan ─────────────────────────────────────────────

/// Source location info for a message (1-based line/col).
pub const MessageSpan = struct {
    file_path: []const u8,
    start_line: u32,
    start_col: u32,
    end_line: u32,
    end_col: u32,
};

// ─── MessagePlaceholder ──────────────────────────────────────

/// Describes text contents of a placeholder in an ICU expression.
pub const MessagePlaceholder = struct {
    text: []const u8,
    source_span: AbsoluteSourceSpan,
};

// ─── Message ─────────────────────────────────────────────────

/// A translatable message extracted from a template.
pub const Message = struct {
    /// Unique ID (custom or computed).
    id: []const u8 = "",
    /// Legacy IDs for backward compatibility.
    legacy_ids: []const []const u8 = &.{},
    /// Serialized message string (computed from nodes).
    message_string: []const u8 = "",
    /// AST nodes of the message.
    nodes: []const Node = &.{},
    /// Maps placeholder names to static content + source spans.
    placeholders: std.StringHashMap(MessagePlaceholder),
    /// Maps placeholder names to nested messages (for ICU).
    placeholder_to_message: std.StringHashMap(*Message),
    /// Meaning context (disambiguates identical strings).
    meaning: []const u8 = "",
    /// Human-readable description.
    description: []const u8 = "",
    /// Custom ID (if provided by user).
    custom_id: []const u8 = "",
    /// Source locations.
    sources: []const MessageSpan = &.{},

    pub fn init(allocator: std.mem.Allocator) Message {
        return .{
            .placeholders = std.StringHashMap(MessagePlaceholder).init(allocator),
            .placeholder_to_message = std.StringHashMap(*Message).init(allocator),
        };
    }

    pub fn deinit(self: *Message) void {
        self.placeholders.deinit();
        self.placeholder_to_message.deinit();
    }
};

// ─── Node ────────────────────────────────────────────────────

/// Tagged union of i18n message node kinds.
pub const NodeKind = enum(u8) {
    text,
    container,
    icu,
    placeholder,
    tag_placeholder,
};

/// A node in an i18n message tree.
pub const Node = struct {
    kind: NodeKind,
    source_span: AbsoluteSourceSpan,
    data: NodeData,

    pub const NodeData = union(NodeKind) {
        text: TextData,
        container: ContainerData,
        icu: IcuData,
        placeholder: PlaceholderData,
        tag_placeholder: TagPlaceholderData,
    };
};

// ─── Node Data Types ─────────────────────────────────────────

/// Literal text content.
pub const TextData = struct {
    value: []const u8,
};

/// A container for nested nodes (e.g. inside an element).
pub const ContainerData = struct {
    children: []const Node,
};

/// An ICU expression ({count, plural, =0 {...} other {...}}).
pub const IcuData = struct {
    expression: []const u8,
    /// Placeholder name for this ICU (e.g. "ICU" or "ICU_1").
    name: []const u8,
    /// Cases (e.g. "=0", "one", "other").
    cases: []const IcuCase,
};

/// A case in an ICU expression.
pub const IcuCase = struct {
    value: []const u8, // "=0", "one", "other", etc.
    children: []const Node,
};

/// A placeholder for an interpolated expression ({{ name }} → PH).
pub const PlaceholderData = struct {
    name: []const u8, // "PH", "PH_1", etc.
    expression: []const u8,
};

/// A placeholder for an element tag (<b>...</b> → START_TAG_B).
pub const TagPlaceholderData = struct {
    /// Tag name: "b", "span", etc. (or "*ngIf" for templates)
    tag: []const u8,
    /// Whether this is a start tag, end tag, or self-closing.
    is_start: bool,
    /// Whether this is a close tag.
    is_close: bool,
    /// Children placeholders (for nested content).
    children: []const Node,
    /// Attributes serialized as string.
    attrs: []const u8 = "",
};

// ─── Visitor Pattern ─────────────────────────────────────────

/// Visitor interface for walking i18n message nodes.
pub const Visitor = struct {
    visit_text: *const fn (ctx: *anyopaque, node: *const Node) anyerror!void,
    visit_container: *const fn (ctx: *anyopaque, node: *const Node) anyerror!void,
    visit_icu: *const fn (ctx: *anyopaque, node: *const Node) anyerror!void,
    visit_placeholder: *const fn (ctx: *anyopaque, node: *const Node) anyerror!void,
    visit_tag_placeholder: *const fn (ctx: *anyopaque, node: *const Node) anyerror!void,
};

/// Visit a node with the given visitor.
pub fn visit(node: *const Node, visitor: *const Visitor, ctx: *anyopaque) !void {
    switch (node.data) {
        .text => try visitor.visit_text(ctx, node),
        .container => try visitor.visit_container(ctx, node),
        .icu => try visitor.visit_icu(ctx, node),
        .placeholder => try visitor.visit_placeholder(ctx, node),
        .tag_placeholder => try visitor.visit_tag_placeholder(ctx, node),
    }
}

// ─── Serialize Message ───────────────────────────────────────

/// Serialize message nodes to a string representation.
/// Used for computing message IDs.
pub fn serializeMessage(allocator: std.mem.Allocator, nodes: []const Node) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    for (nodes) |*node| {
        try serializeNode(&buf, node);
    }
    return buf.toOwnedSlice();
}

fn serializeNode(buf: *std.array_list.Managed(u8), node: *const Node) !void {
    switch (node.data) {
        .text => |t| try buf.appendSlice(t.value),
        .container => |c| {
            for (c.children) |child| {
                try serializeNode(buf, &child);
            }
        },
        .icu => |icu| {
            try buf.appendSlice("{");
            try buf.appendSlice(icu.expression);
            try buf.appendSlice("}");
        },
        .placeholder => |ph| {
            try buf.append('{');
            try buf.appendSlice(ph.name);
            try buf.append('}');
        },
        .tag_placeholder => |tp| {
            if (tp.is_start) {
                try buf.append('<');
                try buf.appendSlice(tp.tag);
                try buf.append('>');
            } else if (tp.is_close) {
                try buf.appendSlice("</");
                try buf.appendSlice(tp.tag);
                try buf.append('>');
            }
            for (tp.children) |child| {
                try serializeNode(buf, &child);
            }
        },
    }
}

// ─── Additional i18n AST types ──────────────────────────────

/// I18nBlockPlaceholder — placeholder for a block (@if, @for) in an i18n message.
pub const BlockPlaceholderData = struct {
    name: []const u8,
    start_name: ?[]const u8 = null,
    close_name: ?[]const u8 = null,
    children: []const Node = &.{},
};

/// Serialize a message to a string representation.
pub fn serializeMessageToString(allocator: std.mem.Allocator, nodes: []const Node) ![]const u8 {
    return serializeMessage(allocator, nodes);
}

// ─── Tests ──────────────────────────────────────────────────

test "TagPlaceholderData defaults" {
    const tp = TagPlaceholderData{ .tag = "div", .is_start = false, .is_close = false, .children = &.{} };
    
    try std.testing.expect(!tp.is_start);
    try std.testing.expect(!tp.is_close);
}

test "BlockPlaceholderData defaults" {
    const bp = BlockPlaceholderData{ .name = "if" };
    try std.testing.expectEqualStrings("if", bp.name);
    try std.testing.expect(bp.start_name == null);
}

test "serializeMessageToString text" {
    const allocator = std.testing.allocator;
    var nodes = [_]Node{.{
        .kind = .text,
        .source_span = .{ .start = 0, .end = 0 },
        .data = .{ .text = .{ .value = "Hello" } },
    }};
    const result = try serializeMessageToString(allocator, &nodes);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello", result);
}

test "serializeMessageToString placeholder" {
    const allocator = std.testing.allocator;
    var nodes = [_]Node{.{
        .kind = .placeholder,
        .source_span = .{ .start = 0, .end = 0 },
        .data = .{ .placeholder = .{ .name = "PH", .expression = "expr" } },
    }};
    const result = try serializeMessageToString(allocator, &nodes);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("{PH}", result);
}
