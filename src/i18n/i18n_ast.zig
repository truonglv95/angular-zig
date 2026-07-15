/// i18n AST — Message and Node types for internationalization
///
/// Port of: compiler/src/i18n/i18n_ast.ts (322 LoC)
///
/// Defines the i18n message structure used for translation extraction.
/// A Message contains a tree of Nodes (Text, Placeholder, TagPlaceholder,
/// Container, Icu, IcuPlaceholder, BlockPlaceholder).
///
/// DOD: tagged union Node thay cho class hierarchy, không vptr.
/// Visitor được implement qua comptime interface (struct với function pointers).
const std = @import("std");
const Allocator = std.mem.Allocator;

const source_span = @import("../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;
const ParseSourceSpan = source_span.ParseSourceSpan;

// ─── MessageSpan ─────────────────────────────────────────────

/// Source location info for a message (1-based line/col).
/// Direct port of `MessageSpan` interface in the TS source.
pub const MessageSpan = struct {
    file_path: []const u8,
    start_line: u32,
    start_col: u32,
    end_line: u32,
    end_col: u32,
};

// ─── MessagePlaceholder ──────────────────────────────────────

/// Describes text contents of a placeholder in an ICU expression.
/// Direct port of `MessagePlaceholder` interface in the TS source.
pub const MessagePlaceholder = struct {
    text: []const u8,
    source_span: AbsoluteSourceSpan,
};

// ─── Node types ──────────────────────────────────────────────

/// Tagged union of i18n message node kinds.
/// Direct port of all `Node` implementations in the TS source:
/// Text, Container, Icu, TagPlaceholder, Placeholder, IcuPlaceholder, BlockPlaceholder.
pub const NodeKind = enum(u8) {
    text,
    container,
    icu,
    tag_placeholder,
    placeholder,
    icu_placeholder,
    block_placeholder,
};

/// A node in an i18n message tree.
/// DOD: tagged union + payload (zero vptr, cache-friendly).
pub const Node = struct {
    kind: NodeKind,
    source_span: ParseSourceSpan,
    data: NodeData,

    pub const NodeData = union(NodeKind) {
        text: Text,
        container: Container,
        icu: Icu,
        tag_placeholder: TagPlaceholder,
        placeholder: Placeholder,
        icu_placeholder: IcuPlaceholder,
        block_placeholder: BlockPlaceholder,
    };

    /// Visit this node with the given visitor.
    /// Direct port of `Node.visit(visitor, context)` in the TS source.
    pub fn visit(self: *const Node, visitor: *const Visitor, ctx: *anyopaque) anyerror!void {
        switch (self.data) {
            .text => try visitor.visit_text(ctx, self),
            .container => try visitor.visit_container(ctx, self),
            .icu => try visitor.visit_icu(ctx, self),
            .tag_placeholder => try visitor.visit_tag_placeholder(ctx, self),
            .placeholder => try visitor.visit_placeholder(ctx, self),
            .icu_placeholder => try visitor.visit_icu_placeholder(ctx, self),
            .block_placeholder => try visitor.visit_block_placeholder(ctx, self),
        }
    }
};

// ─── Text ────────────────────────────────────────────────────

/// Literal text content.
/// Direct port of `Text` class in the TS source.
pub const Text = struct {
    value: []const u8,
};

// ─── Container ───────────────────────────────────────────────

/// A container for nested nodes (e.g. inside an element).
/// Direct port of `Container` class in the TS source.
pub const Container = struct {
    children: []const Node,
};

// ─── Icu ─────────────────────────────────────────────────────

/// An ICU expression ({count, plural, =0 {...} other {...}}).
/// Direct port of `Icu` class in the TS source.
pub const Icu = struct {
    expression: []const u8,
    /// ICU type: "plural", "select", "selectordinal".
    type: []const u8,
    /// Cases — list of (case_value, children).
    cases: []const IcuCase,
    /// Placeholder name for this ICU (e.g. "VAR_plural" or "ICU").
    expression_placeholder: []const u8 = "",
};

/// A case in an ICU expression.
pub const IcuCase = struct {
    /// Case value: "=0", "one", "other", etc.
    value: []const u8,
    /// The child nodes for this case.
    children: []const Node,
};

// ─── TagPlaceholder ──────────────────────────────────────────

/// A placeholder for an element tag (<b>...</b> → START_TAG_B).
/// Direct port of `TagPlaceholder` class in the TS source.
pub const TagPlaceholder = struct {
    /// Tag name: "b", "span", etc.
    tag: []const u8,
    /// Attributes serialized as key=value pairs.
    attrs: []const TagAttr = &.{},
    /// Placeholder name for the start tag (e.g. "START_TAG_B").
    start_name: []const u8,
    /// Placeholder name for the close tag (e.g. "CLOSE_TAG_B").
    /// Empty for void elements.
    close_name: []const u8 = "",
    /// Children nodes (for nested content).
    children: []const Node = &.{},
    /// Whether this is a void element (no closing tag).
    is_void: bool = false,
    /// Start source span (the `<tag>` part).
    start_source_span: ?ParseSourceSpan = null,
    /// End source span (the `</tag>` part).
    end_source_span: ?ParseSourceSpan = null,
};

/// A tag attribute (key=value).
pub const TagAttr = struct {
    name: []const u8,
    value: []const u8,
};

// ─── Placeholder ─────────────────────────────────────────────

/// A placeholder for an interpolated expression ({{ name }} → PH).
/// Direct port of `Placeholder` class in the TS source.
pub const Placeholder = struct {
    /// The expression text (e.g. "name" for {{ name }}).
    value: []const u8,
    /// The placeholder name (e.g. "PH", "PH_1").
    name: []const u8,
};

// ─── IcuPlaceholder ──────────────────────────────────────────

/// A placeholder for an ICU expression (used when ICU is not the root).
/// Direct port of `IcuPlaceholder` class in the TS source.
pub const IcuPlaceholder = struct {
    /// The ICU expression value.
    value: *const Icu,
    /// The placeholder name (e.g. "ICU", "ICU_1").
    name: []const u8,
    /// Optional reference to the previous message (for `setI18nRefs()`).
    previous_message: ?*const Message = null,
};

// ─── BlockPlaceholder ────────────────────────────────────────

/// A placeholder for a block (@if, @for) in an i18n message.
/// Direct port of `BlockPlaceholder` class in the TS source.
pub const BlockPlaceholder = struct {
    /// Block name: "if", "for", "switch", etc.
    name: []const u8,
    /// Block parameters (e.g. ["condition"] for @if(condition)).
    parameters: []const []const u8 = &.{},
    /// Placeholder name for the start of the block.
    start_name: []const u8,
    /// Placeholder name for the close of the block.
    close_name: []const u8,
    /// Children nodes (the block body).
    children: []const Node = &.{},
    /// Start source span (the `@if(...)` part).
    start_source_span: ?ParseSourceSpan = null,
    /// End source span (the `}` part).
    end_source_span: ?ParseSourceSpan = null,
};

// ─── Message ─────────────────────────────────────────────────

/// I18nMeta — either a Message (root) or a Node (part of a message).
/// Direct port of `I18nMeta` type in the TS source.
pub const I18nMeta = union(enum) {
    message: *Message,
    node: *const Node,
};

/// A translatable message extracted from a template.
/// Direct port of `Message` class in the TS source.
pub const Message = struct {
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
    /// Unique ID (custom or computed).
    id: []const u8 = "",
    /// Legacy IDs for backward compatibility.
    legacy_ids: []const []const u8 = &.{},
    /// Serialized message string (computed from nodes via `serializeMessage`).
    message_string: []const u8 = "",
    /// Source locations.
    sources: []const MessageSpan = &.{},
    /// Allocator used for `message_string` and `sources` (null if not owned).
    /// Direct port of TS not-needed (V8 GC handles it).
    allocator: ?Allocator = null,
    /// Whether `message_string` is owned (allocated by `serializeMessage`).
    /// If false, the caller is responsible for freeing it.
    owns_message_string: bool = false,
    /// Whether `sources` is owned (allocated by `initWithNodes`).
    owns_sources: bool = false,
    /// Whether `id` is owned (allocated by `computeDigest`).
    owns_id: bool = false,
    /// Whether `nodes` is owned (allocated by `toOwnedSlice` in `initWithNodes`).
    owns_nodes: bool = false,

    /// Full constructor — direct port of `Message` constructor in the TS source.
    /// Computes `id` (from customId) and `messageString` (from nodes).
    /// Computes `sources` from the first/last node source spans.
    pub fn initWithNodes(
        allocator: Allocator,
        nodes: []const Node,
        placeholders: std.StringHashMap(MessagePlaceholder),
        placeholder_to_message: std.StringHashMap(*Message),
        meaning: []const u8,
        description: []const u8,
        custom_id: []const u8,
    ) !Message {
        var msg = Message{
            .nodes = nodes,
            .placeholders = placeholders,
            .placeholder_to_message = placeholder_to_message,
            .meaning = meaning,
            .description = description,
            .custom_id = custom_id,
            .id = custom_id,
            .message_string = try serializeMessage(allocator, nodes),
            .allocator = allocator,
            .owns_message_string = true,
            .owns_nodes = true,
        };

        // Compute sources from first/last node spans (direct port of lines 50-62 in TS).
        // Note: Zig ParseLocation doesn't carry file.url; file_path is left empty
        // and callers can patch it later via updateSourceFile().
        if (nodes.len > 0) {
            const first = nodes[0];
            const last = nodes[nodes.len - 1];
            const src = MessageSpan{
                .file_path = "",
                .start_line = first.source_span.start.line + 1,
                .start_col = first.source_span.start.col + 1,
                .end_line = last.source_span.end.line + 1,
                .end_col = first.source_span.start.col + 1,
            };
            const sources = try allocator.alloc(MessageSpan, 1);
            sources[0] = src;
            msg.sources = sources;
            msg.owns_sources = true;
        }

        return msg;
    }

    /// Simple init — creates empty placeholder maps. Used by tests and simple flows.
    pub fn init(allocator: Allocator) Message {
        return .{
            .placeholders = std.StringHashMap(MessagePlaceholder).init(allocator),
            .placeholder_to_message = std.StringHashMap(*Message).init(allocator),
        };
    }

    /// Alias for symmetry with TS API.
    pub fn initSimple(allocator: Allocator) Message {
        return init(allocator);
    }

    pub fn deinit(self: *Message) void {
        if (self.allocator) |a| {
            if (self.owns_message_string and self.message_string.len > 0) {
                a.free(self.message_string);
                self.owns_message_string = false;
            }
            if (self.owns_sources and self.sources.len > 0) {
                a.free(self.sources);
                self.owns_sources = false;
            }
            if (self.owns_id and self.id.len > 0) {
                a.free(self.id);
                self.owns_id = false;
            }
            if (self.owns_nodes and self.nodes.len > 0) {
                a.free(self.nodes);
                self.owns_nodes = false;
            }
        }
        self.placeholders.deinit();
        self.placeholder_to_message.deinit();
    }
};

// ─── Visitor interface ───────────────────────────────────────

/// Visitor interface for walking i18n message nodes.
/// Direct port of `Visitor` interface in the TS source.
///
/// Each method takes a `*const Node` and a context pointer.
/// The visitor dispatches based on `node.kind`.
pub const Visitor = struct {
    ctx: *anyopaque,
    visit_text: *const fn (ctx: *anyopaque, node: *const Node) anyerror!void,
    visit_container: *const fn (ctx: *anyopaque, node: *const Node) anyerror!void,
    visit_icu: *const fn (ctx: *anyopaque, node: *const Node) anyerror!void,
    visit_tag_placeholder: *const fn (ctx: *anyopaque, node: *const Node) anyerror!void,
    visit_placeholder: *const fn (ctx: *anyopaque, node: *const Node) anyerror!void,
    visit_icu_placeholder: *const fn (ctx: *anyopaque, node: *const Node) anyerror!void,
    visit_block_placeholder: *const fn (ctx: *anyopaque, node: *const Node) anyerror!void,
};

// ─── CloneVisitor ────────────────────────────────────────────

/// Clone the AST — direct port of `CloneVisitor` class in the TS source.
/// Returns a deep copy of each node.
pub const CloneVisitor = struct {
    allocator: Allocator,
    arena: ?*std.heap.ArenaAllocator = null,

    pub fn init(allocator: Allocator) CloneVisitor {
        return .{ .allocator = allocator };
    }

    /// Clone a list of nodes — direct port of `CloneVisitor.visit*` methods.
    pub fn cloneNodes(self: *CloneVisitor, nodes: []const Node) Allocator.Error![]const Node {
        var result = try self.allocator.alloc(Node, nodes.len);
        for (nodes, 0..) |node, i| {
            result[i] = try self.cloneNode(&node);
        }
        return result;
    }

    /// Clone a single node — dispatches based on kind.
    pub fn cloneNode(self: *CloneVisitor, node: *const Node) Allocator.Error!Node {
        const a = self.allocator;
        return switch (node.data) {
            .text => |t| Node{
                .kind = .text,
                .source_span = node.source_span,
                .data = .{ .text = .{ .value = t.value } },
            },
            .container => |c| Node{
                .kind = .container,
                .source_span = node.source_span,
                .data = .{ .container = .{
                    .children = try self.cloneNodes(c.children),
                } },
            },
            .icu => |icu| blk: {
                var cases = try a.alloc(IcuCase, icu.cases.len);
                for (icu.cases, 0..) |c, i| {
                    cases[i] = .{
                        .value = c.value,
                        .children = try self.cloneNodes(c.children),
                    };
                }
                break :blk Node{
                    .kind = .icu,
                    .source_span = node.source_span,
                    .data = .{ .icu = .{
                        .expression = icu.expression,
                        .type = icu.type,
                        .cases = cases,
                        .expression_placeholder = icu.expression_placeholder,
                    } },
                };
            },
            .tag_placeholder => |tp| Node{
                .kind = .tag_placeholder,
                .source_span = node.source_span,
                .data = .{ .tag_placeholder = .{
                    .tag = tp.tag,
                    .attrs = tp.attrs,
                    .start_name = tp.start_name,
                    .close_name = tp.close_name,
                    .children = try self.cloneNodes(tp.children),
                    .is_void = tp.is_void,
                    .start_source_span = tp.start_source_span,
                    .end_source_span = tp.end_source_span,
                } },
            },
            .placeholder => |ph| Node{
                .kind = .placeholder,
                .source_span = node.source_span,
                .data = .{ .placeholder = .{
                    .value = ph.value,
                    .name = ph.name,
                } },
            },
            .icu_placeholder => |iph| Node{
                .kind = .icu_placeholder,
                .source_span = node.source_span,
                .data = .{ .icu_placeholder = .{
                    .value = iph.value,
                    .name = iph.name,
                    .previous_message = iph.previous_message,
                } },
            },
            .block_placeholder => |bp| Node{
                .kind = .block_placeholder,
                .source_span = node.source_span,
                .data = .{ .block_placeholder = .{
                    .name = bp.name,
                    .parameters = bp.parameters,
                    .start_name = bp.start_name,
                    .close_name = bp.close_name,
                    .children = try self.cloneNodes(bp.children),
                    .start_source_span = bp.start_source_span,
                    .end_source_span = bp.end_source_span,
                } },
            },
        };
    }
};

// ─── RecurseVisitor ──────────────────────────────────────────

/// Visit all the nodes recursively — direct port of `RecurseVisitor` class.
/// Walks children of containers, ICUs, tag/block placeholders.
pub const RecurseVisitor = struct {
    /// Recursively walk a list of nodes.
    pub fn visitAllNodes(nodes: []const Node) void {
        for (nodes) |*node| {
            visitNode(node);
        }
    }

    /// Recursively walk a single node.
    pub fn visitNode(node: *const Node) void {
        switch (node.data) {
            .text => {},
            .container => |c| visitAllNodes(c.children),
            .icu => |icu| {
                for (icu.cases) |c| {
                    visitAllNodes(c.children);
                }
            },
            .tag_placeholder => |tp| visitAllNodes(tp.children),
            .placeholder => {},
            .icu_placeholder => {},
            .block_placeholder => |bp| visitAllNodes(bp.children),
        }
    }
};

// ─── LocalizeMessageStringVisitor ────────────────────────────

/// Serialize the message to the Localize backtick string format.
/// Direct port of `LocalizeMessageStringVisitor` class in the TS source.
///
/// Format:
///   - Text → value
///   - Container → children joined
///   - Icu → {$expressionPlaceholder, type, k1 {children} k2 {children}}
///   - TagPlaceholder → {$$startName}children{$$closeName}
///   - Placeholder → {$$name}
///   - IcuPlaceholder → {$$name}
///   - BlockPlaceholder → {$$startName}children{$$closeName}
pub fn serializeMessage(allocator: Allocator, nodes: []const Node) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    for (nodes) |node| {
        try serializeNodeLocalize(&buf, &node);
    }
    return buf.toOwnedSlice();
}

