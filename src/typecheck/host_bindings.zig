/// TCB Host Bindings — Host binding type checking
///
/// Port of: compiler/src/typecheck/host_bindings.ts (518 LoC)
///
/// Type-checks host bindings on directives and components. Host bindings
/// (e.g., `@HostBinding('class.active')` or `host: { '(click)': '...' }`)
/// are validated against the directive's host metadata.
///
/// The TS source defines:
///   - `SourceNode` tagged union (`StaticSourceNode` with kind 'string' | 'identifier'
///     or `{ kind: 'unspecified', sourceSpan }`)
///   - `HostObjectLiteralBinding`, `HostBindingDecorator`, `HostListenerDecorator`
///   - `createHostElement(type, selector, nameSpan, hostObjectLiteralBindings,
///       hostBindingDecorators, hostListenerDecorators)` returns `HostElement | null`
///   - `createHostBindingsBlockGuard()` returns a guard comment string
///   - `inferBoundAttribute(name)` returns `{attrName, type: BindingType}`
///   - `fixupSpans(ast, node)` walks the AST and overrides spans for nodes
///     after the first escaped character in `node.source`
///   - `ReplaceSpanVisitor extends RecursiveAstVisitor` overrides spans in-place
///
/// In the Zig port we keep the same shape: a tagged union for `SourceNode`,
/// comprehensive metadata structs, and the `createHostElement` entry point
/// that returns an optional `HostElement`. Internal helpers use `anyerror!`
/// to avoid recursive-dependency loops.
const std = @import("std");
const expr_api = @import("expression.zig");

// Re-export commonly used types from expression.zig for convenience.
pub const AbsoluteSourceSpan = expr_api.AbsoluteSourceSpan;
pub const ParseSpan = expr_api.ParseSpan;
pub const AstNode = expr_api.AstNode;

// `TcbExpr` in this file is the legacy string-alias used by `checkHostBindings`.
// The `expression.zig` module defines a richer `TcbExpr` struct; here we use a
// plain `[]const u8` alias for backwards compatibility with the legacy API.
pub const TcbExpr = []const u8;

// ─── Constants ─────────────────────────────────────────────

/// HOST_BINDING_GUARD_COMMENT_TEXT — comment text used to distinguish
/// nodes used for type checking host bindings from those used for templates.
/// Direct port of `HOST_BINDING_GUARD_COMMENT_TEXT` in the TS source.
pub const HOST_BINDING_GUARD_COMMENT_TEXT = "hostBindingsBlockGuard";

// ─── BindingType ───────────────────────────────────────────

/// BindingType — kind of a bound attribute. Mirrors `BindingType` in
/// `expression_parser/ast.ts`. Direct port of the enum used in the TS source.
pub const BindingType = enum(u8) {
    /// `[prop]` — property binding.
    Property,
    /// `[attr.name]` — attribute binding.
    Attribute,
    /// `[class.name]` — class binding.
    Class,
    /// `[style.name]` — style binding.
    Style,
    /// `[@trigger]` — animation binding (new syntax).
    Animation,
    /// `@trigger` — legacy animation binding.
    LegacyAnimation,
    /// Plain text attribute (used by r3_ast.BoundAttribute).
    TextAttribute,
};

// ─── ParsedEventType ───────────────────────────────────────

/// ParsedEventType — kind of a parsed event. Mirrors `ParsedEventType` in
/// `expression_parser/ast.ts`. Direct port of the enum used in the TS source.
pub const ParsedEventType = enum(u8) {
    /// `(click)` — regular DOM event.
    Regular,
    /// `(@trigger)` — animation event (new syntax).
    Animation,
    /// `@trigger` — legacy animation event.
    LegacyAnimation,
};

// ─── SourceNode tagged union ───────────────────────────────

/// SourceNodeKind — tag for the `SourceNode` tagged union.
/// Direct port of `SourceNode['kind']` in the TS source.
pub const SourceNodeKind = enum(u8) {
    /// Static string literal (e.g. `'foo'`).
    string,
    /// Static identifier (e.g. `foo`).
    identifier,
    /// Anything that isn't a static expression.
    unspecified,
};

/// StaticSourceNode — a `SourceNode` representing a static expression.
/// Direct port of `StaticSourceNode` interface in the TS source.
pub const StaticSourceNode = struct {
    kind: SourceNodeKind, // 'string' or 'identifier'
    /// Raw source code of the node (e.g. strings include the quotes).
    source: []const u8,
    /// Actual text of the node (e.g. value inside the quotes in strings).
    text: []const u8,
    /// Location information about the node.
    source_span: AbsoluteSourceSpan,
};

/// SourceNode — either a `StaticSourceNode` or an "unspecified" node with
/// only a source span. Direct port of the `SourceNode` type alias in the TS source.
pub const SourceNode = union(SourceNodeKind) {
    /// Static string or identifier node.
    string: StaticSourceNode,
    identifier: StaticSourceNode,
    /// Unspecified node — only carries a source span.
    unspecified: AbsoluteSourceSpan,

    /// Get the source span of any SourceNode variant.
    pub fn sourceSpan(self: SourceNode) AbsoluteSourceSpan {
        return switch (self) {
            .string => |s| s.source_span,
            .identifier => |s| s.source_span,
            .unspecified => |span| span,
        };
    }

    /// Get the text of a static node, or empty for unspecified nodes.
    pub fn text(self: SourceNode) []const u8 {
        return switch (self) {
            .string => |s| s.text,
            .identifier => |s| s.text,
            .unspecified => "",
        };
    }

    /// Get the raw source of a static node, or empty for unspecified nodes.
    pub fn source(self: SourceNode) []const u8 {
        return switch (self) {
            .string => |s| s.source,
            .identifier => |s| s.source,
            .unspecified => "",
        };
    }

    /// Construct a string-kind SourceNode.
    pub fn fromString(src: []const u8, txt: []const u8, span: AbsoluteSourceSpan) SourceNode {
        return .{ .string = .{
            .kind = .string,
            .source = src,
            .text = txt,
            .source_span = span,
        } };
    }

    /// Construct an identifier-kind SourceNode.
    pub fn fromIdentifier(src: []const u8, txt: []const u8, span: AbsoluteSourceSpan) SourceNode {
        return .{ .identifier = .{
            .kind = .identifier,
            .source = src,
            .text = txt,
            .source_span = span,
        } };
    }

    /// Construct an unspecified-kind SourceNode.
    pub fn unspecifiedFrom(span: AbsoluteSourceSpan) SourceNode {
        return .{ .unspecified = span };
    }
};

