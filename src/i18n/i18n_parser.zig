/// i18n Parser — Convert HTML subtrees to i18n Messages
///
/// Port of: compiler/src/i18n/i18n_parser.ts (461 LoC)
///
/// Parses HTML AST nodes into i18n Message objects. Each Message contains
/// a tree of nodes (text, placeholders, containers, ICUs) that represent
/// the translatable content of a template.
///
/// The parser walks HTML nodes using a visitor pattern:
///   - Text → i18n.Text or Container of Text+Placeholder (for interpolation)
///   - Element → i18n.TagPlaceholder with children
///   - Attribute → i18n.Text or Container (for attribute value)
///   - ICU Expansion → i18n.Icu (nested) or i18n.IcuPlaceholder (top-level)
///   - Block → i18n.BlockPlaceholder
///   - Comment → null (skipped)
const std = @import("std");
const Allocator = std.mem.Allocator;

const i18n_ast = @import("i18n_ast.zig");
const placeholder = @import("serializers/placeholder.zig");
const source_span = @import("../source_span.zig");
const ParseSourceSpan = source_span.ParseSourceSpan;

// ─── Types ───────────────────────────────────────────────────

/// VisitNodeFn — a function that transforms an HTML node into an i18n node.
/// Direct port of `VisitNodeFn` type in the TS source.
///
/// In TS: `(html: html.Node, i18n: i18n.Node) => i18n.Node`
/// In Zig: We use an opaque context + function pointer for the same effect.
pub const VisitNodeFn = *const fn (ctx: *anyopaque, html_node: *const anyopaque, i18n_node: i18n_ast.Node) anyerror!i18n_ast.Node;

/// I18nMessageFactory — creates i18n messages from HTML nodes.
/// Direct port of `I18nMessageFactory` interface in the TS source.
pub const I18nMessageFactory = struct {
    visitor: *I18nVisitor,

    /// Create a Message from HTML nodes.
    /// Direct port of the function returned by `createI18nMessageFactory`.
    pub fn createMessage(
        self: *I18nMessageFactory,
        nodes: []const HtmlNodeInput,
        meaning: []const u8,
        description: []const u8,
        custom_id: []const u8,
        visit_node_fn: ?VisitNodeFn,
    ) !i18n_ast.Message {
        return self.visitor.toI18nMessage(nodes, meaning, description, custom_id, visit_node_fn);
    }
};

/// Input representation of an HTML node for the i18n parser.
/// This is a simplified view that the parser consumes — the real HTML AST
/// is in `ml_parser/ast.zig` and is converted to this view at the boundary.
pub const HtmlNodeInput = struct {
    kind: HtmlNodeKind,
    text: []const u8 = "",
    name: []const u8 = "",
    value: []const u8 = "",
    source_span: ParseSourceSpan,
    children: []const HtmlNodeInput = &.{},
    /// For interpolation tokens: [start_marker, expression, end_marker].
    interpolation_parts: []const []const u8 = &.{},
    /// ICU-specific fields.
    icu_switch_value: []const u8 = "",
    icu_type: []const u8 = "",
    icu_cases: []const IcuCaseInput = &.{},
    /// Block parameters (e.g. ["condition"] for @if(condition)).
    block_parameters: []const []const u8 = &.{},
};

pub const HtmlNodeKind = enum {
    text,
    element,
    attribute,
    comment,
    expansion, // ICU
    expansion_case,
    block,
    block_parameter,
    let_declaration,
};

/// Input representation of an ICU case.
pub const IcuCaseInput = struct {
    value: []const u8,
    expression: []const HtmlNodeInput,
    source_span: ParseSourceSpan,
};

// ─── I18nMessageVisitorContext ───────────────────────────────

/// Context for the i18n message visitor.
/// Direct port of `I18nMessageVisitorContext` interface in the TS source.
pub const I18nMessageVisitorContext = struct {
    is_icu: bool = false,
    icu_depth: u32 = 0,
    placeholder_registry: placeholder.PlaceholderRegistry,
    placeholder_to_content: std.StringHashMap(i18n_ast.MessagePlaceholder),
    placeholder_to_message: std.StringHashMap(*i18n_ast.Message),
    visit_node_fn: ?VisitNodeFn = null,
    visit_node_ctx: ?*anyopaque = null,

    pub fn init(allocator: Allocator) I18nMessageVisitorContext {
        return .{
            .placeholder_registry = placeholder.PlaceholderRegistry.init(allocator),
            .placeholder_to_content = std.StringHashMap(i18n_ast.MessagePlaceholder).init(allocator),
            .placeholder_to_message = std.StringHashMap(*i18n_ast.Message).init(allocator),
        };
    }

    pub fn deinit(self: *I18nMessageVisitorContext) void {
        self.placeholder_registry.deinit();
        self.placeholder_to_content.deinit();
        self.placeholder_to_message.deinit();
    }
};