/// Serialize a node using the Localize format.
fn serializeNodeLocalize(buf: *std.array_list.Managed(u8), node: *const Node) !void {
    switch (node.data) {
        .text => |t| try buf.appendSlice(t.value),
        .container => |c| {
            for (c.children) |child| {
                try serializeNodeLocalize(buf, &child);
            }
        },
        .icu => |icu| {
            try buf.appendSlice("{");
            try buf.appendSlice(icu.expression_placeholder);
            try buf.appendSlice(", ");
            try buf.appendSlice(icu.type);
            try buf.appendSlice(", ");
            for (icu.cases, 0..) |c, i| {
                if (i > 0) try buf.append(' ');
                try buf.appendSlice(c.value);
                try buf.appendSlice(" {");
                for (c.children) |child| {
                    try serializeNodeLocalize(buf, &child);
                }
                try buf.appendSlice("}");
            }
            try buf.appendSlice("}");
        },
        .tag_placeholder => |tp| {
            try buf.appendSlice("{$");
            try buf.appendSlice(tp.start_name);
            try buf.appendSlice("}");
            for (tp.children) |child| {
                try serializeNodeLocalize(buf, &child);
            }
            if (!tp.is_void and tp.close_name.len > 0) {
                try buf.appendSlice("{$");
                try buf.appendSlice(tp.close_name);
                try buf.appendSlice("}");
            }
        },
        .placeholder => |ph| {
            try buf.appendSlice("{$");
            try buf.appendSlice(ph.name);
            try buf.appendSlice("}");
        },
        .icu_placeholder => |iph| {
            try buf.appendSlice("{$");
            try buf.appendSlice(iph.name);
            try buf.appendSlice("}");
        },
        .block_placeholder => |bp| {
            try buf.appendSlice("{$");
            try buf.appendSlice(bp.start_name);
            try buf.appendSlice("}");
            for (bp.children) |child| {
                try serializeNodeLocalize(buf, &child);
            }
            try buf.appendSlice("{$");
            try buf.appendSlice(bp.close_name);
            try buf.appendSlice("}");
        },
    }
}