// ─── HostObjectLiteralBinding ──────────────────────────────

/// HostObjectLiteralBinding — a single binding inside the `host` object of
/// a directive. Direct port of `HostObjectLiteralBinding` interface.
pub const HostObjectLiteralBinding = struct {
    /// Node representing the key of the binding.
    key: SourceNode,
    /// Node representing the value of the binding.
    value: SourceNode,
    /// Location information about the entire binding.
    source_span: AbsoluteSourceSpan,
};

// ─── HostListenerDecorator ─────────────────────────────────

/// HostListenerDecorator — a single binding declared by a `@HostListener`
/// decorator on a class member. Direct port of `HostListenerDecorator` interface.
pub const HostListenerDecorator = struct {
    /// Node declaring the name of the event (e.g. first argument of `@HostListener`).
    event_name: ?SourceNode,
    /// Node representing the name of the member that was decorated.
    member_name: StaticSourceNode,
    /// Location information about the member that the decorator is set on.
    member_span: AbsoluteSourceSpan,
    /// Arguments passed to the event.
    arguments: []const SourceNode,
    /// Location information about the decorator.
    decorator_span: AbsoluteSourceSpan,
};

// ─── HostBindingDecorator ──────────────────────────────────

/// HostBindingDecorator — a single binding declared by the `@HostBinding`
/// decorator on a class member. Direct port of `HostBindingDecorator` interface.
pub const HostBindingDecorator = struct {
    /// Node representing the name of the member that was decorated.
    member_name: StaticSourceNode,
    /// Location information about the member that the decorator is set on.
    member_span: AbsoluteSourceSpan,
    /// Arguments passed into the decorator.
    arguments: []const SourceNode,
    /// Location information about the decorator.
    decorator_span: AbsoluteSourceSpan,
};

// ─── BoundAttribute & BoundEvent (simplified r3_ast) ───────

/// BoundAttribute — a bound attribute on a host element. Mirrors
/// `BoundAttribute` from `render3/r3_ast.ts`. Simplified for type-checking.
pub const BoundAttribute = struct {
    name: []const u8,
    type: BindingType,
    /// Security context (unused for type-checking, kept for parity).
    security_context: u32 = 0,
    /// The parsed AST expression for the binding value.
    value_expr: ?*const AstNode = null,
    /// The unit (e.g. `px` for style bindings).
    unit: ?[]const u8 = null,
    /// Location info for the entire binding.
    source_span: AbsoluteSourceSpan,
    /// Location info for the key (name) part.
    key_span: AbsoluteSourceSpan,
    /// Location info for the value part.
    value_span: AbsoluteSourceSpan,
};

/// BoundEvent — a bound event on a host element. Mirrors `BoundEvent` from
/// `render3/r3_ast.ts`. Simplified for type-checking.
pub const BoundEvent = struct {
    name: []const u8,
    type: ParsedEventType,
    /// The parsed AST expression for the handler.
    handler: ?*const AstNode = null,
    /// Target of the event (e.g. `window` for `(window:scroll)`).
    target: ?[]const u8 = null,
    /// Phase of the event (only for legacy animation events).
    phase: ?[]const u8 = null,
    /// Location info for the entire binding.
    source_span: AbsoluteSourceSpan,
    /// Location info for the key (name) part.
    key_span: AbsoluteSourceSpan,
    /// Location info for the handler part.
    handler_span: AbsoluteSourceSpan,
};

// ─── HostElement ───────────────────────────────────────────

/// HostElement — the synthetic host element with its bindings and listeners.
/// Direct port of `HostElement` (from `render3/r3_ast.ts`) constructor result.
pub const HostElement = struct {
    /// Tag names that the host element can have (from the directive's selector).
    tag_names: []const []const u8,
    /// Bound attribute bindings on the host element.
    bindings: []const BoundAttribute,
    /// Bound event listeners on the host element.
    listeners: []const BoundEvent,
    /// Location info for the directive's name.
    name_span: AbsoluteSourceSpan,

    pub fn deinit(self: *const HostElement, allocator: std.mem.Allocator) void {
        allocator.free(self.tag_names);
        allocator.free(self.bindings);
        allocator.free(self.listeners);
    }
};

// ─── DirectiveType ─────────────────────────────────────────

/// DirectiveType — whether the host is for a `component` or `directive`.
/// Direct port of `type: 'component' | 'directive'` parameter in the TS source.
pub const DirectiveType = enum(u8) {
    component,
    directive,

    pub fn fallbackTagName(self: DirectiveType) []const u8 {
        return switch (self) {
            .component => "ng-component",
            .directive => "ng-directive",
        };
    }
};

// ─── inferBoundAttribute ───────────────────────────────────

/// InferBoundAttributeResult — the return value of `inferBoundAttribute`.
pub const InferBoundAttributeResult = struct {
    attr_name: []const u8,
    type: BindingType,
};

/// Infer the attribute name and binding type of a bound attribute based on
/// its raw name.
/// Direct port of `inferBoundAttribute(name)` in the TS source.
pub fn inferBoundAttribute(name: []const u8) InferBoundAttributeResult {
    const attr_prefix = "attr.";
    const class_prefix = "class.";
    const style_prefix = "style.";
    const animation_prefix = "animate.";
    const legacy_animation_prefix = "@";

    if (std.mem.startsWith(u8, name, attr_prefix)) {
        return .{
            .attr_name = name[attr_prefix.len..],
            .type = .Attribute,
        };
    } else if (std.mem.startsWith(u8, name, class_prefix)) {
        return .{
            .attr_name = name[class_prefix.len..],
            .type = .Class,
        };
    } else if (std.mem.startsWith(u8, name, style_prefix)) {
        return .{
            .attr_name = name[style_prefix.len..],
            .type = .Style,
        };
    } else if (std.mem.startsWith(u8, name, animation_prefix)) {
        return .{
            .attr_name = name,
            .type = .Animation,
        };
    } else if (std.mem.startsWith(u8, name, legacy_animation_prefix)) {
        return .{
            .attr_name = name[legacy_animation_prefix.len..],
            .type = .LegacyAnimation,
        };
    } else {
        return .{
            .attr_name = name,
            .type = .Property,
        };
    }
}

// ─── createHostBindingsBlockGuard ──────────────────────────

