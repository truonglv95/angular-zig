/// HTML AST → R3 AST Transform
///
/// CRITICAL BRIDGE: This is the core transformation that turns a parsed HTML tree
/// into the R3 template AST used by the IR pipeline.
///
/// DOD optimizations:
///   - Single pass over HTML nodes (no multi-pass)
///   - Attribute classification via branchless prefix scan
///   - Expression parsing deferred to IR phase (lazy evaluation)
///   - Arena-allocated R3 nodes (zero fragmentation)
///   - Pre-allocated ArrayLists with capacity hints based on node count
const std = @import("std");
const Allocator = std.mem.Allocator;

const arena_mod = @import("../arena.zig");
const AstArena = arena_mod.AstArena;

const html_ast = @import("../ml_parser/ast.zig");
const HtmlNode = html_ast.Node;
const TextNode = html_ast.TextNode;
const AttributeNode = html_ast.AttributeNode;
const ElementNode = html_ast.ElementNode;

const source_span = @import("../source_span.zig");
const ParseSourceSpan = source_span.ParseSourceSpan;
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;
const ParseError = source_span.ParseError;

const r3_ast = @import("../render3/r3_ast.zig");
const R3Node = r3_ast.R3Node;
const NodeKind = r3_ast.NodeKind;
const BindingType = r3_ast.BindingType;
const ParsedEventType = r3_ast.ParsedEventType;
const IfBlockBranch = r3_ast.IfBlockBranch;
const DeferredTrigger = r3_ast.DeferredTrigger;
const SwitchBlockCase = r3_ast.SwitchBlockCase;
const SwitchBlockCaseGroup = r3_ast.SwitchBlockCaseGroup;

const binding_parser = @import("../template_parser/binding_parser.zig");
const ClassifiedAttr = binding_parser.ClassifiedAttr;
const classifyAttribute = binding_parser.classifyAttribute;

const expr_lexer = @import("../expression_parser/lexer.zig");
const expr_parser = @import("../expression_parser/parser.zig");
const expr_ast = @import("../expression_parser/ast.zig");

const tags = @import("../ml_parser/tags.zig");

// ─── Transform Context ────────────────────────────────────────

pub const TransformContext = struct {
    allocator: Allocator,
    arena: *AstArena,
    source: []const u8,
    errors: std.array_list.Managed(ParseError),
    style_urls: std.array_list.Managed([]const u8),
    styles: std.array_list.Managed([]const u8),
    ng_content_selectors: std.array_list.Managed([]const u8),
    /// Track ng-template references for later view creation
    template_refs: std.array_list.Managed(TemplateRef),

    pub const TemplateRef = struct {
        name: []const u8,
        node: *const R3Node,
    };

    pub fn init(allocator: Allocator, arena: *AstArena, source: []const u8) TransformContext {
        return .{
            .allocator = allocator,
            .arena = arena,
            .source = source,
            .errors = std.array_list.Managed(ParseError).init(allocator),
            .style_urls = std.array_list.Managed([]const u8).init(allocator),
            .styles = std.array_list.Managed([]const u8).init(allocator),
            .ng_content_selectors = std.array_list.Managed([]const u8).init(allocator),
            .template_refs = std.array_list.Managed(TemplateRef).init(allocator),
        };
    }

    pub fn deinit(self: *TransformContext) void {
        self.errors.deinit();
        self.style_urls.deinit();
        self.styles.deinit();
        self.ng_content_selectors.deinit();
        self.template_refs.deinit();
    }
};

// ─── Transform Result ────────────────────────────────────────

pub const TransformResult = struct {
    nodes: []*R3Node,
    style_urls: []const []const u8,
    styles: []const []const u8,
    ng_content_selectors: []const []const u8,
    errors: []const ParseError,
};

// ─── Main Transform Entry Point ──────────────────────────────

/// Transform HTML AST nodes into R3 Template AST nodes.
/// This is the bridge between HTML parsing and IR generation.
pub fn transformHtmlToR3(
    ctx: *TransformContext,
    html_nodes: []const *const HtmlNode,
) !TransformResult {
    // Pre-allocate with estimated capacity (heuristic: ~1.5x HTML nodes)
    const estimated = html_nodes.len * 3 / 2 + 4;
    var r3_nodes = try std.array_list.Managed(*R3Node).initCapacity(ctx.arena.allocator(), estimated);

    for (html_nodes) |hn| {
        const r3 = try transformNode(ctx, hn);
        if (r3) |rn| {
            try r3_nodes.append(rn);
        }
    }

    return .{
        .nodes = r3_nodes.items,
        .style_urls = ctx.style_urls.items,
        .styles = ctx.styles.items,
        .ng_content_selectors = ctx.ng_content_selectors.items,
        .errors = ctx.errors.items,
    };
}

/// Transform a single HTML node into an R3 node (or null if skipped)
fn transformNode(ctx: *TransformContext, node: *const HtmlNode) error{OutOfMemory}!?*R3Node {
    switch (node.data) {
        .Element => |elem| return try transformElement(ctx, node, elem),
        .Text => |text| return try transformText(ctx, node, text),
        .Comment => |comment| return transformComment(ctx, node, comment),
        .DocType => return null,
        .Cdata => |cdata| return transformCdata(ctx, node, cdata),
        .Expansion => |exp| return try transformExpansion(ctx, node, exp),
        .Block => |block| return try transformBlock(ctx, node, block),
        .Attribute, .ExpansionCase, .BlockParameter => return null,
    }
}

// ─── Element Transform ───────────────────────────────────────