/// Serialize a message to a string representation.
/// Alias for `serializeMessage` — matches the TS API name.
pub fn serializeMessageToString(allocator: Allocator, nodes: []const Node) ![]const u8 {
    return serializeMessage(allocator, nodes);
}

// ─── XML-like serializer (for digest computation) ────────────

/// Serialize the i18n AST to an XML-like format for UID generation.
/// Direct port of `_SerializerVisitor` class in `digest.ts`.
///
/// Format:
///   - Text → value
///   - Container → [child1, child2, ...]
///   - Icu → {expression, type, k1 {children}, k2 {children}}
///   - TagPlaceholder (void) → <ph tag name="startName"/>
///   - TagPlaceholder (non-void) → <ph tag name="startName">children</ph name="closeName">
///   - Placeholder → <ph name="name">value</ph> or <ph name="name"/>
///   - IcuPlaceholder → <ph icu name="name">value</ph>
///   - BlockPlaceholder → <ph block name="startName">children</ph name="closeName">
pub fn serializeNodesXmlLike(allocator: Allocator, nodes: []const Node) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    for (nodes) |node| {
        try serializeNodeXmlLike(&buf, &node);
    }
    return buf.toOwnedSlice();
}

fn serializeNodeXmlLike(buf: *std.array_list.Managed(u8), node: *const Node) anyerror!void {
    switch (node.data) {
        .text => |t| try buf.appendSlice(t.value),
        .container => |c| {
            try buf.append('[');
            for (c.children, 0..) |child, i| {
                if (i > 0) try buf.appendSlice(", ");
                try serializeNodeXmlLike(buf, &child);
            }
            try buf.append(']');
        },
        .icu => |icu| {
            try buf.append('{');
            try buf.appendSlice(icu.expression);
            try buf.appendSlice(", ");
            try buf.appendSlice(icu.type);
            try buf.appendSlice(", ");
            for (icu.cases, 0..) |c, i| {
                if (i > 0) try buf.appendSlice(", ");
                try buf.appendSlice(c.value);
                try buf.appendSlice(" {");
                for (c.children) |child| {
                    try serializeNodeXmlLike(buf, &child);
                }
                try buf.appendSlice("}");
            }
            try buf.append('}');
        },
        .tag_placeholder => |tp| {
            if (tp.is_void) {
                try buf.appendSlice("<ph tag name=\"");
                try buf.appendSlice(tp.start_name);
                try buf.appendSlice("\"/>");
            } else {
                try buf.appendSlice("<ph tag name=\"");
                try buf.appendSlice(tp.start_name);
                try buf.appendSlice("\">");
                for (tp.children, 0..) |child, i| {
                    if (i > 0) try buf.appendSlice(", ");
                    try serializeNodeXmlLike(buf, &child);
                }
                try buf.appendSlice("</ph name=\"");
                try buf.appendSlice(tp.close_name);
                try buf.appendSlice("\">");
            }
        },
        .placeholder => |ph| {
            if (ph.value.len > 0) {
                try buf.appendSlice("<ph name=\"");
                try buf.appendSlice(ph.name);
                try buf.appendSlice("\">");
                try buf.appendSlice(ph.value);
                try buf.appendSlice("</ph>");
            } else {
                try buf.appendSlice("<ph name=\"");
                try buf.appendSlice(ph.name);
                try buf.appendSlice("\"/>");
            }
        },
        .icu_placeholder => |iph| {
            try buf.appendSlice("<ph icu name=\"");
            try buf.appendSlice(iph.name);
            try buf.appendSlice("\">");
            // Serialize the inner ICU value
            const icu_node = Node{
                .kind = .icu,
                .source_span = emptySpan(),
                .data = .{ .icu = iph.value.* },
            };
            try serializeNodeXmlLike(buf, &icu_node);
            try buf.appendSlice("</ph>");
        },
        .block_placeholder => |bp| {
            try buf.appendSlice("<ph block name=\"");
            try buf.appendSlice(bp.start_name);
            try buf.appendSlice("\">");
            for (bp.children, 0..) |child, i| {
                if (i > 0) try buf.appendSlice(", ");
                try serializeNodeXmlLike(buf, &child);
            }
            try buf.appendSlice("</ph name=\"");
            try buf.appendSlice(bp.close_name);
            try buf.appendSlice("\">");
        },
    }
}