/// Create an AST node that can be used as a guard in `if` statements to
/// distinguish TypeScript nodes used for checking host bindings from ones
/// used for checking templates.
/// Direct port of `createHostBindingsBlockGuard()` in the TS source.
pub fn createHostBindingsBlockGuard(allocator: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(true /*{s}*/)", .{HOST_BINDING_GUARD_COMMENT_TEXT});
}

// ─── CssSelector (simplified) ──────────────────────────────

/// CssSelectorPart — a single parsed CSS selector with optional element name.
/// Simplified port of `CssSelector` from `directive_matching.ts`.
pub const CssSelectorPart = struct {
    element: ?[]const u8 = null,
    class_names: []const []const u8 = &.{},
    attrs: []const []const u8 = &.{},
};

/// Parse a CSS selector string into a list of `CssSelectorPart`s.
/// Very simplified port of `CssSelector.parse(selector)` — only handles
/// element names and comma-separated selectors.
pub fn parseCssSelector(allocator: std.mem.Allocator, selector: []const u8) ![]const CssSelectorPart {
    var parts = std.array_list.Managed(CssSelectorPart).init(allocator);
    errdefer parts.deinit();

    var iter = std.mem.splitScalar(u8, selector, ',');
    while (iter.next()) |raw| {
        const s = std.mem.trim(u8, raw, " \t\n");
        if (s.len == 0) continue;
        // Extract the element name (leading word).
        var element: ?[]const u8 = null;
        var i: usize = 0;
        while (i < s.len) : (i += 1) {
            const c = s[i];
            if (c == '.' or c == '#' or c == '[' or c == ':' or c == '*') break;
        }
        if (i > 0) element = s[0..i];
        try parts.append(.{ .element = element });
    }
    return parts.toOwnedSlice();
}

// ─── createHostElement ─────────────────────────────────────

/// Create an AST node that represents the host element of a directive.
/// Returns `null` if there are no valid bindings to be checked.
/// Direct port of `createHostElement(...)` in the TS source.
pub fn createHostElement(
    allocator: std.mem.Allocator,
    dir_type: DirectiveType,
    selector: ?[]const u8,
    name_span: AbsoluteSourceSpan,
    host_object_literal_bindings: []const HostObjectLiteralBinding,
    host_binding_decorators: []const HostBindingDecorator,
    host_listener_decorators: []const HostListenerDecorator,
) !?HostElement {
    var bindings = std.array_list.Managed(BoundAttribute).init(allocator);
    errdefer bindings.deinit();
    var listeners = std.array_list.Managed(BoundEvent).init(allocator);
    errdefer listeners.deinit();

    // Process host object literal bindings (e.g. `host: { '[prop]': '...' }`).
    for (host_object_literal_bindings) |binding| {
        try createNodeFromHostLiteralProperty(allocator, binding, &bindings, &listeners);
    }

    // Process `@HostBinding` decorators.
    for (host_binding_decorators) |decorator| {
        try createNodeFromBindingDecorator(allocator, decorator, &bindings);
    }

    // Process `@HostListener` decorators.
    for (host_listener_decorators) |decorator| {
        try createNodeFromListenerDecorator(allocator, decorator, &listeners);
    }

    // The element is a no-op if there are no bindings.
    if (bindings.items.len == 0 and listeners.items.len == 0) {
        bindings.deinit();
        listeners.deinit();
        return null;
    }

    // Determine tag names from the selector.
    var tag_names = std.array_list.Managed([]const u8).init(allocator);
    errdefer tag_names.deinit();
    if (selector) |sel| {
        const parts = try parseCssSelector(allocator, sel);
        defer allocator.free(parts);
        for (parts) |part| {
            if (part.element) |el| {
                try tag_names.append(el);
            }
        }
    }

    // Fall back to `ng-component`/`ng-directive` if no tag names were found.
    if (tag_names.items.len == 0) {
        try tag_names.append(dir_type.fallbackTagName());
    }

    return HostElement{
        .tag_names = try tag_names.toOwnedSlice(),
        .bindings = try bindings.toOwnedSlice(),
        .listeners = try listeners.toOwnedSlice(),
        .name_span = name_span,
    };
}

// ─── createNodeFromHostLiteralProperty ─────────────────────

/// Create and track the relevant AST node for a binding declared through a
/// property on the `host` literal.
/// Direct port of `createNodeFromHostLiteralProperty(...)` in the TS source.
fn createNodeFromHostLiteralProperty(
    allocator: std.mem.Allocator,
    binding: HostObjectLiteralBinding,
    bindings: *std.array_list.Managed(BoundAttribute),
    listeners: *std.array_list.Managed(BoundEvent),
) anyerror!void {
    _ = allocator;
    const key = binding.key;
    const value = binding.value;
    const source_span = binding.source_span;

    // Only static-string keys and values are supported.
    if (key != .string or value != .string) return;
    const key_text = key.text();

    if (std.mem.startsWith(u8, key_text, "[") and std.mem.endsWith(u8, key_text, "]")) {
        // Property binding: `[prop]` or `[attr.name]` etc.
        const inner = key_text[1 .. key_text.len - 1];
        const inferred = inferBoundAttribute(inner);
        try bindings.append(.{
            .name = inferred.attr_name,
            .type = inferred.type,
            .source_span = source_span,
            .key_span = key.sourceSpan(),
            .value_span = value.sourceSpan(),
        });
    } else if (std.mem.startsWith(u8, key_text, "(") and std.mem.endsWith(u8, key_text, ")")) {
        // Event binding: `(event)`.
        const inner = key_text[1 .. key_text.len - 1];
        const inferred = inferBoundAttribute(inner);
        const event_type: ParsedEventType = if (inferred.type == .Animation)
            .Animation
        else if (inferred.type == .LegacyAnimation)
            .LegacyAnimation
        else
            .Regular;
        try listeners.append(.{
            .name = inferred.attr_name,
            .type = event_type,
            .source_span = source_span,
            .key_span = key.sourceSpan(),
            .handler_span = value.sourceSpan(),
        });
    }
}

// ─── createNodeFromBindingDecorator ────────────────────────