// ─── createI18nMessageFactory ────────────────────────────────

/// Create an i18n message factory.
/// Direct port of `createI18nMessageFactory(retainEmptyTokens, preserveExpressionWhitespace)` in the TS source.
pub fn createI18nMessageFactory(
    allocator: Allocator,
    retain_empty_tokens: bool,
    preserve_expression_whitespace: bool,
) !I18nMessageFactory {
    const visitor = try allocator.create(I18nVisitor);
    visitor.* = I18nVisitor.init(allocator, retain_empty_tokens, preserve_expression_whitespace);
    return .{ .visitor = visitor };
}

// ─── noopVisitNodeFn ─────────────────────────────────────────

/// Noop visit node function — returns the i18n node unchanged.
/// Direct port of `noopVisitNodeFn` in the TS source.
pub fn noopVisitNodeFn(
    _: *anyopaque,
    _: *const anyopaque,
    i18n_node: i18n_ast.Node,
) !i18n_ast.Node {
    return i18n_node;
}

// ─── I18nVisitor ─────────────────────────────────────────────

/// I18nVisitor — walks HTML AST and builds i18n Message.
/// Direct port of `_I18nVisitor` class in the TS source.
///
/// The visitor implements the HTML visitor interface and converts each
/// HTML node into the corresponding i18n node type:
///   - visitText → Text or Container (with interpolation Placeholders)
///   - visitElement/visitComponent → TagPlaceholder (via _visitElementLike)
///   - visitAttribute → Text or Container (with interpolation Placeholders)
///   - visitExpansion (ICU) → Icu (nested) or IcuPlaceholder (top-level)
///   - visitBlock → BlockPlaceholder (or Container for @switch)
///   - visitComment → null (skipped)
pub const I18nVisitor = struct {
    allocator: Allocator,
    retain_empty_tokens: bool = false,
    preserve_expression_whitespace: bool = false,

    pub fn init(
        allocator: Allocator,
        retain_empty_tokens: bool,
        preserve_expression_whitespace: bool,
    ) I18nVisitor {
        return .{
            .allocator = allocator,
            .retain_empty_tokens = retain_empty_tokens,
            .preserve_expression_whitespace = preserve_expression_whitespace,
        };
    }

    /// Convert HTML nodes to an i18n Message.
    /// Direct port of `toI18nMessage(nodes, meaning, description, customId, visitNodeFn)`.
    pub fn toI18nMessage(
        self: *I18nVisitor,
        nodes: []const HtmlNodeInput,
        meaning: []const u8,
        description: []const u8,
        custom_id: []const u8,
        visit_node_fn: ?VisitNodeFn,
    ) !i18n_ast.Message {
        var context = I18nMessageVisitorContext.init(self.allocator);
        // NOTE: We do NOT free placeholder_registry here because the
        // placeholder names (start_name, close_name, etc.) are allocated
        // by the registry and referenced by the returned Message's nodes.
        // Freeing the registry would create dangling pointers.
        context.is_icu = nodes.len == 1 and nodes[0].kind == .expansion;
        context.visit_node_fn = visit_node_fn;

        var i18nodes = std.array_list.Managed(i18n_ast.Node).init(self.allocator);
        defer i18nodes.deinit();

        for (nodes) |node| {
            if (try self.visitAny(&node, &context)) |result| {
                try i18nodes.append(result);
            }
        }

        return try i18n_ast.Message.initWithNodes(
            self.allocator,
            try i18nodes.toOwnedSlice(),
            context.placeholder_to_content,
            context.placeholder_to_message,
            meaning,
            description,
            custom_id,
        );
    }

    /// Dispatch to the correct visit method based on node kind.
    /// Direct port of the `html.Visitor` interface dispatch.
    fn visitAny(
        self: *I18nVisitor,
        node: *const HtmlNodeInput,
        context: *I18nMessageVisitorContext,
    ) anyerror!?i18n_ast.Node {
        return switch (node.kind) {
            .text => try self.visitText(node, context),
            .element => try self.visitElement(node, context),
            .attribute => try self.visitAttribute(node, context),
            .comment => try self.visitComment(node, context),
            .expansion => try self.visitExpansion(node, context),
            .expansion_case => return error.UnreachableCode,
            .block => try self.visitBlock(node, context),
            .block_parameter => return error.UnreachableCode,
            .let_declaration => try self.visitLetDeclaration(node, context),
        };
    }

    /// Visit an element HTML node — direct port of `visitElement(el, context)`.
    pub fn visitElement(
        self: *I18nVisitor,
        el: *const HtmlNodeInput,
        context: *I18nMessageVisitorContext,
    ) anyerror!?i18n_ast.Node {
        return try self.visitElementLike(el, context);
    }

    /// Visit an element-like node (element or component).
    /// Direct port of `_visitElementLike(node, context)` in the TS source.
    ///
    /// Creates a TagPlaceholder with:
    ///   - start_name (e.g. "START_TAG_DIV")
    ///   - close_name (e.g. "CLOSE_TAG_DIV") — empty for void elements
    ///   - children (visited recursively)
    ///   - is_void flag
    fn visitElementLike(
        self: *I18nVisitor,
        node: *const HtmlNodeInput,
        context: *I18nMessageVisitorContext,
    ) anyerror!?i18n_ast.Node {
        // Visit children
        var children = std.array_list.Managed(i18n_ast.Node).init(self.allocator);
        defer children.deinit();
        for (node.children) |child| {
            if (try self.visitAny(&child, context)) |result| {
                try children.append(result);
            }
        }

        const node_name = node.name;
        const is_void = isVoidElement(node_name);

        const start_ph_name = try context.placeholder_registry.getStartTagPlaceholderName(
            node_name,
            is_void,
        );
        try context.placeholder_to_content.put(start_ph_name, .{
            .text = node_name,
            .source_span = .{ .start = node.source_span.full_start.start, .end = node.source_span.full_start.end },
        });

        var close_ph_name: []const u8 = "";
        if (!is_void) {
            close_ph_name = try context.placeholder_registry.getCloseTagPlaceholderName(node_name);
            try context.placeholder_to_content.put(close_ph_name, .{
                .text = try std.fmt.allocPrint(self.allocator, "</{s}>", .{node_name}),
                .source_span = .{ .start = node.source_span.full_start.start, .end = node.source_span.full_start.end },
            });
        }

        var node_data = i18n_ast.TagPlaceholder{
            .tag = node_name,
            .start_name = start_ph_name,
            .close_name = close_ph_name,
            .children = try children.toOwnedSlice(),
            .is_void = is_void,
        };
        _ = &node_data;

        return i18n_ast.Node{
            .kind = .tag_placeholder,
            .source_span = node.source_span,
            .data = .{ .tag_placeholder = node_data },
        };
    }

    /// Visit an attribute HTML node — direct port of `visitAttribute(attribute, context)`.
    pub fn visitAttribute(
        self: *I18nVisitor,
        attr: *const HtmlNodeInput,
        context: *I18nMessageVisitorContext,
    ) !?i18n_ast.Node {
        // If no interpolation tokens, just create a Text node.
        if (attr.interpolation_parts.len == 0) {
            const node = i18n_ast.Node{
                .kind = .text,
                .source_span = attr.source_span,
                .data = .{ .text = .{ .value = attr.value } },
            };
            return try self.applyVisitFn(context, attr, node);
        }

        // Otherwise, visit with interpolation.
        const node = try self.visitTextWithInterpolation(
            attr.interpolation_parts,
            attr.source_span,
            context,
        );
        return try self.applyVisitFn(context, attr, node);
    }

    /// Visit a text HTML node — direct port of `visitText(text, context)`.
    pub fn visitText(
        self: *I18nVisitor,
        text: *const HtmlNodeInput,
        context: *I18nMessageVisitorContext,
    ) !?i18n_ast.Node {
        // If no interpolation tokens, just create a Text node.
        if (text.interpolation_parts.len == 0) {
            const node = i18n_ast.Node{
                .kind = .text,
                .source_span = text.source_span,
                .data = .{ .text = .{ .value = text.text } },
            };
            return try self.applyVisitFn(context, text, node);
        }

        // Otherwise, visit with interpolation.
        const node = try self.visitTextWithInterpolation(
            text.interpolation_parts,
            text.source_span,
            context,
        );
        return try self.applyVisitFn(context, text, node);
    }

    /// Visit a comment HTML node — direct port of `visitComment(comment, context)`.
    /// Returns null (comments are skipped).
    pub fn visitComment(
        self: *I18nVisitor,
        comment: *const HtmlNodeInput,
        context: *I18nMessageVisitorContext,
    ) !?i18n_ast.Node {
        _ = self;
        _ = context;
        _ = comment;
        return null;
    }

    /// Visit an ICU expansion — direct port of `visitExpansion(icu, context)`.
    ///
    /// If the ICU is at the top level (not nested), returns an IcuPlaceholder.
    /// If the ICU is nested (inside another ICU or is the root), returns an Icu node.
    pub fn visitExpansion(
        self: *I18nVisitor,
        icu: *const HtmlNodeInput,
        context: *I18nMessageVisitorContext,
    ) !?i18n_ast.Node {
        context.icu_depth += 1;
        defer context.icu_depth -= 1;

        // Build ICU cases
        var cases = try self.allocator.alloc(i18n_ast.IcuCase, icu.icu_cases.len);
        for (icu.icu_cases, 0..) |caze, i| {
            var children = std.array_list.Managed(i18n_ast.Node).init(self.allocator);
            defer children.deinit();
            for (caze.expression) |child| {
                if (try self.visitAny(&child, context)) |result| {
                    try children.append(result);
                }
            }
            cases[i] = .{
                .value = caze.value,
                .children = try children.toOwnedSlice(),
            };
        }

        var i18n_icu = i18n_ast.Icu{
            .expression = icu.icu_switch_value,
            .type = icu.icu_type,
            .cases = cases,
        };

        if (context.is_icu or context.icu_depth > 0) {
            // Nested ICU — return an Icu node with expression placeholder.
            const exp_ph = try context.placeholder_registry.getUniquePlaceholder(
                try std.fmt.allocPrint(self.allocator, "VAR_{s}", .{icu.icu_type}),
            );
            i18n_icu.expression_placeholder = exp_ph;
            try context.placeholder_to_content.put(exp_ph, .{
                .text = icu.icu_switch_value,
                .source_span = .{ .start = icu.source_span.full_start.start, .end = icu.source_span.full_start.end },
            });

            const node = i18n_ast.Node{
                .kind = .icu,
                .source_span = icu.source_span,
                .data = .{ .icu = i18n_icu },
            };
            return try self.applyVisitFn(context, icu, node);
        }

        // Top-level ICU — return an IcuPlaceholder.
        const ph_name = try context.placeholder_registry.getPlaceholderName("ICU", icu.icu_switch_value);
        // Create a nested message for this ICU.
        const nested_msg = try self.allocator.create(i18n_ast.Message);
        nested_msg.* = try self.toI18nMessage(
            &[_]HtmlNodeInput{icu.*},
            "",
            "",
            "",
            null,
        );
        try context.placeholder_to_message.put(ph_name, nested_msg);

        const icu_ptr = try self.allocator.create(i18n_ast.Icu);
        icu_ptr.* = i18n_icu;

        const node = i18n_ast.Node{
            .kind = .icu_placeholder,
            .source_span = icu.source_span,
            .data = .{ .icu_placeholder = .{
                .value = icu_ptr,
                .name = ph_name,
            } },
        };
        return try self.applyVisitFn(context, icu, node);
    }

    /// Visit a block HTML node — direct port of `visitBlock(block, context)`.
    pub fn visitBlock(
        self: *I18nVisitor,
        block: *const HtmlNodeInput,
        context: *I18nMessageVisitorContext,
    ) !?i18n_ast.Node {
        var children = std.array_list.Managed(i18n_ast.Node).init(self.allocator);
        defer children.deinit();
        for (block.children) |child| {
            if (try self.visitAny(&child, context)) |result| {
                try children.append(result);
            }
        }

        // @switch blocks become a simple Container.
        if (std.mem.eql(u8, block.name, "switch")) {
            return i18n_ast.Node{
                .kind = .container,
                .source_span = block.source_span,
                .data = .{ .container = .{ .children = try children.toOwnedSlice() } },
            };
        }

        const start_ph_name = try context.placeholder_registry.getStartBlockPlaceholderName(block.name);
        const close_ph_name = try context.placeholder_registry.getCloseBlockPlaceholderName(block.name);

        try context.placeholder_to_content.put(start_ph_name, .{
            .text = block.name,
            .source_span = .{ .start = block.source_span.full_start.start, .end = block.source_span.full_start.end },
        });
        try context.placeholder_to_content.put(close_ph_name, .{
            .text = "}",
            .source_span = .{ .start = block.source_span.full_start.start, .end = block.source_span.full_start.end },
        });

        return i18n_ast.Node{
            .kind = .block_placeholder,
            .source_span = block.source_span,
            .data = .{ .block_placeholder = .{
                .name = block.name,
                .parameters = block.block_parameters,
                .start_name = start_ph_name,
                .close_name = close_ph_name,
                .children = try children.toOwnedSlice(),
            } },
        };
    }

    /// Visit a let declaration — direct port of `visitLetDeclaration(decl, context)`.
    /// Returns null (let declarations are skipped).
    pub fn visitLetDeclaration(
        self: *I18nVisitor,
        decl: *const HtmlNodeInput,
        context: *I18nMessageVisitorContext,
    ) !?i18n_ast.Node {
        _ = self;
        _ = context;
        _ = decl;
        return null;
    }

    /// Convert text and interpolated tokens into Text and Placeholder pieces.
    /// Direct port of `_visitTextWithInterpolation(tokens, sourceSpan, context, previousI18n)`.
    ///
    /// Returns a Container if there are interpolations, otherwise a single Text node.
    fn visitTextWithInterpolation(
        self: *I18nVisitor,
        tokens: []const []const u8,
        source_span_val: ParseSourceSpan,
        context: *I18nMessageVisitorContext,
    ) !i18n_ast.Node {
        var nodes = std.array_list.Managed(i18n_ast.Node).init(self.allocator);
        defer nodes.deinit();
        var has_interpolation = false;

        // Tokens come in groups of 3: [start_marker, expression, end_marker]
        // Text tokens are single-element.
        var i: usize = 0;
        while (i < tokens.len) {
            // Heuristic: if this token starts with "{{", it's an interpolation.
            if (std.mem.startsWith(u8, tokens[i], "{{") and i + 2 < tokens.len) {
                has_interpolation = true;
                const expression = tokens[i + 1];
                const base_name = extractPlaceholderName(expression) orelse "INTERPOLATION";
                const ph_name = try context.placeholder_registry.getPlaceholderName(base_name, expression);

                try context.placeholder_to_content.put(ph_name, .{
                    .text = try std.fmt.allocPrint(self.allocator, "{s}{s}{s}", .{ tokens[i], expression, tokens[i + 2] }),
                    .source_span = .{ .start = source_span_val.full_start.start, .end = source_span_val.full_start.end },
                });

                try nodes.append(i18n_ast.Node{
                    .kind = .placeholder,
                    .source_span = source_span_val,
                    .data = .{ .placeholder = .{
                        .value = expression,
                        .name = ph_name,
                    } },
                });
                i += 3;
            } else {
                // Text token
                if (tokens[i].len > 0 or self.retain_empty_tokens) {
                    try nodes.append(i18n_ast.Node{
                        .kind = .text,
                        .source_span = source_span_val,
                        .data = .{ .text = .{ .value = tokens[i] } },
                    });
                }
                i += 1;
            }
        }

        if (has_interpolation) {
            return i18n_ast.Node{
                .kind = .container,
                .source_span = source_span_val,
                .data = .{ .container = .{ .children = try nodes.toOwnedSlice() } },
            };
        }

        // Single text node
        if (nodes.items.len > 0) {
            return nodes.items[0];
        }

        // Empty — return an empty text node.
        return i18n_ast.Node{
            .kind = .text,
            .source_span = source_span_val,
            .data = .{ .text = .{ .value = "" } },
        };
    }

    /// Apply the visit_node_fn if set, otherwise return the node unchanged.
    fn applyVisitFn(
        self: *I18nVisitor,
        context: *I18nMessageVisitorContext,
        html_node: *const HtmlNodeInput,
        i18n_node: i18n_ast.Node,
    ) !i18n_ast.Node {
        _ = self;
        if (context.visit_node_fn) |fn_ptr| {
            if (context.visit_node_ctx) |ctx| {
                return fn_ptr(ctx, @ptrCast(html_node), i18n_node);
            }
        }
        return i18n_node;
    }
};