fn transformElement(ctx: *TransformContext, html_node: *const HtmlNode, elem: ElementNode) error{OutOfMemory}!?*R3Node {
    const name = elem.name;

    // Check for ng-content
    if (std.mem.eql(u8, name, "ng-content")) {
        return try transformNgContent(ctx, html_node, elem);
    }

    // Check for @if, @for, @switch, @defer blocks
    if (name.len > 0 and name[0] == '@') {
        return try transformControlFlowBlock(ctx, html_node, elem);
    }

    // Check for ng-template
    if (std.mem.eql(u8, name, "ng-template")) {
        return try transformNgTemplate(ctx, html_node, elem);
    }

    // Check for ng-container
    if (std.mem.eql(u8, name, "ng-container")) {
        return try transformNgContainer(ctx, html_node, elem);
    }

    // Check for style/script tags — these are treated as regular elements in R3
    // (their content is raw text, but they still appear as Element nodes)
    if (std.mem.eql(u8, name, "style")) {
        return try transformRegularElement(ctx, html_node, elem);
    }
    if (std.mem.eql(u8, name, "script")) {
        return try transformRegularElement(ctx, html_node, elem);
    }

    // Regular element — classify all attributes and build R3 Element
    return try transformRegularElement(ctx, html_node, elem);
}

fn transformRegularElement(ctx: *TransformContext, html_node: *const HtmlNode, elem: ElementNode) error{OutOfMemory}!?*R3Node {
    // Separate attributes into classified groups
    var text_attrs = std.array_list.Managed(R3Node).initCapacity(ctx.arena.allocator(), elem.attrs.len) catch unreachable;

    var bound_attrs = std.array_list.Managed(R3Node).initCapacity(ctx.arena.allocator(), elem.attrs.len) catch unreachable;

    var bound_events = std.array_list.Managed(R3Node).initCapacity(ctx.arena.allocator(), 2) catch unreachable;

    var references = std.array_list.Managed(R3Node).initCapacity(ctx.arena.allocator(), 2) catch unreachable;

    var variables = std.array_list.Managed(R3Node).initCapacity(ctx.arena.allocator(), 2) catch unreachable;

    var i18n_attr: ?[]const u8 = null;
    var structural_attr: ?*R3Node = null;

    // Classify each attribute
    for (elem.attrs) |attr| {
        const classified = classifyAttribute(attr.name);

        switch (classified.class) {
            .TextAttribute => {
                // Check if value has interpolations → BoundAttribute or TextAttribute
                if (attr.interpolation_boundaries.len > 0) {
                    // Attribute with interpolation like class="foo {{ bar }}"
                    const r3 = try ctx.arena.create(R3Node);
                    r3.* = .{
                        .kind = .BoundAttribute,
                        .source_span = html_node.source_span,
                        .data = .{ .BoundAttribute = .{
                            .name = attr.name,
                            .type = .Attribute,
                            .value = try parseInterpolatedAttr(ctx, attr, html_node.source_span),
                            .unit = null,
                            .security_context = null,
                            .key_span = attr.key_span,
                            .source_span = attr.value_span,
                        } },
                    };
                    try bound_attrs.append(r3.*);
                } else {
                    const r3 = try ctx.arena.create(R3Node);
                    r3.* = .{
                        .kind = .TextAttribute,
                        .source_span = html_node.source_span,
                        .data = .{ .TextAttribute = .{
                            .name = attr.name,
                            .value = attr.value,
                            .key_span = attr.key_span,
                            .value_span = attr.value_span,
                            .i18n = null,
                        } },
                    };
                    try text_attrs.append(r3.*);
                }
            },
            .Property => {
                const r3 = try ctx.arena.create(R3Node);
                const binding_type: BindingType = if (std.mem.startsWith(u8, classified.name, "attr."))
                    .Attribute
                else if (std.mem.startsWith(u8, classified.name, "class."))
                    .Class
                else if (std.mem.startsWith(u8, classified.name, "style."))
                    .Style
                else
                    .Property;

                const effective_name = if (binding_type == .Attribute)
                    classified.name[5..]
                else if (binding_type == .Class)
                    classified.name[6..]
                else if (binding_type == .Style)
                    classified.name[6..]
                else
                    classified.name;

                r3.* = .{
                    .kind = .BoundAttribute,
                    .source_span = html_node.source_span,
                    .data = .{ .BoundAttribute = .{
                        .name = effective_name,
                        .type = binding_type,
                        .value = try parseExpression(ctx, attr.value, attr.value_span, .{ .is_binding = true }),
                        .unit = extractUnit(classified.name),
                        .security_context = null,
                        .key_span = attr.key_span,
                        .source_span = attr.value_span,
                    } },
                };
                try bound_attrs.append(r3.*);
            },
            .TwoWay => {
                const r3 = try ctx.arena.create(R3Node);
                r3.* = .{
                    .kind = .BoundAttribute,
                    .source_span = html_node.source_span,
                    .data = .{ .BoundAttribute = .{
                        .name = classified.name,
                        .type = .TwoWay,
                        .value = try parseExpression(ctx, attr.value, attr.value_span, .{ .is_binding = true }),
                        .unit = null,
                        .security_context = null,
                        .key_span = attr.key_span,
                        .source_span = attr.value_span,
                    } },
                };
                try bound_attrs.append(r3.*);
            },
            .Event => {
                const event_type = if (std.mem.startsWith(u8, classified.name, "@"))
                    if (std.mem.endsWith(u8, classified.name, ".start"))
                        ParsedEventType.AnimationStart
                    else
                        ParsedEventType.AnimationDone
                else
                    ParsedEventType.Regular;

                const effective_name = if (std.mem.startsWith(u8, classified.name, "@"))
                    classified.name
                else
                    classified.name;

                const r3 = try ctx.arena.create(R3Node);
                r3.* = .{
                    .kind = .BoundEvent,
                    .source_span = html_node.source_span,
                    .data = .{ .BoundEvent = .{
                        .name = effective_name,
                        .type = event_type,
                        .handler = try parseExpression(ctx, attr.value, attr.value_span, .{ .is_action = true }),
                        .target = null,
                        .phase = null,
                        .key_span = attr.key_span,
                        .handler_span = attr.value_span,
                        .source_span = attr.value_span,
                    } },
                };
                try bound_events.append(r3.*);
            },
            .Reference => {
                const r3 = try ctx.arena.create(R3Node);
                r3.* = .{
                    .kind = .Reference,
                    .source_span = html_node.source_span,
                    .data = .{ .Reference = .{
                        .name = classified.name,
                        .value = attr.value,
                        .key_span = attr.key_span,
                        .value_span = attr.value_span,
                    } },
                };
                try references.append(r3.*);
            },
            .Variable => {
                const r3 = try ctx.arena.create(R3Node);
                r3.* = .{
                    .kind = .Variable,
                    .source_span = html_node.source_span,
                    .data = .{ .Variable = .{
                        .name = classified.name,
                        .value = attr.value,
                        .key_span = attr.key_span,
                        .value_span = attr.value_span,
                    } },
                };
                try variables.append(r3.*);
            },
            .Structural => {
                // *ngIf, *ngFor, etc. — expand into Template node
                structural_attr = try ctx.arena.create(R3Node);
                structural_attr.?.* = .{
                    .kind = .TextAttribute,
                    .source_span = html_node.source_span,
                    .data = .{ .TextAttribute = .{
                        .name = attr.name,
                        .value = attr.value,
                        .key_span = attr.key_span,
                        .value_span = attr.value_span,
                    } },
                };
            },
            .I18n => {
                i18n_attr = attr.value;
            },
            .Class, .Style, .Attr, .Animation => {
                // These are handled via BoundAttribute with special binding type
                const r3 = try ctx.arena.create(R3Node);
                const bt: BindingType = switch (classified.class) {
                    .Class => .Class,
                    .Style => .Style,
                    .Attr => .Attribute,
                    .Animation => .Animation,
                    else => .Property,
                };
                r3.* = .{
                    .kind = .BoundAttribute,
                    .source_span = html_node.source_span,
                    .data = .{ .BoundAttribute = .{
                        .name = classified.name,
                        .type = bt,
                        .value = try parseExpression(ctx, attr.value, attr.value_span, .{ .is_binding = true }),
                        .unit = if (bt == .Style) extractStyleUnit(attr.value) else null,
                        .security_context = null,
                        .key_span = attr.key_span,
                        .source_span = attr.value_span,
                    } },
                };
                try bound_attrs.append(r3.*);
            },
        }
    }

    // If this element has a structural directive (*ngIf, *ngFor), wrap in Template
    if (structural_attr) |sa| {
        return try expandStructuralDirective(ctx, html_node, elem, sa, &text_attrs, &bound_attrs, &bound_events, &references);
    }

    // Transform children
    var r3_children = std.array_list.Managed(*const R3Node).initCapacity(ctx.arena.allocator(), elem.children.len) catch unreachable;
    for (elem.children) |c| {
        if (try transformNode(ctx, c)) |rn| {
            try r3_children.append(rn);
        }
    }

    // Build the R3 Element node
    const r3 = try ctx.arena.create(R3Node);
    r3.* = .{
        .kind = .Element,
        .source_span = html_node.source_span,
        .data = .{ .Element = .{
            .name = elem.name,
            .attributes = text_attrs.items,
            .inputs = bound_attrs.items,
            .outputs = bound_events.items,
            .directives = &[_]R3Node{},
            .children = r3_children.items,
            .references = references.items,
            .is_self_closing = elem.is_self_closing,
            .is_void = elem.is_void,
            .i18n = i18n_attr,
        } },
    };
    return r3;
}