/// Create and track a bound attribute node from a `@HostBinding` decorator.
/// Direct port of `createNodeFromBindingDecorator(...)` in the TS source.
fn createNodeFromBindingDecorator(
    allocator: std.mem.Allocator,
    decorator: HostBindingDecorator,
    bindings: *std.array_list.Managed(BoundAttribute),
) anyerror!void {
    _ = allocator;
    const args = decorator.arguments;

    // The first parameter is optional. If omitted, the name of the class
    // member is used as the property.
    var name_node: SourceNode = undefined;
    if (args.len == 0) {
        // Use the member name (a StaticSourceNode).
        name_node = .{ .string = decorator.member_name };
    } else if (args[0] == .string) {
        name_node = args[0];
    } else {
        return;
    }

    // Only static string/identifier names are supported.
    if (name_node != .string and name_node != .identifier) return;
    const inferred = inferBoundAttribute(name_node.text());

    try bindings.append(.{
        .name = inferred.attr_name,
        .type = inferred.type,
        .source_span = decorator.decorator_span,
        .key_span = name_node.sourceSpan(),
        .value_span = decorator.decorator_span,
    });
}

// ─── createNodeFromListenerDecorator ───────────────────────

/// Create and track a bound event node from a `@HostListener` decorator.
/// Direct port of `createNodeFromListenerDecorator(...)` in the TS source.
fn createNodeFromListenerDecorator(
    allocator: std.mem.Allocator,
    decorator: HostListenerDecorator,
    listeners: *std.array_list.Managed(BoundEvent),
) anyerror!void {
    _ = allocator;
    const event_name_node = decorator.event_name orelse return;
    if (event_name_node != .string) return;

    const text = event_name_node.text();
    var event_type: ParsedEventType = undefined;
    var event_name: []const u8 = undefined;
    var phase: ?[]const u8 = null;
    var target: ?[]const u8 = null;

    if (std.mem.startsWith(u8, text, "@")) {
        // Legacy animation event: `@trigger.start` or `@trigger`.
        event_type = .LegacyAnimation;
        const rest = text[1..];
        if (std.mem.indexOfScalar(u8, rest, '.')) |dot| {
            event_name = rest[0..dot];
            phase = rest[dot + 1 ..];
        } else {
            event_name = rest;
        }
        target = null;
    } else {
        // Regular event, possibly with target: `window:scroll`.
        event_type = .Regular;
        if (std.mem.startsWith(u8, text, "animate.")) {
            event_type = .Animation;
            event_name = text;
        } else if (std.mem.indexOfScalar(u8, text, ':')) |colon| {
            target = text[0..colon];
            event_name = text[colon + 1 ..];
        } else {
            event_name = text;
        }
        phase = null;
    }

    try listeners.append(.{
        .name = event_name,
        .type = event_type,
        .target = target,
        .phase = phase,
        .source_span = decorator.decorator_span,
        .key_span = decorator.decorator_span,
        .handler_span = event_name_node.sourceSpan(),
    });
}

// ─── fixupSpans & ReplaceSpanVisitor ───────────────────────

/// ReplaceSpanVisitor — walks the AST and overrides spans of all nodes that
/// fall after a specific index. Direct port of `ReplaceSpanVisitor` class.
pub const ReplaceSpanVisitor = struct {
    after_index: u32,
    override_span: ParseSpan,
    override_source_span: AbsoluteSourceSpan,

    pub fn init(
        after_index: u32,
        override_span: ParseSpan,
        override_source_span: AbsoluteSourceSpan,
    ) ReplaceSpanVisitor {
        return .{
            .after_index = after_index,
            .override_span = override_span,
            .override_source_span = override_source_span,
        };
    }

    /// Visit an AST node and override its spans if they fall after the index.
    /// Direct port of `ReplaceSpanVisitor.visit(ast)` in the TS source.
    pub fn visit(self: *const ReplaceSpanVisitor, ast: *AstNode) void {
        if (ast.span.start >= self.after_index or ast.span.end >= self.after_index) {
            ast.span = self.override_span;
            ast.source_span = self.override_source_span;
            if (ast.name_span) |_| {
                ast.name_span = self.override_source_span;
            }
            if (ast.argument_span) |_| {
                ast.argument_span = self.override_source_span;
            }
        }
        // Recurse into children (recursive visitor pattern).
        visitChildren(self, ast);
    }
};

/// Recursively visit child nodes — mirrors `RecursiveAstVisitor.visitChildren`.
fn visitChildren(visitor: *const ReplaceSpanVisitor, ast: *const AstNode) void {
    switch (ast.data) {
        .Unary => |u| visitor.visit(@constCast(u.expr)),
        .Binary => |b| {
            visitor.visit(@constCast(b.left));
            visitor.visit(@constCast(b.right));
        },
        .Chain => |c| {
            for (c.expressions) |e| visitor.visit(@constCast(e));
        },
        .Conditional => |c| {
            visitor.visit(@constCast(c.condition));
            visitor.visit(@constCast(c.true_exp));
            visitor.visit(@constCast(c.false_exp));
        },
        .Call => |call| {
            visitor.visit(@constCast(call.receiver));
            for (call.args) |a| visitor.visit(@constCast(a));
        },
        .SafeCall => |call| {
            visitor.visit(@constCast(call.receiver));
            for (call.args) |a| visitor.visit(@constCast(a));
        },
        .PropertyRead => |pr| visitor.visit(@constCast(pr.receiver)),
        .SafePropertyRead => |spr| visitor.visit(@constCast(spr.receiver)),
        .KeyedRead => |kr| {
            visitor.visit(@constCast(kr.receiver));
            visitor.visit(@constCast(kr.key));
        },
        .SafeKeyedRead => |skr| {
            visitor.visit(@constCast(skr.receiver));
            visitor.visit(@constCast(skr.key));
        },
        .BindingPipe => |bp| {
            visitor.visit(@constCast(bp.exp));
            for (bp.args) |a| visitor.visit(@constCast(a));
        },
        .LiteralArray => |la| {
            for (la.expressions) |e| visitor.visit(@constCast(e));
        },
        .LiteralMap => |lm| {
            for (lm.values) |v| visitor.visit(@constCast(v));
        },
        .SpreadElement => |se| visitor.visit(@constCast(se.expression)),
        .Interpolation => |i| {
            for (i.expressions) |e| visitor.visit(@constCast(e));
        },
        .PrefixNot => |pn| visitor.visit(@constCast(pn.expression)),
        .TypeofExpr => |te| visitor.visit(@constCast(te.expression)),
        .VoidExpr => |ve| visitor.visit(@constCast(ve.expression)),
        .NonNullAssert => |nna| visitor.visit(@constCast(nna.expression)),
        .Parenthesized => |p| visitor.visit(@constCast(p.expression)),
        .ArrowFunction => |af| visitor.visit(@constCast(af.body)),
        .TaggedTemplate => |tt| {
            visitor.visit(@constCast(tt.tag));
            for (tt.template.expressions) |e| visitor.visit(@constCast(e));
        },
        .TemplateLiteral => |tl| {
            for (tl.expressions) |e| visitor.visit(@constCast(e));
        },
        .ASTWithSource => |aws| visitor.visit(@constCast(aws.ast)),
        else => {},
    }
}