// ─── reusePreviousSourceSpans ────────────────────────────────

/// Re-use the source-spans from `previousI18n` metadata for the `nodes`.
/// Direct port of `reusePreviousSourceSpans(nodes, previousI18n)` in the TS source.
///
/// Whitespace removal can invalidate the source-spans of interpolation nodes,
/// so we reuse the source-span stored from a previous pass before the whitespace was removed.
pub fn reusePreviousSourceSpans(
    nodes: []i18n_ast.Node,
    previous_i18n: ?i18n_ast.I18nMeta,
) void {
    if (previous_i18n == null) return;
    const prev = previous_i18n.?;

    switch (prev) {
        .message => |msg| {
            // The `previousI18n` is an i18n `Message`, so we are processing an `Attribute` with i18n
            // metadata. The `Message` should consist only of a single `Container` that contains the
            // parts (`Text` and `Placeholder`) to process.
            if (msg.nodes.len != 1) return;
            if (msg.nodes[0].kind != .container) return;
            reuseFromContainer(msg.nodes[0].data.container, nodes);
        },
        .node => |n| {
            if (n.kind == .container) {
                reuseFromContainer(n.data.container, nodes);
            }
        },
    }
}

fn reuseFromContainer(container: i18n_ast.Container, nodes: []i18n_ast.Node) void {
    if (container.children.len != nodes.len) return;
    for (container.children, 0..) |prev_child, i| {
        if (prev_child.kind != nodes[i].kind) return;
        nodes[i].source_span = prev_child.source_span;
    }
}