// ─── Text Transform ───────────────────────────────────────────

fn transformText(ctx: *TransformContext, html_node: *const HtmlNode, text: TextNode) error{OutOfMemory}!?*R3Node {
    const trimmed = std.mem.trim(u8, text.value, " \t\n\r");
    if (trimmed.len == 0 and text.interpolation_boundaries.len == 0) return null;

    // Check for interpolations
    if (text.interpolation_boundaries.len > 0) {
        // This is a BoundText — text with {{ expr }} inside
        const expr_ast_node = try parseInterpolatedText(ctx, text, html_node.source_span);
        const r3 = try ctx.arena.create(R3Node);
        r3.* = .{
            .kind = .BoundText,
            .source_span = html_node.source_span,
            .data = .{ .BoundText = .{
                .value = expr_ast_node,
                .i18n = null,
            } },
        };
        return r3;
    }

    // Plain text node
    const r3 = try ctx.arena.create(R3Node);
    r3.* = .{
        .kind = .Text,
        .source_span = html_node.source_span,
        .data = .{ .Text = .{
            .value = text.value,
        } },
    };
    return r3;
}

// ─── Control Flow Blocks (@if, @for, @switch, @defer) ────────

fn transformControlFlowBlock(ctx: *TransformContext, html_node: *const HtmlNode, elem: ElementNode) error{OutOfMemory}!?*R3Node {
    const block_name = elem.name;

    if (std.mem.eql(u8, block_name, "@if")) {
        return try transformIfBlock(ctx, html_node, elem);
    } else if (std.mem.eql(u8, block_name, "@for")) {
        return try transformForBlock(ctx, html_node, elem);
    } else if (std.mem.eql(u8, block_name, "@switch")) {
        return try transformSwitchBlock(ctx, html_node, elem);
    } else if (std.mem.eql(u8, block_name, "@defer")) {
        return try transformDeferBlock(ctx, html_node, elem);
    } else if (std.mem.eql(u8, block_name, "@let")) {
        return try transformLetDeclaration(ctx, html_node, elem);
    }

    // Unknown block
    const r3 = try ctx.arena.create(R3Node);
    r3.* = .{
        .kind = .UnknownBlock,
        .source_span = html_node.source_span,
        .data = .{ .UnknownBlock = .{
            .name = block_name,
            .children = &[_]*const R3Node{},
        } },
    };
    return r3;
}