/// Find the first index of `\\` (escape char) in `source` starting from `from`.
fn indexOfEscapeFrom(source: []const u8, from: usize) ?usize {
    var i = from;
    while (i < source.len) : (i += 1) {
        if (source[i] == '\\') return i;
    }
    return null;
}

/// Adjust the spans of a parsed AST so that they're appropriate for a host
/// bindings context. Direct port of `fixupSpans(ast, node)` in the TS source.
pub fn fixupSpans(ast: *AstNode, node: StaticSourceNode) void {
    // Look for an escape character after the first character (skipping the
    // leading quote in strings, which is why we start at index 1).
    const start_idx: usize = 1;
    const escape_index = indexOfEscapeFrom(node.source, start_idx) orelse return;

    const start = node.source_span.start;
    const end = node.source_span.end;
    const new_span = ParseSpan{ .start = 0, .end = end - start };
    const new_source_span = AbsoluteSourceSpan{ .start = start, .end = end };

    const visitor = ReplaceSpanVisitor.init(@intCast(escape_index), new_span, new_source_span);
    visitor.visit(ast);
}

// ─── Legacy API (kept for backwards compat with prior tests) ──

/// TcbConfig — TCB configuration options (legacy).
pub const TcbConfig = struct {
    strict_host_binding_types: bool = true,
    check_type_of_dom_events: bool = true,
};

/// Context — the TCB compilation context (legacy).
pub const Context = struct {
    allocator: std.mem.Allocator,
    config: TcbConfig = .{},
};

/// Scope — the template scope for variable resolution (legacy).
pub const Scope = struct {
    allocator: std.mem.Allocator,
};

/// HostBindingType — kind of host binding (legacy).
pub const HostBindingType = enum(u8) {
    Property,
    Attribute,
    Class,
    Style,
    Event,
    TwoWay,
    LegacyAnimation,
    Animation,
};

/// HostBindingInfo — info about a single host binding (legacy).
pub const HostBindingInfo = struct {
    name: []const u8,
    binding_type: HostBindingType,
    value: []const u8 = "",
    handler: []const u8 = "",
    source_span: ?[]const u8 = null,
};

/// HostBindings — the collection of host bindings for a directive (legacy).
pub const HostBindings = struct {
    properties: []const HostBindingInfo = &.{},
    attributes: []const HostBindingInfo = &.{},
    events: []const HostBindingInfo = &.{},
    two_way_bindings: []const HostBindingInfo = &.{},
};

/// Check host bindings for a directive (legacy).
pub fn checkHostBindings(
    allocator: std.mem.Allocator,
    tcb: *const Context,
    scope: *const Scope,
    host: HostBindings,
    dir_instance: []const u8,
) ![]TcbExpr {
    _ = scope;
    var results = std.array_list.Managed(TcbExpr).init(allocator);
    errdefer results.deinit();

    for (host.properties) |prop| {
        if (tcb.config.strict_host_binding_types) {
            const check = try std.fmt.allocPrint(
                allocator,
                "{s}.{s} = {s}",
                .{ dir_instance, prop.name, prop.value },
            );
            try results.append(check);
        }
    }

    for (host.attributes) |attr| {
        const check = try std.fmt.allocPrint(
            allocator,
            "document.createElement('div').setAttribute('{s}', {s})",
            .{ attr.name, attr.value },
        );
        try results.append(check);
    }

    for (host.events) |event| {
        if (tcb.config.check_type_of_dom_events) {
            const check = try std.fmt.allocPrint(
                allocator,
                "document.createElement('div').addEventListener('{s}', $event => {s})",
                .{ event.name, event.handler },
            );
            try results.append(check);
        } else {
            const check = try std.fmt.allocPrint(
                allocator,
                "($event: any) => {s}",
                .{event.handler},
            );
            try results.append(check);
        }
    }

    for (host.two_way_bindings) |twb| {
        const check = try std.fmt.allocPrint(
            allocator,
            "{s}.{s} && ({s}.{s} = {s})",
            .{ dir_instance, twb.name, dir_instance, twb.name, twb.value },
        );
        try results.append(check);
    }

    return results.toOwnedSlice();
}

/// Check a single host property binding (legacy).
pub fn checkHostProperty(
    allocator: std.mem.Allocator,
    tcb: *const Context,
    prop: HostBindingInfo,
    dir_instance: []const u8,
) !TcbExpr {
    _ = tcb;
    return std.fmt.allocPrint(allocator, "{s}.{s} = {s}", .{ dir_instance, prop.name, prop.value });
}

/// Check a single host event binding (legacy).
pub fn checkHostEvent(
    allocator: std.mem.Allocator,
    tcb: *const Context,
    event: HostBindingInfo,
) !TcbExpr {
    if (tcb.config.check_type_of_dom_events) {
        return std.fmt.allocPrint(
            allocator,
            "document.createElement('div').addEventListener('{s}', $event => {s})",
            .{ event.name, event.handler },
        );
    }
    return std.fmt.allocPrint(allocator, "($event: any) => {s}", .{event.handler});
}

// ─── Tests ─────────────────────────────────────────────────

test "inferBoundAttribute property" {
    const r = inferBoundAttribute("id");
    try std.testing.expectEqualStrings("id", r.attr_name);
    try std.testing.expectEqual(BindingType.Property, r.type);
}

test "inferBoundAttribute attribute" {
    const r = inferBoundAttribute("attr.aria-label");
    try std.testing.expectEqualStrings("aria-label", r.attr_name);
    try std.testing.expectEqual(BindingType.Attribute, r.type);
}

test "inferBoundAttribute class" {
    const r = inferBoundAttribute("class.active");
    try std.testing.expectEqualStrings("active", r.attr_name);
    try std.testing.expectEqual(BindingType.Class, r.type);
}