// ─── extractPlaceholderName ──────────────────────────────────

/// Regex to extract placeholder name from `// i18n (...) ph="..."` comments.
/// Direct port of `_CUSTOM_PH_EXP` in the TS source.
const _CUSTOM_PH_EXP = "//[\\s\\S]*i18n[\\s\\S]*\\([\\s\\S]*ph[\\s\\S]*=[\\s\\S]*\"([\\s\\S]*?)\"[\\s\\S]*\\)";

/// Extract a custom placeholder name from an expression.
/// Direct port of `extractPlaceholderName(input)` in the TS source.
pub fn extractPlaceholderName(input: []const u8) ?[]const u8 {
    // Look for `// ... i18n ... ph="name"` pattern.
    // Simple implementation: find `ph="..."` and extract the name.
    const ph_marker = "ph=\"";
    var pos: usize = 0;
    while (pos < input.len) {
        if (std.mem.indexOfPos(u8, input, pos, ph_marker)) |idx| {
            const start = idx + ph_marker.len;
            if (start < input.len) {
                if (std.mem.indexOfScalarPos(u8, input, start, '"')) |end| {
                    return input[start..end];
                }
            }
            pos = idx + 1;
        } else {
            break;
        }
    }
    return null;
}

// ─── Helpers ─────────────────────────────────────────────────