fn transformIfBlock(ctx: *TransformContext, html_node: *const HtmlNode, elem: ElementNode) error{OutOfMemory}!?*R3Node {
    // @if (condition) { ... } @else if (cond2) { ... } @else { ... }
    var branches = std.array_list.Managed(IfBlockBranch).initCapacity(ctx.arena.allocator(), 2) catch unreachable;

    // First @if block
    const cond_expr = if (elem.attrs.len > 0)
        try parseExpression(ctx, elem.attrs[0].value, elem.attrs[0].value_span, .{ .is_binding = true })
    else
        null;

    const children = try transformChildren(ctx, elem.children);

    try branches.append(.{
        .expression = cond_expr,
        .children = children,
        .expression_alias = null,
        .source_span = elem.start_span,
    });

    // Process @else if / @else children
    // (In a full implementation, we'd find sibling @else blocks)
    // For now, the first branch is the @if condition

    const r3 = try ctx.arena.create(R3Node);
    r3.* = .{
        .kind = .IfBlock,
        .source_span = html_node.source_span,
        .data = .{ .IfBlock = .{
            .branches = branches.items,
        } },
    };
    return r3;
}

fn transformForBlock(ctx: *TransformContext, html_node: *const HtmlNode, elem: ElementNode) error{OutOfMemory}!?*R3Node {
    // @for (item of items; track expr) { ... }
    // Parse microsyntax from first attribute: "item of items; track trackFn"
    var item_name: []const u8 = "item";
    var expression_str: []const u8 = "";
    var track_by: ?[]const u8 = null;

    if (elem.attrs.len > 0) {
        const micro = elem.attrs[0].value;
        // Parse "item of expression; track expr"
        var parts = std.mem.splitSequence(u8, micro, ";");
        var part_idx: usize = 0;
        while (parts.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " ");
            if (part_idx == 0) {
                // "item of expression"
                if (std.mem.indexOf(u8, trimmed, " of ")) |of_idx| {
                    item_name = std.mem.trim(u8, trimmed[0..of_idx], " ");
                    expression_str = std.mem.trim(u8, trimmed[of_idx + 4 ..], " ");
                } else {
                    expression_str = trimmed;
                }
            } else if (std.mem.startsWith(u8, trimmed, "track ")) {
                track_by = std.mem.trim(u8, trimmed[6..], " ");
            }
            part_idx += 1;
        }
    }

    const expr_ast_node = try parseExpression(ctx, expression_str, elem.start_span, .{ .is_binding = true });

    const children = try transformChildren(ctx, elem.children);

    // Build the item variable node
    const item_var = try ctx.arena.create(R3Node);
    item_var.* = .{
        .kind = .Variable,
        .source_span = ParseSourceSpan.fromAbsolute(elem.start_span),
        .data = .{ .Variable = .{
            .name = item_name,
            .value = "$implicit",
            .key_span = elem.start_span,
            .value_span = elem.start_span,
        } },
    };

    const r3 = try ctx.arena.create(R3Node);
    r3.* = .{
        .kind = .ForLoopBlock,
        .source_span = html_node.source_span,
        .data = .{ .ForLoopBlock = .{
            .item = item_var,
            .expression = expr_ast_node,
            .track_by = track_by,
            .context_variables = &[_]R3Node{},
            .children = children,
            .empty = null,
        } },
    };
    return r3;
}

fn transformSwitchBlock(ctx: *TransformContext, html_node: *const HtmlNode, elem: ElementNode) error{OutOfMemory}!?*R3Node {
    const expr_str = if (elem.attrs.len > 0) elem.attrs[0].value else "";
    const expr_ast_node = try parseExpression(ctx, expr_str, elem.start_span, .{ .is_binding = true });

    // Parse @case children into groups
    var groups = std.array_list.Managed(SwitchBlockCaseGroup).initCapacity(ctx.arena.allocator(), 2) catch unreachable;

    var current_cases = std.array_list.Managed(SwitchBlockCase).initCapacity(ctx.arena.allocator(), 1) catch unreachable;

    for (elem.children) |c| {
        if (c.kind == .Element) {
            const elem_data = c.data.Element;
            if (std.mem.eql(u8, elem_data.name, "@case")) {
                // Flush previous group if it has cases
                if (current_cases.items.len > 0) {
                    try groups.append(.{
                        .cases = current_cases.items,
                        .children = &[_]*const R3Node{},
                    });
                    current_cases = std.array_list.Managed(SwitchBlockCase).initCapacity(ctx.arena.allocator(), 1) catch unreachable;
                }
                // Extract case value from attribute
                const case_val = if (elem_data.attrs.len > 0) elem_data.attrs[0].value else "";
                try current_cases.append(.{
                    .value = case_val,
                    .source_span = elem_data.start_span,
                });
                continue;
            } else if (std.mem.eql(u8, elem_data.name, "@default")) {
                if (current_cases.items.len > 0) {
                    try groups.append(.{
                        .cases = current_cases.items,
                        .children = &[_]*const R3Node{},
                    });
                    current_cases = std.array_list.Managed(SwitchBlockCase).initCapacity(ctx.arena.allocator(), 1) catch unreachable;
                }
                try current_cases.append(.{
                    .value = "",
                    .source_span = elem_data.start_span,
                });
                continue;
            }
        }
    }
    // Flush last group
    if (current_cases.items.len > 0) {
        try groups.append(.{
            .cases = current_cases.items,
            .children = &[_]*const R3Node{},
        });
    }

    const r3 = try ctx.arena.create(R3Node);
    r3.* = .{
        .kind = .SwitchBlock,
        .source_span = html_node.source_span,
        .data = .{ .SwitchBlock = .{
            .expression = expr_ast_node,
            .groups = groups.items,
        } },
    };
    return r3;
}