test "inferBoundAttribute style" {
    const r = inferBoundAttribute("style.color");
    try std.testing.expectEqualStrings("color", r.attr_name);
    try std.testing.expectEqual(BindingType.Style, r.type);
}

test "inferBoundAttribute animation (new)" {
    const r = inferBoundAttribute("animate.fadeIn");
    try std.testing.expectEqualStrings("animate.fadeIn", r.attr_name);
    try std.testing.expectEqual(BindingType.Animation, r.type);
}

test "inferBoundAttribute animation (legacy)" {
    const r = inferBoundAttribute("@fadeIn");
    try std.testing.expectEqualStrings("fadeIn", r.attr_name);
    try std.testing.expectEqual(BindingType.LegacyAnimation, r.type);
}

test "createHostBindingsBlockGuard format" {
    const allocator = std.testing.allocator;
    const guard = try createHostBindingsBlockGuard(allocator);
    defer allocator.free(guard);
    try std.testing.expectEqualStrings("(true /*hostBindingsBlockGuard*/)", guard);
}

test "DirectiveType fallback tag name" {
    try std.testing.expectEqualStrings("ng-component", DirectiveType.component.fallbackTagName());
    try std.testing.expectEqualStrings("ng-directive", DirectiveType.directive.fallbackTagName());
}

test "SourceNode.fromString" {
    const span = AbsoluteSourceSpan{ .start = 0, .end = 5 };
    const node = SourceNode.fromString("'foo'", "foo", span);
    try std.testing.expect(node == .string);
    try std.testing.expectEqualStrings("foo", node.text());
    try std.testing.expectEqualStrings("'foo'", node.source());
    try std.testing.expectEqual(@as(u32, 0), node.sourceSpan().start);
}

test "SourceNode.fromIdentifier" {
    const span = AbsoluteSourceSpan{ .start = 0, .end = 3 };
    const node = SourceNode.fromIdentifier("foo", "foo", span);
    try std.testing.expect(node == .identifier);
    try std.testing.expectEqualStrings("foo", node.text());
}

test "SourceNode.unspecifiedFrom" {
    const span = AbsoluteSourceSpan{ .start = 5, .end = 10 };
    const node = SourceNode.unspecifiedFrom(span);
    try std.testing.expect(node == .unspecified);
    try std.testing.expectEqualStrings("", node.text());
    try std.testing.expectEqual(@as(u32, 5), node.sourceSpan().start);
}

test "createHostElement returns null when no bindings" {
    const allocator = std.testing.allocator;
    const result = try createHostElement(
        allocator,
        .directive,
        null,
        .{ .start = 0, .end = 0 },
        &.{},
        &.{},
        &.{},
    );
    try std.testing.expect(result == null);
}

test "createHostElement with host object literal property binding" {
    const allocator = std.testing.allocator;
    const key = SourceNode.fromString("'[id]", "[id]", .{ .start = 0, .end = 5 });
    const value = SourceNode.fromString("'myId'", "myId", .{ .start = 5, .end = 11 });
    const bindings = [_]HostObjectLiteralBinding{HostObjectLiteralBinding{
        .key = key,
        .value = value,
        .source_span = .{ .start = 0, .end = 11 },
    }};
    const result = try createHostElement(
        allocator,
        .component,
        "app-foo",
        .{ .start = 0, .end = 7 },
        &bindings,
        &.{},
        &.{},
    );
    try std.testing.expect(result != null);
    const host = result.?;
    defer host.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), host.bindings.len);
    try std.testing.expectEqualStrings("id", host.bindings[0].name);
    try std.testing.expectEqual(BindingType.Property, host.bindings[0].type);
    try std.testing.expectEqual(@as(usize, 1), host.tag_names.len);
    try std.testing.expectEqualStrings("app-foo", host.tag_names[0]);
}

test "createHostElement falls back to ng-component tag" {
    const allocator = std.testing.allocator;
    const key = SourceNode.fromString("'[id]'", "[id]", .{ .start = 0, .end = 5 });
    const value = SourceNode.fromString("'myId'", "myId", .{ .start = 5, .end = 11 });
    const bindings = [_]HostObjectLiteralBinding{HostObjectLiteralBinding{
        .key = key,
        .value = value,
        .source_span = .{ .start = 0, .end = 11 },
    }};
    const result = try createHostElement(
        allocator,
        .component,
        null,
        .{ .start = 0, .end = 7 },
        &bindings,
        &.{},
        &.{},
    );
    try std.testing.expect(result != null);
    const host = result.?;
    defer host.deinit(allocator);
    try std.testing.expectEqualStrings("ng-component", host.tag_names[0]);
}

test "createHostElement with host object literal event binding" {
    const allocator = std.testing.allocator;
    const key = SourceNode.fromString("'(click)'", "(click)", .{ .start = 0, .end = 7 });
    const value = SourceNode.fromString("'onClick()'", "onClick()", .{ .start = 8, .end = 19 });
    const bindings = [_]HostObjectLiteralBinding{HostObjectLiteralBinding{
        .key = key,
        .value = value,
        .source_span = .{ .start = 0, .end = 19 },
    }};
    const result = try createHostElement(
        allocator,
        .directive,
        "[myDir]",
        .{ .start = 0, .end = 7 },
        &bindings,
        &.{},
        &.{},
    );
    try std.testing.expect(result != null);
    const host = result.?;
    defer host.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), host.bindings.len);
    try std.testing.expectEqual(@as(usize, 1), host.listeners.len);
    try std.testing.expectEqualStrings("click", host.listeners[0].name);
    try std.testing.expectEqual(ParsedEventType.Regular, host.listeners[0].type);
    // No element name in selector → fallback.
    try std.testing.expectEqualStrings("ng-directive", host.tag_names[0]);
}

test "createHostElement with @HostBinding decorator (no args)" {
    const allocator = std.testing.allocator;
    const member_name = StaticSourceNode{
        .kind = .identifier,
        .source = "id",
        .text = "id",
        .source_span = .{ .start = 0, .end = 2 },
    };
    const decorators = [_]HostBindingDecorator{HostBindingDecorator{
        .member_name = member_name,
        .member_span = .{ .start = 0, .end = 2 },
        .arguments = &.{},
        .decorator_span = .{ .start = 0, .end = 2 },
    }};
    const result = try createHostElement(
        allocator,
        .component,
        "app-foo",
        .{ .start = 0, .end = 7 },
        &.{},
        &decorators,
        &.{},
    );
    try std.testing.expect(result != null);
    const host = result.?;
    defer host.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), host.bindings.len);
    try std.testing.expectEqualStrings("id", host.bindings[0].name);
}