/// Check if an HTML tag name is a void element (no closing tag).
/// Void elements: area, base, br, col, embed, hr, img, input, link, meta, param, source, track, wbr.
fn isVoidElement(name: []const u8) bool {
    const void_tags = [_][]const u8{
        "area", "base", "br",  "col",  "embed", "hr",    "img",
        "input", "link", "meta", "param", "source", "track", "wbr",
    };
    for (void_tags) |void_tag| {
        if (std.ascii.eqlIgnoreCase(name, void_tag)) return true;
    }
    return false;
}

// ─── Simple API (backwards-compat with previous stub) ────────

/// Simple parse — creates a Message from source text.
/// This is a convenience wrapper that creates a single Text node.
pub fn parse(
    allocator: Allocator,
    source: []const u8,
    meaning: []const u8,
    description: []const u8,
    custom_id: []const u8,
) !i18n_ast.Message {
    var visitor = I18nVisitor.init(allocator, false, false);
    var nodes = [_]HtmlNodeInput{.{
        .kind = .text,
        .text = source,
        .source_span = .{
            .start = .{ .offset = 0, .line = 0, .col = 0 },
            .end = .{ .offset = @intCast(source.len), .line = 0, .col = @intCast(source.len) },
            .full_start = .{ .start = 0, .end = @intCast(source.len) },
        },
    }};
    return visitor.toI18nMessage(&nodes, meaning, description, custom_id, null);
}