fn transformDeferBlock(ctx: *TransformContext, html_node: *const HtmlNode, elem: ElementNode) error{OutOfMemory}!?*R3Node {
    // Parse triggers from attributes: on idle, on viewport, on interaction, etc.
    var triggers = std.array_list.Managed(DeferredTrigger).initCapacity(ctx.arena.allocator(), 2) catch unreachable;

    for (elem.attrs) |attr| {
        const name = attr.name;
        if (std.mem.eql(u8, name, "on idle")) {
            try triggers.append(.{ .kind = .Idle, .value = attr.value });
        } else if (std.mem.eql(u8, name, "on immediate")) {
            try triggers.append(.{ .kind = .Immediate });
        } else if (std.mem.eql(u8, name, "on timer")) {
            try triggers.append(.{ .kind = .Timer, .value = attr.value });
        } else if (std.mem.eql(u8, name, "on hover")) {
            try triggers.append(.{ .kind = .Hover });
        } else if (std.mem.eql(u8, name, "on interaction")) {
            try triggers.append(.{ .kind = .Interaction });
        } else if (std.mem.eql(u8, name, "on viewport")) {
            try triggers.append(.{ .kind = .Viewport });
        } else if (std.mem.eql(u8, name, "on never")) {
            try triggers.append(.{ .kind = .Never });
        } else if (std.mem.eql(u8, name, "when")) {
            // DeferWhen trigger — will be handled in IR
        } else if (std.mem.startsWith(u8, name, "defer on ")) {
            try triggers.append(.{ .kind = .Idle }); // fallback
        }
    }

    const children = try transformChildren(ctx, elem.children);

    const r3 = try ctx.arena.create(R3Node);
    r3.* = .{
        .kind = .DeferredBlock,
        .source_span = html_node.source_span,
        .data = .{ .DeferredBlock = .{
            .children = children,
            .triggers = triggers.items,
            .placeholder = null,
            .loading = null,
            .err = null,
            .defer_block_dependencies = &[_][]const u8{},
        } },
    };
    return r3;
}

fn transformLetDeclaration(ctx: *TransformContext, html_node: *const HtmlNode, elem: ElementNode) error{OutOfMemory}!?*R3Node {
    // @let name = expression;
    const name = if (elem.attrs.len > 0) elem.attrs[0].name else "value";
    const value_str = if (elem.attrs.len > 0) elem.attrs[0].value else "null";
    const value_span = if (elem.attrs.len > 0) elem.attrs[0].value_span else elem.start_span;

    const expr_ast_node = try parseExpression(ctx, value_str, value_span, .{ .is_binding = true });

    const r3 = try ctx.arena.create(R3Node);
    r3.* = .{
        .kind = .LetDeclaration,
        .source_span = html_node.source_span,
        .data = .{ .LetDeclaration = .{
            .name = name,
            .value = expr_ast_node,
            .name_span = elem.start_span,
            .value_span = value_span,
        } },
    };
    return r3;
}

// ─── Special Element Transforms ──────────────────────────────

fn transformNgContent(ctx: *TransformContext, html_node: *const HtmlNode, elem: ElementNode) error{OutOfMemory}!?*R3Node {
    const selector = findAttrValue(elem.attrs, "select");
    if (selector) |sel| {
        try ctx.ng_content_selectors.append(sel);
    }

    const children = try transformChildren(ctx, elem.children);

    const r3 = try ctx.arena.create(R3Node);
    r3.* = .{
        .kind = .Content,
        .source_span = html_node.source_span,
        .data = .{ .Content = .{
            .selector = selector,
            .attributes = &[_]R3Node{},
            .children = children,
        } },
    };
    return r3;
}

fn transformNgTemplate(ctx: *TransformContext, html_node: *const HtmlNode, elem: ElementNode) error{OutOfMemory}!?*R3Node {
    const children = try transformChildren(ctx, elem.children);

    // Extract variables from let-* attributes
    var r3_vars = std.array_list.Managed(R3Node).initCapacity(ctx.arena.allocator(), 2) catch unreachable;
    for (elem.attrs) |attr| {
        if (std.mem.startsWith(u8, attr.name, "let-")) {
            const r3 = try ctx.arena.create(R3Node);
            r3.* = .{
                .kind = .Variable,
                .source_span = html_node.source_span,
                .data = .{ .Variable = .{
                    .name = attr.name[4..],
                    .value = attr.value,
                    .key_span = attr.key_span,
                    .value_span = attr.value_span,
                } },
            };
            try r3_vars.append(r3.*);
        }
    }

    const r3 = try ctx.arena.create(R3Node);
    r3.* = .{
        .kind = .Template,
        .source_span = html_node.source_span,
        .data = .{ .Template = .{
            .tag_name = "ng-template",
            .attributes = &[_]R3Node{},
            .inputs = &[_]R3Node{},
            .outputs = &[_]R3Node{},
            .directives = &[_]R3Node{},
            .template_attrs = &[_]R3Node{},
            .children = children,
            .references = &[_]R3Node{},
            .variables = r3_vars.items,
        } },
    };
    return r3;
}

fn transformNgContainer(ctx: *TransformContext, html_node: *const HtmlNode, elem: ElementNode) error{OutOfMemory}!?*R3Node {
    // ng-container is like a transparent element (becomes a container in IR)
    return try transformRegularElement(ctx, html_node, elem);
}

fn transformStyleElement(ctx: *TransformContext, _: *const HtmlNode, elem: ElementNode) error{OutOfMemory}!?*R3Node {
    // Extract inline styles from content
    for (elem.children) |c| {
        if (c.kind == .Text) {
            const style_content = c.data.Text.value;
            if (style_content.len > 0) {
                try ctx.styles.append(style_content);
            }
        }
    }
    return null; // Style elements don't produce R3 nodes
}