test "createHostElement with @HostBinding decorator (with args)" {
    const allocator = std.testing.allocator;
    const arg = SourceNode.fromString("'class.active'", "class.active", .{ .start = 0, .end = 14 });
    const member_name = StaticSourceNode{
        .kind = .identifier,
        .source = "isActive",
        .text = "isActive",
        .source_span = .{ .start = 0, .end = 8 },
    };
    const decorators = [_]HostBindingDecorator{HostBindingDecorator{
        .member_name = member_name,
        .member_span = .{ .start = 0, .end = 8 },
        .arguments = &[_]SourceNode{arg},
        .decorator_span = .{ .start = 0, .end = 14 },
    }};
    const result = try createHostElement(
        allocator,
        .component,
        "app-foo",
        .{ .start = 0, .end = 7 },
        &.{},
        &decorators,
        &.{},
    );
    try std.testing.expect(result != null);
    const host = result.?;
    defer host.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), host.bindings.len);
    try std.testing.expectEqualStrings("active", host.bindings[0].name);
    try std.testing.expectEqual(BindingType.Class, host.bindings[0].type);
}

test "createHostElement with @HostListener decorator" {
    const allocator = std.testing.allocator;
    const event_name = SourceNode.fromString("'click'", "click", .{ .start = 0, .end = 7 });
    const member_name = StaticSourceNode{
        .kind = .identifier,
        .source = "onClick",
        .text = "onClick",
        .source_span = .{ .start = 0, .end = 7 },
    };
    const decorators = [_]HostListenerDecorator{HostListenerDecorator{
        .event_name = event_name,
        .member_name = member_name,
        .member_span = .{ .start = 0, .end = 7 },
        .arguments = &.{},
        .decorator_span = .{ .start = 0, .end = 7 },
    }};
    const result = try createHostElement(
        allocator,
        .component,
        "app-foo",
        .{ .start = 0, .end = 7 },
        &.{},
        &.{},
        &decorators,
    );
    try std.testing.expect(result != null);
    const host = result.?;
    defer host.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), host.listeners.len);
    try std.testing.expectEqualStrings("click", host.listeners[0].name);
    try std.testing.expectEqual(ParsedEventType.Regular, host.listeners[0].type);
}

test "createHostElement with @HostListener legacy animation" {
    const allocator = std.testing.allocator;
    const event_name = SourceNode.fromString("'@fade.start'", "@fade.start", .{ .start = 0, .end = 13 });
    const member_name = StaticSourceNode{
        .kind = .identifier,
        .source = "onAnim",
        .text = "onAnim",
        .source_span = .{ .start = 0, .end = 6 },
    };
    const decorators = [_]HostListenerDecorator{HostListenerDecorator{
        .event_name = event_name,
        .member_name = member_name,
        .member_span = .{ .start = 0, .end = 6 },
        .arguments = &.{},
        .decorator_span = .{ .start = 0, .end = 13 },
    }};
    const result = try createHostElement(
        allocator,
        .component,
        "app-foo",
        .{ .start = 0, .end = 7 },
        &.{},
        &.{},
        &decorators,
    );
    try std.testing.expect(result != null);
    const host = result.?;
    defer host.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), host.listeners.len);
    try std.testing.expectEqualStrings("fade", host.listeners[0].name);
    try std.testing.expectEqual(ParsedEventType.LegacyAnimation, host.listeners[0].type);
    try std.testing.expectEqualStrings("start", host.listeners[0].phase.?);
}

test "createHostElement with @HostListener with target" {
    const allocator = std.testing.allocator;
    const event_name = SourceNode.fromString("'window:scroll'", "window:scroll", .{ .start = 0, .end = 15 });
    const member_name = StaticSourceNode{
        .kind = .identifier,
        .source = "onScroll",
        .text = "onScroll",
        .source_span = .{ .start = 0, .end = 8 },
    };
    const decorators = [_]HostListenerDecorator{HostListenerDecorator{
        .event_name = event_name,
        .member_name = member_name,
        .member_span = .{ .start = 0, .end = 8 },
        .arguments = &.{},
        .decorator_span = .{ .start = 0, .end = 15 },
    }};
    const result = try createHostElement(
        allocator,
        .component,
        "app-foo",
        .{ .start = 0, .end = 7 },
        &.{},
        &.{},
        &decorators,
    );
    try std.testing.expect(result != null);
    const host = result.?;
    defer host.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), host.listeners.len);
    try std.testing.expectEqualStrings("scroll", host.listeners[0].name);
    try std.testing.expectEqualStrings("window", host.listeners[0].target.?);
}

test "parseCssSelector extracts element names" {
    const allocator = std.testing.allocator;
    const parts = try parseCssSelector(allocator, "div, span, button");
    defer allocator.free(parts);
    try std.testing.expectEqual(@as(usize, 3), parts.len);
    try std.testing.expectEqualStrings("div", parts[0].element.?);
    try std.testing.expectEqualStrings("span", parts[1].element.?);
    try std.testing.expectEqualStrings("button", parts[2].element.?);
}

test "parseCssSelector handles class-only selectors" {
    const allocator = std.testing.allocator;
    const parts = try parseCssSelector(allocator, ".foo, .bar");
    defer allocator.free(parts);
    try std.testing.expectEqual(@as(usize, 2), parts.len);
    try std.testing.expect(parts[0].element == null);
    try std.testing.expect(parts[1].element == null);
}

test "parseCssSelector empty input" {
    const allocator = std.testing.allocator;
    const parts = try parseCssSelector(allocator, "");
    defer allocator.free(parts);
    try std.testing.expectEqual(@as(usize, 0), parts.len);
}

test "indexOfEscapeFrom finds escape" {
    try std.testing.expectEqual(@as(usize, 2), indexOfEscapeFrom("ab\\cd", 0).?);
    try std.testing.expect(indexOfEscapeFrom("abcd", 0) == null);
    try std.testing.expectEqual(@as(usize, 4), indexOfEscapeFrom("'foo\\'bar'", 1).?);
}