/// Parse a single HTML text node into an i18n Text node.
pub fn parseText(_: Allocator, text: []const u8) !i18n_ast.Text {
    return i18n_ast.Text{ .value = text };
}

/// Parse an interpolation into an i18n Placeholder node.
pub fn parseInterpolation(
    _: Allocator,
    expression: []const u8,
) !i18n_ast.Placeholder {
    return i18n_ast.Placeholder{
        .value = expression,
        .name = "INTERPOLATION",
    };
}

// ─── Tests ──────────────────────────────────────────────────

fn emptySpan() ParseSourceSpan {
    return .{
        .start = .{ .offset = 0, .line = 0, .col = 0 },
        .end = .{ .offset = 0, .line = 0, .col = 0 },
        .full_start = .{ .start = 0, .end = 0 },
    };
}

test "parse creates message with metadata" {
    const allocator = std.testing.allocator;
    var msg = try parse(allocator, "Hello", "greeting", "A greeting", "custom-id");
    defer msg.deinit();
    defer allocator.free(msg.nodes);
    try std.testing.expectEqualStrings("greeting", msg.meaning);
    try std.testing.expectEqualStrings("A greeting", msg.description);
    try std.testing.expectEqualStrings("custom-id", msg.custom_id);
}

test "createI18nMessageFactory" {
    const allocator = std.testing.allocator;
    const factory = try createI18nMessageFactory(allocator, true, false);
    defer allocator.destroy(factory.visitor);
    try std.testing.expect(factory.visitor.retain_empty_tokens);
    try std.testing.expect(!factory.visitor.preserve_expression_whitespace);
}