/// Serialize nodes ignoring ICU expression content (for decimal digest).
/// Direct port of `_SerializerIgnoreIcuExpVisitor` class in `digest.ts`.
pub fn serializeNodesXmlLikeIgnoreIcu(allocator: Allocator, nodes: []const Node) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    for (nodes) |node| {
        try serializeNodeXmlLikeIgnoreIcu(&buf, &node);
    }
    return buf.toOwnedSlice();
}

fn serializeNodeXmlLikeIgnoreIcu(buf: *std.array_list.Managed(u8), node: *const Node) anyerror!void {
    switch (node.data) {
        .icu => |icu| {
            // Do not take the expression into account
            try buf.append('{');
            try buf.appendSlice(icu.type);
            try buf.appendSlice(", ");
            for (icu.cases, 0..) |c, i| {
                if (i > 0) try buf.appendSlice(", ");
                try buf.appendSlice(c.value);
                try buf.appendSlice(" {");
                for (c.children) |child| {
                    try serializeNodeXmlLikeIgnoreIcu(buf, &child);
                }
                try buf.appendSlice("}");
            }
            try buf.append('}');
        },
        else => try serializeNodeXmlLike(buf, node),
    }
}

// ─── Tests ──────────────────────────────────────────────────

fn emptySpan() ParseSourceSpan {
    return .{
        .start = .{ .offset = 0, .line = 0, .col = 0 },
        .end = .{ .offset = 0, .line = 0, .col = 0 },
        .full_start = .{ .start = 0, .end = 0 },
    };
}