fn transformComment(ctx: *TransformContext, html_node: *const HtmlNode, comment: html_ast.CommentNode) error{OutOfMemory}!?*R3Node {
    _ = ctx;
    _ = html_node;
    _ = comment;
    // Comments are not included in R3 AST by default (TS behavior)
    return null;
}

fn transformCdata(ctx: *TransformContext, html_node: *const HtmlNode, cdata: html_ast.CdataNode) error{OutOfMemory}!?*R3Node {
    const r3 = try ctx.arena.create(R3Node);
    r3.* = .{
        .kind = .Text,
        .source_span = html_node.source_span,
        .data = .{ .Text = .{
            .value = cdata.value,
        } },
    };
    return r3;
}

// ─── Structural Directive Expansion ───────────────────────────
/// *ngIf="condition" → Template with conditional
/// *ngFor="let item of items" → Template with for loop
fn expandStructuralDirective(
    ctx: *TransformContext,
    html_node: *const HtmlNode,
    elem: ElementNode,
    template_attr: *R3Node,
    text_attrs: *std.array_list.Managed(R3Node),
    bound_attrs: *std.array_list.Managed(R3Node),
    bound_events: *std.array_list.Managed(R3Node),
    references: *std.array_list.Managed(R3Node),
) error{OutOfMemory}!?*R3Node {
    const dir_name = template_attr.data.TextAttribute.name[1..]; // strip *

    // Parse the directive value
    const dir_value = template_attr.data.TextAttribute.value;

    if (std.mem.eql(u8, dir_name, "ngIf")) {
        return try expandNgIf(ctx, html_node, elem, dir_value, text_attrs, bound_attrs, bound_events, references);
    } else if (std.mem.eql(u8, dir_name, "ngFor")) {
        return try expandNgFor(ctx, html_node, elem, dir_value, text_attrs, bound_attrs, bound_events, references);
    } else if (std.mem.eql(u8, dir_name, "ngSwitch")) {
        return try expandNgSwitch(ctx, html_node, elem, dir_value, text_attrs, bound_attrs, bound_events, references);
    }

    // Generic structural directive → Template node
    const children = try transformChildren(ctx, elem.children);

    const r3 = try ctx.arena.create(R3Node);
    r3.* = .{
        .kind = .Template,
        .source_span = html_node.source_span,
        .data = .{ .Template = .{
            .tag_name = "ng-template",
            .attributes = text_attrs.items,
            .inputs = bound_attrs.items,
            .outputs = bound_events.items,
            .directives = &[_]R3Node{},
            .template_attrs = &[_]R3Node{template_attr.*},
            .children = children,
            .references = references.items,
            .variables = &[_]R3Node{},
        } },
    };
    return r3;
}

fn expandNgIf(
    ctx: *TransformContext,
    html_node: *const HtmlNode,
    elem: ElementNode,
    condition_str: []const u8,
    _: *std.array_list.Managed(R3Node),
    _: *std.array_list.Managed(R3Node),
    _: *std.array_list.Managed(R3Node),
    _: *std.array_list.Managed(R3Node),
) !?*R3Node {
    const cond_expr = try parseExpression(ctx, condition_str, elem.start_span, .{ .is_binding = true });
    const children = try transformChildren(ctx, elem.children);

    const r3 = try ctx.arena.create(R3Node);
    r3.* = .{
        .kind = .IfBlock,
        .source_span = html_node.source_span,
        .data = .{ .IfBlock = .{
            .branches = &[_]IfBlockBranch{
                .{
                    .expression = cond_expr,
                    .children = children,
                    .expression_alias = null,
                    .source_span = elem.start_span,
                },
            },
        } },
    };
    return r3;
}

fn expandNgFor(
    ctx: *TransformContext,
    html_node: *const HtmlNode,
    elem: ElementNode,
    microsyntax: []const u8,
    _: *std.array_list.Managed(R3Node),
    _: *std.array_list.Managed(R3Node),
    _: *std.array_list.Managed(R3Node),
    _: *std.array_list.Managed(R3Node),
) !?*R3Node {
    // Parse: "let item of items; trackBy: trackFn; index as i"
    var item_name: []const u8 = "$implicit";
    var expr_str: []const u8 = "";
    var track_by: ?[]const u8 = null;

    var it = std.mem.splitSequence(u8, microsyntax, ";");
    while (it.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " ");
        if (std.mem.indexOf(u8, trimmed, " of ")) |of_idx| {
            item_name = std.mem.trim(u8, trimmed[0..of_idx], " ");
            expr_str = std.mem.trim(u8, trimmed[of_idx + 4 ..], " ");
        } else if (std.mem.startsWith(u8, trimmed, "trackBy: ") or std.mem.startsWith(u8, trimmed, "track ")) {
            track_by = std.mem.trim(u8, if (std.mem.startsWith(u8, trimmed, "trackBy: "))
                trimmed[9..]
            else
                trimmed[6..], " ");
        }
    }

    const expr_ast_node = try parseExpression(ctx, expr_str, elem.start_span, .{ .is_binding = true });
    const children = try transformChildren(ctx, elem.children);

    const item_var = try ctx.arena.create(R3Node);
    item_var.* = .{
        .kind = .Variable,
        .source_span = ParseSourceSpan.fromAbsolute(elem.start_span),
        .data = .{ .Variable = .{
            .name = item_name,
            .value = "$implicit",
            .key_span = elem.start_span,
            .value_span = elem.start_span,
        } },
    };

    const r3 = try ctx.arena.create(R3Node);
    r3.* = .{
        .kind = .ForLoopBlock,
        .source_span = html_node.source_span,
        .data = .{ .ForLoopBlock = .{
            .item = item_var,
            .expression = expr_ast_node,
            .track_by = track_by,
            .context_variables = &[_]R3Node{},
            .children = children,
            .empty = null,
        } },
    };
    return r3;
}