test "parseText creates text node" {
    const text = try parseText(std.testing.allocator, "Hello World");
    try std.testing.expectEqualStrings("Hello World", text.value);
}

test "parseInterpolation creates placeholder" {
    const ph = try parseInterpolation(std.testing.allocator, "name");
    try std.testing.expectEqualStrings("INTERPOLATION", ph.name);
    try std.testing.expectEqualStrings("name", ph.value);
}

test "I18nVisitor init" {
    const allocator = std.testing.allocator;
    const visitor = I18nVisitor.init(allocator, false, false);
    try std.testing.expect(!visitor.retain_empty_tokens);
    try std.testing.expect(!visitor.preserve_expression_whitespace);
}

test "I18nVisitor toI18nMessage — single text" {
    const allocator = std.testing.allocator;
    var visitor = I18nVisitor.init(allocator, false, false);
    var nodes = [_]HtmlNodeInput{.{
        .kind = .text,
        .text = "Hello World",
        .source_span = emptySpan(),
    }};
    var msg = try visitor.toI18nMessage(&nodes, "greeting", "A greeting", "custom-id", null);
    defer msg.deinit();
    defer allocator.free(msg.nodes);
    try std.testing.expectEqualStrings("greeting", msg.meaning);
    try std.testing.expectEqualStrings("Hello World", msg.message_string);
}

test "I18nVisitor visitElement — void element" {
    const allocator = std.testing.allocator;
    var visitor = I18nVisitor.init(allocator, false, false);
    var nodes = [_]HtmlNodeInput{.{
        .kind = .element,
        .name = "img",
        .source_span = emptySpan(),
    }};
    var msg = try visitor.toI18nMessage(&nodes, "", "", "", null);
    defer msg.deinit();
    defer allocator.free(msg.nodes);
    try std.testing.expectEqual(@as(usize, 1), msg.nodes.len);
    try std.testing.expectEqual(i18n_ast.NodeKind.tag_placeholder, msg.nodes[0].kind);
    try std.testing.expect(msg.nodes[0].data.tag_placeholder.is_void);
}

test "I18nVisitor visitElement — non-void element with children" {
    const allocator = std.testing.allocator;
    var visitor = I18nVisitor.init(allocator, false, false);
    var children = [_]HtmlNodeInput{.{
        .kind = .text,
        .text = "Hello",
        .source_span = emptySpan(),
    }};
    var nodes = [_]HtmlNodeInput{.{
        .kind = .element,
        .name = "div",
        .children = &children,
        .source_span = emptySpan(),
    }};
    var msg = try visitor.toI18nMessage(&nodes, "", "", "", null);
    defer msg.deinit();
    defer allocator.free(msg.nodes);
    defer allocator.free(msg.nodes[0].data.tag_placeholder.children);

    try std.testing.expectEqual(@as(usize, 1), msg.nodes.len);
    const tp = msg.nodes[0].data.tag_placeholder;
    try std.testing.expectEqualStrings("div", tp.tag);
    try std.testing.expect(!tp.is_void);
    // The message_string includes the tag placeholders in Localize format.
    try std.testing.expectEqualStrings("{$START_TAG_DIV}Hello{$CLOSE_TAG_DIV}", msg.message_string);
}