test "Text node serialization (Localize format)" {
    const allocator = std.testing.allocator;
    var nodes = [_]Node{.{
        .kind = .text,
        .source_span = emptySpan(),
        .data = .{ .text = .{ .value = "Hello" } },
    }};
    const result = try serializeMessage(allocator, &nodes);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello", result);
}

test "Placeholder node serialization (Localize format)" {
    const allocator = std.testing.allocator;
    var nodes = [_]Node{.{
        .kind = .placeholder,
        .source_span = emptySpan(),
        .data = .{ .placeholder = .{ .value = "name", .name = "PH" } },
    }};
    const result = try serializeMessage(allocator, &nodes);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("{$PH}", result);
}

test "TagPlaceholder void serialization" {
    const allocator = std.testing.allocator;
    var nodes = [_]Node{.{
        .kind = .tag_placeholder,
        .source_span = emptySpan(),
        .data = .{ .tag_placeholder = .{
            .tag = "img",
            .start_name = "START_TAG_IMG",
            .is_void = true,
        } },
    }};
    const result = try serializeMessage(allocator, &nodes);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("{$START_TAG_IMG}", result);
}

test "TagPlaceholder non-void serialization" {
    const allocator = std.testing.allocator;
    var children = [_]Node{.{
        .kind = .text,
        .source_span = emptySpan(),
        .data = .{ .text = .{ .value = "Hello" } },
    }};
    var nodes = [_]Node{.{
        .kind = .tag_placeholder,
        .source_span = emptySpan(),
        .data = .{ .tag_placeholder = .{
            .tag = "b",
            .start_name = "START_TAG_B",
            .close_name = "CLOSE_TAG_B",
            .children = &children,
            .is_void = false,
        } },
    }};
    const result = try serializeMessage(allocator, &nodes);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("{$START_TAG_B}Hello{$CLOSE_TAG_B}", result);
}