test "ReplaceSpanVisitor init" {
    const v = ReplaceSpanVisitor.init(
        5,
        .{ .start = 0, .end = 10 },
        .{ .start = 100, .end = 110 },
    );
    try std.testing.expectEqual(@as(u32, 5), v.after_index);
    try std.testing.expectEqual(@as(u32, 0), v.override_span.start);
    try std.testing.expectEqual(@as(u32, 100), v.override_source_span.start);
}

test "fixupSpans does nothing when no escapes" {
    // Build a node with no escapes in source.
    var node = AstNode.literalString(
        .{ .start = 0, .end = 5 },
        .{ .start = 0, .end = 5 },
        "hello",
    );
    const original_span = node.span;
    const static_node = StaticSourceNode{
        .kind = .string,
        .source = "'hello'",
        .text = "hello",
        .source_span = .{ .start = 0, .end = 7 },
    };
    fixupSpans(&node, static_node);
    try std.testing.expectEqual(original_span.start, node.span.start);
    try std.testing.expectEqual(original_span.end, node.span.end);
}

test "fixupSpans overrides spans when escapes present" {
    var node = AstNode.literalString(
        .{ .start = 10, .end = 20 },
        .{ .start = 100, .end = 110 },
        "value",
    );
    const static_node = StaticSourceNode{
        .kind = .string,
        .source = "'val\\ue'",
        .text = "val\\ue",
        .source_span = .{ .start = 100, .end = 108 },
    };
    fixupSpans(&node, static_node);
    // After fixupSpans, the node's span should be overridden because its
    // original span (10, 20) is after the escape index (4).
    try std.testing.expectEqual(@as(u32, 0), node.span.start);
    try std.testing.expectEqual(@as(u32, 8), node.span.end);
    try std.testing.expectEqual(@as(u32, 100), node.source_span.start);
    try std.testing.expectEqual(@as(u32, 108), node.source_span.end);
}

test "HOST_BINDING_GUARD_COMMENT_TEXT value" {
    try std.testing.expectEqualStrings("hostBindingsBlockGuard", HOST_BINDING_GUARD_COMMENT_TEXT);
}

test "BindingType enum values" {
    try std.testing.expectEqual(BindingType.Property, inferBoundAttribute("x").type);
    try std.testing.expectEqual(BindingType.Attribute, inferBoundAttribute("attr.x").type);
    try std.testing.expectEqual(BindingType.Class, inferBoundAttribute("class.x").type);
    try std.testing.expectEqual(BindingType.Style, inferBoundAttribute("style.x").type);
    try std.testing.expectEqual(BindingType.Animation, inferBoundAttribute("animate.x").type);
    try std.testing.expectEqual(BindingType.LegacyAnimation, inferBoundAttribute("@x").type);
}

test "ParsedEventType enum values" {
    try std.testing.expectEqual(ParsedEventType.Regular, .Regular);
    try std.testing.expectEqual(ParsedEventType.Animation, .Animation);
    try std.testing.expectEqual(ParsedEventType.LegacyAnimation, .LegacyAnimation);
}

test "checkHostProperty generates assignment" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const prop = HostBindingInfo{
        .name = "class.active",
        .binding_type = .Property,
        .value = "isActive",
    };
    const result = try checkHostProperty(allocator, &ctx, prop, "dir");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("dir.class.active = isActive", result);
}

test "checkHostEvent generates addEventListener" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const event = HostBindingInfo{
        .name = "click",
        .binding_type = .Event,
        .handler = "onClick($event)",
    };
    const result = try checkHostEvent(allocator, &ctx, event);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "addEventListener") != null);
}

test "checkHostBindings with empty bindings" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    const host = HostBindings{};
    const results = try checkHostBindings(allocator, &ctx, &scope, host, "dir");
    defer allocator.free(results);
    try std.testing.expectEqual(@as(usize, 0), results.len);
}

test "checkHostBindings with property and event" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    const props = [_]HostBindingInfo{HostBindingInfo{
        .name = "id",
        .binding_type = .Property,
        .value = "myId",
    }};
    const events = [_]HostBindingInfo{HostBindingInfo{
        .name = "click",
        .binding_type = .Event,
        .handler = "onClick()",
    }};
    const host = HostBindings{
        .properties = &props,
        .events = &events,
    };
    const results = try checkHostBindings(allocator, &ctx, &scope, host, "dir");
    defer {
        for (results) |r| allocator.free(r);
        allocator.free(results);
    }
    try std.testing.expectEqual(@as(usize, 2), results.len);
    try std.testing.expect(std.mem.indexOf(u8, results[0], "dir.id = myId") != null);
    try std.testing.expect(std.mem.indexOf(u8, results[1], "addEventListener") != null);
}

test "HostElement struct" {
    const host = HostElement{
        .tag_names = &.{"div"},
        .bindings = &.{},
        .listeners = &.{},
        .name_span = .{ .start = 0, .end = 3 },
    };
    try std.testing.expectEqual(@as(usize, 1), host.tag_names.len);
    try std.testing.expectEqualStrings("div", host.tag_names[0]);
}

test "SourceNodeKind tag values" {
    try std.testing.expect(@intFromEnum(SourceNodeKind.string) == 0);
    try std.testing.expect(@intFromEnum(SourceNodeKind.identifier) == 1);
    try std.testing.expect(@intFromEnum(SourceNodeKind.unspecified) == 2);
}

test "HostObjectLiteralBinding struct" {
    const key = SourceNode.fromString("[id]", "id", .{ .start = 0, .end = 4 });
    const value = SourceNode.fromString("'foo'", "foo", .{ .start = 5, .end = 10 });
    const b = HostObjectLiteralBinding{
        .key = key,
        .value = value,
        .source_span = .{ .start = 0, .end = 10 },
    };
    try std.testing.expectEqual(@as(u32, 0), b.source_span.start);
    try std.testing.expectEqualStrings("id", b.key.text());
    try std.testing.expectEqualStrings("foo", b.value.text());
}

test "HostListenerDecorator struct with null event_name" {
    const member_name = StaticSourceNode{
        .kind = .identifier,
        .source = "onClick",
        .text = "onClick",
        .source_span = .{ .start = 0, .end = 7 },
    };
    const d = HostListenerDecorator{
        .event_name = null,
        .member_name = member_name,
        .member_span = .{ .start = 0, .end = 7 },
        .arguments = &.{},
        .decorator_span = .{ .start = 0, .end = 7 },
    };
    try std.testing.expect(d.event_name == null);
    try std.testing.expectEqualStrings("onClick", d.member_name.text);
}