test "I18nVisitor visitComment returns null" {
    const allocator = std.testing.allocator;
    var visitor = I18nVisitor.init(allocator, false, false);
    var nodes = [_]HtmlNodeInput{.{
        .kind = .comment,
        .text = "comment",
        .source_span = emptySpan(),
    }};
    var msg = try visitor.toI18nMessage(&nodes, "", "", "", null);
    defer msg.deinit();
    defer allocator.free(msg.nodes);
    try std.testing.expectEqual(@as(usize, 0), msg.nodes.len);
}

test "I18nVisitor visitBlock — switch becomes container" {
    const allocator = std.testing.allocator;
    var visitor = I18nVisitor.init(allocator, false, false);
    var children = [_]HtmlNodeInput{.{
        .kind = .text,
        .text = "content",
        .source_span = emptySpan(),
    }};
    var nodes = [_]HtmlNodeInput{.{
        .kind = .block,
        .name = "switch",
        .children = &children,
        .source_span = emptySpan(),
    }};
    var msg = try visitor.toI18nMessage(&nodes, "", "", "", null);
    defer msg.deinit();
    defer allocator.free(msg.nodes);
    defer allocator.free(msg.nodes[0].data.container.children);

    try std.testing.expectEqual(@as(usize, 1), msg.nodes.len);
    try std.testing.expectEqual(i18n_ast.NodeKind.container, msg.nodes[0].kind);
}

test "I18nVisitor visitBlock — if becomes block_placeholder" {
    const allocator = std.testing.allocator;
    var visitor = I18nVisitor.init(allocator, false, false);
    var children = [_]HtmlNodeInput{.{
        .kind = .text,
        .text = "Yes",
        .source_span = emptySpan(),
    }};
    var nodes = [_]HtmlNodeInput{.{
        .kind = .block,
        .name = "if",
        .children = &children,
        .source_span = emptySpan(),
    }};
    var msg = try visitor.toI18nMessage(&nodes, "", "", "", null);
    defer msg.deinit();
    defer allocator.free(msg.nodes);
    defer allocator.free(msg.nodes[0].data.block_placeholder.children);

    try std.testing.expectEqual(@as(usize, 1), msg.nodes.len);
    try std.testing.expectEqual(i18n_ast.NodeKind.block_placeholder, msg.nodes[0].kind);
    try std.testing.expectEqualStrings("if", msg.nodes[0].data.block_placeholder.name);
}

test "extractPlaceholderName — no match" {
    const result = extractPlaceholderName("just a regular expression");
    try std.testing.expect(result == null);
}

test "extractPlaceholderName — with ph marker" {
    const result = extractPlaceholderName("// i18n (ph=\"customName\")");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("customName", result.?);
}

test "isVoidElement — known void tags" {
    try std.testing.expect(isVoidElement("img"));
    try std.testing.expect(isVoidElement("br"));
    try std.testing.expect(isVoidElement("input"));
    try std.testing.expect(isVoidElement("hr"));
    try std.testing.expect(isVoidElement("IMG")); // case-insensitive
}

test "isVoidElement — non-void tags" {
    try std.testing.expect(!isVoidElement("div"));
    try std.testing.expect(!isVoidElement("span"));
    try std.testing.expect(!isVoidElement("p"));
}

test "IcuCaseInput struct" {
    const case = IcuCaseInput{
        .value = "=1",
        .expression = &.{},
        .source_span = emptySpan(),
    };
    try std.testing.expectEqualStrings("=1", case.value);
}

test "HtmlNodeInput — text kind" {
    const node = HtmlNodeInput{
        .kind = .text,
        .text = "Hello",
        .source_span = emptySpan(),
    };
    try std.testing.expectEqual(HtmlNodeKind.text, node.kind);
    try std.testing.expectEqualStrings("Hello", node.text);
}

test "noopVisitNodeFn returns input unchanged" {
    const input = i18n_ast.Node{
        .kind = .text,
        .source_span = emptySpan(),
        .data = .{ .text = .{ .value = "test" } },
    };
    var ctx: u8 = 0;
    const html_node: u8 = 0;
    const result = try noopVisitNodeFn(@ptrCast(&ctx), @ptrCast(&html_node), input);
    try std.testing.expectEqualStrings("test", result.data.text.value);
}