test "BlockPlaceholder serialization" {
    const allocator = std.testing.allocator;
    var children = [_]Node{.{
        .kind = .text,
        .source_span = emptySpan(),
        .data = .{ .text = .{ .value = "Yes" } },
    }};
    var nodes = [_]Node{.{
        .kind = .block_placeholder,
        .source_span = emptySpan(),
        .data = .{ .block_placeholder = .{
            .name = "if",
            .start_name = "START_BLOCK_IF",
            .close_name = "CLOSE_BLOCK_IF",
            .children = &children,
        } },
    }};
    const result = try serializeMessage(allocator, &nodes);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("{$START_BLOCK_IF}Yes{$CLOSE_BLOCK_IF}", result);
}

test "IcuPlaceholder serialization" {
    const allocator = std.testing.allocator;
    var icu = Icu{
        .expression = "count",
        .type = "plural",
        .cases = &.{},
        .expression_placeholder = "VAR_plural",
    };
    var nodes = [_]Node{.{
        .kind = .icu_placeholder,
        .source_span = emptySpan(),
        .data = .{ .icu_placeholder = .{
            .value = &icu,
            .name = "ICU",
        } },
    }};
    const result = try serializeMessage(allocator, &nodes);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("{$ICU}", result);
}

test "Icu serialization with cases" {
    const allocator = std.testing.allocator;
    var one_children = [_]Node{.{
        .kind = .text,
        .source_span = emptySpan(),
        .data = .{ .text = .{ .value = "one item" } },
    }};
    var other_children = [_]Node{.{
        .kind = .text,
        .source_span = emptySpan(),
        .data = .{ .text = .{ .value = "many items" } },
    }};
    var cases = [_]IcuCase{
        .{ .value = "one", .children = &one_children },
        .{ .value = "other", .children = &other_children },
    };
    var nodes = [_]Node{.{
        .kind = .icu,
        .source_span = emptySpan(),
        .data = .{ .icu = .{
            .expression = "count",
            .type = "plural",
            .cases = &cases,
            .expression_placeholder = "VAR_plural",
        } },
    }};
    const result = try serializeMessage(allocator, &nodes);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("{VAR_plural, plural, one {one item} other {many items}}", result);
}