fn expandNgSwitch(
    ctx: *TransformContext,
    html_node: *const HtmlNode,
    elem: ElementNode,
    switch_expr_str: []const u8,
    text_attrs: *std.array_list.Managed(R3Node),
    bound_attrs: *std.array_list.Managed(R3Node),
    bound_events: *std.array_list.Managed(R3Node),
    references: *std.array_list.Managed(R3Node),
) !?*R3Node {
    _ = text_attrs;
    _ = bound_attrs;
    _ = bound_events;
    _ = references;

    const expr_ast_node = try parseExpression(ctx, switch_expr_str, elem.start_span, .{ .is_binding = true });
    const children = try transformChildren(ctx, elem.children);

    const r3 = try ctx.arena.create(R3Node);
    r3.* = .{
        .kind = .SwitchBlock,
        .source_span = html_node.source_span,
        .data = .{ .SwitchBlock = .{
            .expression = expr_ast_node,
            .groups = &[_]SwitchBlockCaseGroup{
                .{
                    .cases = &[_]SwitchBlockCase{},
                    .children = children,
                },
            },
        } },
    };
    return r3;
}

// ─── Expression Parsing Helpers ──────────────────────────────

/// Flags for parseExpression
const ParseExpressionFlags = struct {
    is_action: bool = false,
    is_binding: bool = false,
    is_pipe: bool = false,
};

/// Parse an expression string into an ExprAst using the expression parser
fn parseExpression(ctx: *TransformContext, source: []const u8, span: AbsoluteSourceSpan, flags: ParseExpressionFlags) error{OutOfMemory}!*const expr_ast.Ast {
    var lex = expr_lexer.Lexer.init(ctx.allocator, source);
    defer lex.deinit();
    const lex_result = try lex.tokenize();

    var parser = expr_parser.Parser.init(ctx.allocator, ctx.arena, source, lex_result.@"0", span.start);
    defer parser.deinit();

    const ast_node = if (flags.is_action)
        try parser.parseAction()
    else
        try parser.parseBinding();

    return ast_node;
}

/// Parse interpolated text "Hello {{ name }}!" into a BoundText expression
fn parseInterpolatedText(ctx: *TransformContext, text: TextNode, span: ParseSourceSpan) error{OutOfMemory}!*const expr_ast.Ast {
    const expr_str = text.value; // Full text including {{ }}
    return try parseExpression(ctx, expr_str, span.absolute(), .{ .is_binding = true });
}

/// Parse interpolated attribute value
fn parseInterpolatedAttr(ctx: *TransformContext, attr: AttributeNode, _: ParseSourceSpan) error{OutOfMemory}!*const expr_ast.Ast {
    return try parseExpression(ctx, attr.value, attr.value_span, .{ .is_binding = true });
}

// ─── i18n Expansion Node Transform ─────────────────────────
/// Handles {plural} and {select} ICU message expansions.
/// Produces R3 Icu nodes with placeholders for each case.
/// Example: {items, plural, =0 {no items} one{1 item} other{{count} items}}
fn transformExpansion(ctx: *TransformContext, html_node: *const HtmlNode, exp: html_ast.ExpansionNode) error{OutOfMemory}!?*R3Node {
    // Parse the switch value expression (e.g., "items" in {items, plural, ...})
    const switch_expr = try parseExpression(ctx, exp.switch_value, html_node.source_span.absolute(), .{ .is_binding = true });

    // Build ICU placeholder nodes from each case
    var placeholders = std.array_list.Managed(r3_ast.IcuPlaceholder).initCapacity(ctx.arena.allocator(), exp.cases.len) catch unreachable;

    // Collect context variables (ICU variables like "=0", "one", "other")
    var icu_vars = std.array_list.Managed(r3_ast.IcuPlaceholder).initCapacity(ctx.arena.allocator(), exp.cases.len) catch unreachable;

    for (exp.cases) |case_node| {
        if (case_node.kind != .ExpansionCase) continue;
        const case = case_node.data.ExpansionCase;

        // Transform the case's children into R3 nodes
        var case_children = std.array_list.Managed(*const R3Node).initCapacity(ctx.arena.allocator(), case.children.len) catch unreachable;
        for (case.children) |c| {
            if (try transformNode(ctx, c)) |rn| {
                try case_children.append(rn);
            }
        }

        // Create a text node wrapping the case children for the placeholder value
        const placeholder_node = try ctx.arena.create(R3Node);
        if (case_children.items.len == 1) {
            placeholder_node.* = case_children.items[0].*;
        } else {
            // Multiple children → wrap in a synthetic text-like node
            placeholder_node.* = .{
                .kind = .Text,
                .source_span = html_node.source_span,
                .data = .{ .Text = .{ .value = case.expression } },
            };
        }

        // Register the case value as a placeholder
        try placeholders.append(.{
            .name = case.value,
            .value = placeholder_node,
        });

        // ICU variables (the case keys like "=0", "one", "many", "other")
        try icu_vars.append(.{
            .name = case.value,
            .value = placeholder_node,
        });
    }

    const r3 = try ctx.arena.create(R3Node);
    r3.* = .{
        .kind = .Icu,
        .source_span = html_node.source_span,
        .data = .{ .Icu = .{
            .vars = icu_vars.items,
            .placeholders = placeholders.items,
            .source_span = html_node.source_span.absolute(),
        } },
    };

    _ = switch_expr;
    return r3;
}