test "Container serialization" {
    const allocator = std.testing.allocator;
    var children = [_]Node{
        .{ .kind = .text, .source_span = emptySpan(), .data = .{ .text = .{ .value = "Hello " } } },
        .{ .kind = .placeholder, .source_span = emptySpan(), .data = .{ .placeholder = .{ .value = "name", .name = "PH" } } },
        .{ .kind = .text, .source_span = emptySpan(), .data = .{ .text = .{ .value = "!" } } },
    };
    var nodes = [_]Node{.{
        .kind = .container,
        .source_span = emptySpan(),
        .data = .{ .container = .{ .children = &children } },
    }};
    const result = try serializeMessage(allocator, &nodes);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello {$PH}!", result);
}

test "XmlLike serialization — Text" {
    const allocator = std.testing.allocator;
    var nodes = [_]Node{.{
        .kind = .text,
        .source_span = emptySpan(),
        .data = .{ .text = .{ .value = "Hello" } },
    }};
    const result = try serializeNodesXmlLike(allocator, &nodes);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello", result);
}

test "XmlLike serialization — Placeholder with value" {
    const allocator = std.testing.allocator;
    var nodes = [_]Node{.{
        .kind = .placeholder,
        .source_span = emptySpan(),
        .data = .{ .placeholder = .{ .value = "name", .name = "PH" } },
    }};
    const result = try serializeNodesXmlLike(allocator, &nodes);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("<ph name=\"PH\">name</ph>", result);
}

test "XmlLike serialization — Placeholder without value" {
    const allocator = std.testing.allocator;
    var nodes = [_]Node{.{
        .kind = .placeholder,
        .source_span = emptySpan(),
        .data = .{ .placeholder = .{ .value = "", .name = "PH" } },
    }};
    const result = try serializeNodesXmlLike(allocator, &nodes);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("<ph name=\"PH\"/>", result);
}

test "XmlLike serialization — TagPlaceholder void" {
    const allocator = std.testing.allocator;
    var nodes = [_]Node{.{
        .kind = .tag_placeholder,
        .source_span = emptySpan(),
        .data = .{ .tag_placeholder = .{
            .tag = "img",
            .start_name = "START_TAG_IMG",
            .is_void = true,
        } },
    }};
    const result = try serializeNodesXmlLike(allocator, &nodes);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("<ph tag name=\"START_TAG_IMG\"/>", result);
}

test "XmlLike serialization — Container" {
    const allocator = std.testing.allocator;
    var children = [_]Node{
        .{ .kind = .text, .source_span = emptySpan(), .data = .{ .text = .{ .value = "a" } } },
        .{ .kind = .text, .source_span = emptySpan(), .data = .{ .text = .{ .value = "b" } } },
    };
    var nodes = [_]Node{.{
        .kind = .container,
        .source_span = emptySpan(),
        .data = .{ .container = .{ .children = &children } },
    }};
    const result = try serializeNodesXmlLike(allocator, &nodes);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("[a, b]", result);
}

test "CloneVisitor clones Text" {
    const allocator = std.testing.allocator;
    var cv = CloneVisitor.init(allocator);
    const original = Node{
        .kind = .text,
        .source_span = emptySpan(),
        .data = .{ .text = .{ .value = "Hello" } },
    };
    const cloned = try cv.cloneNode(&original);
    try std.testing.expectEqualStrings("Hello", cloned.data.text.value);
}

test "CloneVisitor clones Container" {
    const allocator = std.testing.allocator;
    var cv = CloneVisitor.init(allocator);
    var children = [_]Node{.{
        .kind = .text,
        .source_span = emptySpan(),
        .data = .{ .text = .{ .value = "Hello" } },
    }};
    const original = Node{
        .kind = .container,
        .source_span = emptySpan(),
        .data = .{ .container = .{ .children = &children } },
    };
    const cloned = try cv.cloneNode(&original);
    defer allocator.free(cloned.data.container.children);
    try std.testing.expectEqual(@as(usize, 1), cloned.data.container.children.len);
    try std.testing.expectEqualStrings("Hello", cloned.data.container.children[0].data.text.value);
}

test "RecurseVisitor walks tree" {
    var children = [_]Node{.{
        .kind = .text,
        .source_span = emptySpan(),
        .data = .{ .text = .{ .value = "Hello" } },
    }};
    var nodes = [_]Node{.{
        .kind = .container,
        .source_span = emptySpan(),
        .data = .{ .container = .{ .children = &children } },
    }};
    RecurseVisitor.visitAllNodes(&nodes);
    // Should not crash — walks all children
    try std.testing.expect(true);
}

test "Message.initSimple creates empty message" {
    var msg = Message.initSimple(std.testing.allocator);
    defer msg.deinit();
    try std.testing.expectEqual(@as(usize, 0), msg.nodes.len);
    try std.testing.expectEqualStrings("", msg.meaning);
}

test "TagAttr struct" {
    const attr = TagAttr{ .name = "class", .value = "active" };
    try std.testing.expectEqualStrings("class", attr.name);
    try std.testing.expectEqualStrings("active", attr.value);
}

test "IcuCase struct" {
    var children = [_]Node{.{
        .kind = .text,
        .source_span = emptySpan(),
        .data = .{ .text = .{ .value = "one" } },
    }};
    const case = IcuCase{ .value = "=1", .children = &children };
    try std.testing.expectEqualStrings("=1", case.value);
    try std.testing.expectEqual(@as(usize, 1), case.children.len);
}

test "serializeMessageToString alias" {
    const allocator = std.testing.allocator;
    var nodes = [_]Node{.{
        .kind = .text,
        .source_span = emptySpan(),
        .data = .{ .text = .{ .value = "Test" } },
    }};
    const result = try serializeMessageToString(allocator, &nodes);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Test", result);
}

test "XmlLike IgnoreIcu — Icu without expression" {
    const allocator = std.testing.allocator;
    var one_children = [_]Node{.{
        .kind = .text,
        .source_span = emptySpan(),
        .data = .{ .text = .{ .value = "one" } },
    }};
    var cases = [_]IcuCase{
        .{ .value = "one", .children = &one_children },
    };
    var nodes = [_]Node{.{
        .kind = .icu,
        .source_span = emptySpan(),
        .data = .{ .icu = .{
            .expression = "count",
            .type = "plural",
            .cases = &cases,
            .expression_placeholder = "VAR_plural",
        } },
    }};
    const result = try serializeNodesXmlLikeIgnoreIcu(allocator, &nodes);
    defer allocator.free(result);
    // Expression "count" should NOT be present
    try std.testing.expect(std.mem.indexOf(u8, result, "count") == null);
    // Type "plural" should be present
    try std.testing.expect(std.mem.indexOf(u8, result, "plural") != null);
}