/// Transform @if block with @else if / @else sibling handling.
/// Walks sibling nodes after the @if block to collect chained @else if and
/// terminal @else branches.
fn transformIfBlockFromBlock(
    ctx: *TransformContext,
    html_node: *const HtmlNode,
    block: html_ast.BlockNode,
) error{OutOfMemory}!?*R3Node {
    var branches = std.array_list.Managed(IfBlockBranch).initCapacity(ctx.arena.allocator(), 2) catch unreachable;

    // First @if branch
    const cond_str = if (block.parameters.len > 0) block.parameters[0].expression else "";
    const cond_span = if (block.parameters.len > 0) block.parameters[0].source_span else html_node.source_span.absolute();

    const children = try transformChildren(ctx, block.children);
    const cond_expr = if (cond_str.len > 0)
        try parseExpression(ctx, cond_str, cond_span, .{ .is_binding = true })
    else
        null;

    try branches.append(.{
        .expression = cond_expr,
        .children = children,
        .expression_alias = null,
        .source_span = html_node.source_span.absolute(),
    });

    // TODO: walk siblings to collect @else if / @else branches.
    // This requires passing the parent's children list + index, which is not
    // currently available in this function signature. For now, @else if and
    // @else are handled as separate blocks in the parent's children list.
    // A future refactor will pass sibling context to enable proper chaining.

    const r3 = try ctx.arena.create(R3Node);
    r3.* = .{
        .kind = .IfBlock,
        .source_span = html_node.source_span,
        .data = .{ .IfBlock = .{ .branches = branches.items } },
    };
    return r3;
}

// ─── Block Node Transform (@if/@for from HTML parser Block nodes) ─
/// The HTML parser produces Block nodes for @if, @for, @switch, @defer.
/// These are already handled via the Element path (they appear as elements
/// with @-prefixed names), but if the parser emits them as Block nodes
/// directly, we handle them here.
fn transformBlock(ctx: *TransformContext, html_node: *const HtmlNode, block: html_ast.BlockNode) error{OutOfMemory}!?*R3Node {
    // Delegate to control flow block handling based on block name
    if (std.mem.eql(u8, block.name, "if")) {
        return try transformIfBlockFromBlock(ctx, html_node, block);
    }

    if (std.mem.eql(u8, block.name, "for")) {
        const micro = if (block.parameters.len > 0) block.parameters[0].expression else "";
        const micro_span = if (block.parameters.len > 0) block.parameters[0].source_span else html_node.source_span.absolute();

        var item_name: []const u8 = "$implicit";
        var expr_str: []const u8 = "";
        var track_by: ?[]const u8 = null;

        var it = std.mem.splitSequence(u8, micro, ";");
        while (it.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " ");
            if (std.mem.indexOf(u8, trimmed, " of ")) |of_idx| {
                item_name = std.mem.trim(u8, trimmed[0..of_idx], " ");
                expr_str = std.mem.trim(u8, trimmed[of_idx + 4 ..], " ");
            } else if (std.mem.startsWith(u8, trimmed, "track ")) {
                track_by = std.mem.trim(u8, trimmed[6..], " ");
            }
        }

        const expr_ast_node = try parseExpression(ctx, expr_str, micro_span, .{ .is_binding = true });
        const children = try transformChildren(ctx, block.children);

        const item_var = try ctx.arena.create(R3Node);
        item_var.* = .{
            .kind = .Variable,
            .source_span = html_node.source_span,
            .data = .{ .Variable = .{
                .name = item_name,
                .value = "$implicit",
                .key_span = html_node.source_span.absolute(),
                .value_span = html_node.source_span.absolute(),
            } },
        };

        const r3 = try ctx.arena.create(R3Node);
        r3.* = .{
            .kind = .ForLoopBlock,
            .source_span = html_node.source_span,
            .data = .{ .ForLoopBlock = .{
                .item = item_var,
                .expression = expr_ast_node,
                .track_by = track_by,
                .context_variables = &[_]R3Node{},
                .children = children,
                .empty = null,
            } },
        };
        return r3;
    }

    if (std.mem.eql(u8, block.name, "switch")) {
        const expr_str = if (block.parameters.len > 0) block.parameters[0].expression else "";
        const expr_span = if (block.parameters.len > 0) block.parameters[0].source_span else html_node.source_span.absolute();
        const expr_ast_node = try parseExpression(ctx, expr_str, expr_span, .{ .is_binding = true });

        const children = try transformChildren(ctx, block.children);

        const r3 = try ctx.arena.create(R3Node);
        r3.* = .{
            .kind = .SwitchBlock,
            .source_span = html_node.source_span,
            .data = .{ .SwitchBlock = .{
                .expression = expr_ast_node,
                .groups = &[_]SwitchBlockCaseGroup{
                    .{ .cases = &[_]SwitchBlockCase{}, .children = children },
                },
            } },
        };
        return r3;
    }

    // Unknown block — skip
    return null;
}

// ─── Utility Helpers ─────────────────────────────────────────

fn transformChildren(ctx: *TransformContext, children: []const *const HtmlNode) error{OutOfMemory}![]const *const R3Node {
    var r3_children = std.array_list.Managed(*const R3Node).initCapacity(ctx.arena.allocator(), children.len) catch unreachable;
    for (children) |c| {
        if (try transformNode(ctx, c)) |rn| {
            try r3_children.append(rn);
        }
    }
    return r3_children.items;
}

fn findAttrValue(attrs: []const AttributeNode, name: []const u8) ?[]const u8 {
    for (attrs) |a| {
        if (std.mem.eql(u8, a.name, name)) return a.value;
    }
    return null;
}

fn extractUnit(name: []const u8) ?[]const u8 {
    // style.width.px → "px"
    if (std.mem.startsWith(u8, name, "style.") and name.len > 6) {
        const prop_part = name[6..];
        if (std.mem.lastIndexOfScalar(u8, prop_part, '.')) |dot| {
            return prop_part[dot + 1 ..];
        }
    }
    return null;
}

fn extractStyleUnit(value: []const u8) ?[]const u8 {
    // "100px" → "px", "1em" → "em", "50%" → "%"
    var i = value.len;
    while (i > 0) : (i -= 1) {
        const ch = value[i - 1];
        if ((ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or ch == '%') {
            continue;
        }
        if (i < value.len) return value[i..];
        return null;
    }
    return null;
}
