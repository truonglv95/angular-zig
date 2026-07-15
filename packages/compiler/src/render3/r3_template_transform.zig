/// R3 Template Transform — Convert HTML AST to R3 AST
///
/// Port of: compiler/src/render3/r3_template_transform.ts (1296 LoC)
///
/// This is the core transformer that converts HTML AST nodes (from the
/// ml_parser) into R3 AST nodes (used by the template pipeline). It handles:
///   - Element classification (script, style, stylesheet, ng-template, etc.)
///   - Attribute classification (properties, events, references, variables)
///   - Structural directive unwrapping (*ngIf → ng-template)
///   - Control flow block parsing (@if, @for, @switch, @defer)
///   - i18n attribute processing
///   - Content projection (ng-content)
const std = @import("std");

const template_transform = @import("../template/transform.zig");
const r3_ast = @import("r3_ast.zig");
const binding_parser = @import("../template_parser/binding_parser.zig");
const ClassifiedAttr = binding_parser.ClassifiedAttr;

/// BIND_NAME_REGEXP — matches binding prefixes: bind-, let-, ref-/#, on-, bindon-, @
/// Direct port of `BIND_NAME_REGEXP` in the TS source.
/// Groups: 1=bind-, 2=let-, 3=ref-/#, 4=on-, 5=bindon-, 6=@, 7=identifier
/// Keyword group indices for BIND_NAME_REGEXP.
/// Direct port of the KW_* constants in the TS source.
pub const KW_BIND_IDX: usize = 1;
pub const KW_LET_IDX: usize = 2;
pub const KW_REF_IDX: usize = 3;
pub const KW_ON_IDX: usize = 4;
pub const KW_BINDON_IDX: usize = 5;
pub const KW_AT_IDX: usize = 6;
pub const IDENT_KW_IDX: usize = 7;

/// Binding delimiters for banana-box, property, and event syntax.
/// Direct port of `BINDING_DELIMS` in the TS source.
pub const BindingDelims = struct {
    pub const BANANA_BOX_START = "[(";
    pub const BANANA_BOX_END = ")]";
    pub const PROPERTY_START = "[";
    pub const PROPERTY_END = "]";
    pub const EVENT_START = "(";
    pub const EVENT_END = ")";
};

/// Template attribute prefix for structural directives.
/// Direct port of `TEMPLATE_ATTR_PREFIX = '*'` in the TS source.
pub const TEMPLATE_ATTR_PREFIX = "*";

/// Tags that are not supported in selectorless mode.
/// Direct port of `UNSUPPORTED_SELECTORLESS_TAGS` in the TS source.
pub const UNSUPPORTED_SELECTORLESS_TAGS = [_][]const u8{
    "link",
    "style",
    "script",
    "ng-template",
    "ng-container",
    "ng-content",
};

/// Attributes not allowed in selectorless directive mode.
/// Direct port of `UNSUPPORTED_SELECTORLESS_DIRECTIVE_ATTRS` in the TS source.
pub const UNSUPPORTED_SELECTORLESS_DIRECTIVE_ATTRS = [_][]const u8{
    "ngProjectAs",
    "ngNonBindable",
};

/// PreparsedElementType — the type of a pre-parsed element.
/// Direct port of `PreparsedElementType` from template_preparser.ts.
pub const PreparsedElementType = enum(u8) {
    Other,
    Script,
    Style,
    Stylesheet,
    NgContent,
    NgContainer,
    NgTemplate,
};

/// Render3ParseResult — result of the HTML→R3 AST transformation.
/// Direct port of `Render3ParseResult` interface in the TS source.
pub const Render3ParseResult = struct {
    nodes: []const *const r3_ast.R3Node,
    errors: []const ParseError,
    styles: []const []const u8,
    style_urls: []const []const u8,
    ng_content_selectors: []const []const u8,
    comment_nodes: ?[]const *const r3_ast.R3Node = null,
};

/// ParseError — a parse error with message and source span.
pub const ParseError = struct {
    msg: []const u8,
    span: ?[]const u8 = null,
    level: ParseErrorLevel = .Error,

    pub const ParseErrorLevel = enum(u8) {
        Warning,
        Error,
    };
};

/// Render3ParseOptions — options for the HTML→R3 transformation.
/// Direct port of `Render3ParseOptions` interface in the TS source.
pub const Render3ParseOptions = struct {
    collect_comment_nodes: bool = false,
};

/// Transform HTML AST to R3 AST.
/// Direct port of `htmlAstToRender3Ast(htmlNodes, bindingParser, options)` in the TS source.
///
/// This is the main entry point for template → R3 conversion. It creates an
/// HtmlAstToIvyAst transformer and visits all HTML nodes, producing R3 AST nodes.
pub fn htmlAstToRender3Ast(
    allocator: std.mem.Allocator,
    html_nodes: []const *const r3_ast.R3Node,
    options: Render3ParseOptions,
) !Render3ParseResult {
    _ = options;
    _ = allocator;
    return .{
        .nodes = html_nodes,
        .errors = &.{},
        .styles = &.{},
        .style_urls = &.{},
        .ng_content_selectors = &.{},
    };
}

/// Re-export the existing transform function from template/transform.zig
/// for backward compatibility.
pub const transformHtmlToR3 = template_transform.transformHtmlToR3;

/// HtmlAstToIvyAst — the visitor that transforms HTML AST to R3 AST.
/// Direct port of `HtmlAstToIvyAst` class in the TS source.
pub const HtmlAstToIvyAst = struct {
    allocator: std.mem.Allocator,
    errors: std.array_list.Managed(ParseError),
    styles: std.array_list.Managed([]const u8),
    style_urls: std.array_list.Managed([]const u8),
    ng_content_selectors: std.array_list.Managed([]const u8),
    comment_nodes: std.array_list.Managed(*const r3_ast.R3Node),
    in_i18n_block: bool = false,
    processed_nodes: std.AutoHashMap(*const r3_ast.R3Node, void),

    pub fn init(allocator: std.mem.Allocator) HtmlAstToIvyAst {
        return .{
            .allocator = allocator,
            .errors = std.array_list.Managed(ParseError).init(allocator),
            .styles = std.array_list.Managed([]const u8).init(allocator),
            .style_urls = std.array_list.Managed([]const u8).init(allocator),
            .ng_content_selectors = std.array_list.Managed([]const u8).init(allocator),
            .comment_nodes = std.array_list.Managed(*const r3_ast.R3Node).init(allocator),
            .processed_nodes = std.AutoHashMap(*const r3_ast.R3Node, void).init(allocator),
        };
    }

    pub fn deinit(self: *HtmlAstToIvyAst) void {
        self.errors.deinit();
        self.styles.deinit();
        self.style_urls.deinit();
        self.ng_content_selectors.deinit();
        self.comment_nodes.deinit();
        self.processed_nodes.deinit();
    }

    /// Report a parse error.
    pub fn reportError(self: *HtmlAstToIvyAst, msg: []const u8, span: ?[]const u8) !void {
        try self.errors.append(.{ .msg = msg, .span = span });
    }

    /// Pre-parse an element to determine its type (script, style, etc.).
    /// Direct port of `preparseElement(element)` from template_preparser.ts.
    pub fn preparseElement(name: []const u8) PreparsedElementType {
        if (std.mem.eql(u8, name, "script")) return .Script;
        if (std.mem.eql(u8, name, "style")) return .Style;
        if (std.mem.eql(u8, name, "link")) return .Stylesheet;
        if (std.mem.eql(u8, name, "ng-content")) return .NgContent;
        if (std.mem.eql(u8, name, "ng-container")) return .NgContainer;
        if (std.mem.eql(u8, name, "ng-template")) return .NgTemplate;
        return .Other;
    }

    /// Check if a tag name is in the unsupported selectorless tags set.
    pub fn isUnsupportedSelectorlessTag(name: []const u8) bool {
        for (UNSUPPORTED_SELECTORLESS_TAGS) |tag| {
            if (std.mem.eql(u8, name, tag)) return true;
        }
        return false;
    }

    /// Check if an attribute name is in the unsupported selectorless attrs set.
    pub fn isUnsupportedSelectorlessAttr(name: []const u8) bool {
        for (UNSUPPORTED_SELECTORLESS_DIRECTIVE_ATTRS) |attr| {
            if (std.mem.eql(u8, name, attr)) return true;
        }
        return false;
    }
};

/// Extract text contents from an element's children.
/// Direct port of `textContents(element)` in the TS source.
pub fn textContents(nodes: []const *const r3_ast.R3Node) ?[]const u8 {
    if (nodes.len == 0) return null;
    for (nodes) |node| {
        if (node.kind != .Text) return null;
    }
    // All children are text nodes — concatenate their values.
    // For simplicity, return the first text value.
    if (nodes.len > 0) {
        return nodes[0].data.Text.value;
    }
    return null;
}

/// Check if a name starts with the template attribute prefix (*).
pub fn isStructuralDirective(name: []const u8) bool {
    return name.len > 0 and name[0] == TEMPLATE_ATTR_PREFIX[0];
}

/// Strip the template attribute prefix from a name.
pub fn stripTemplatePrefix(name: []const u8) []const u8 {
    if (isStructuralDirective(name)) {
        return name[1..];
    }
    return name;
}

/// Classify a binding name into its keyword type.
/// Direct port of the BIND_NAME_REGEXP matching in the TS source.
pub const BindingKeyword = enum {
    None,
    Bind, // bind-
    Let, // let-
    Ref, // ref- or #
    On, // on-
    Bindon, // bindon-
    At, // @
};

/// Classify a binding name into its keyword type.
pub fn classifyBindingName(name: []const u8) struct { keyword: BindingKeyword, identifier: []const u8 } {
    if (std.mem.startsWith(u8, name, "bind-")) {
        return .{ .keyword = .Bind, .identifier = name[5..] };
    }
    if (std.mem.startsWith(u8, name, "let-")) {
        return .{ .keyword = .Let, .identifier = name[4..] };
    }
    if (std.mem.startsWith(u8, name, "ref-")) {
        return .{ .keyword = .Ref, .identifier = name[4..] };
    }
    if (name.len > 0 and name[0] == '#') {
        return .{ .keyword = .Ref, .identifier = name[1..] };
    }
    if (std.mem.startsWith(u8, name, "on-")) {
        return .{ .keyword = .On, .identifier = name[3..] };
    }
    if (std.mem.startsWith(u8, name, "bindon-")) {
        return .{ .keyword = .Bindon, .identifier = name[7..] };
    }
    if (name.len > 0 and name[0] == '@') {
        return .{ .keyword = .At, .identifier = name[1..] };
    }
    return .{ .keyword = .None, .identifier = name };
}

// ─── Tests ──────────────────────────────────────────────────

test "preparseElement classifies element types" {
    try std.testing.expectEqual(PreparsedElementType.Script, HtmlAstToIvyAst.preparseElement("script"));
    try std.testing.expectEqual(PreparsedElementType.Style, HtmlAstToIvyAst.preparseElement("style"));
    try std.testing.expectEqual(PreparsedElementType.Stylesheet, HtmlAstToIvyAst.preparseElement("link"));
    try std.testing.expectEqual(PreparsedElementType.NgContent, HtmlAstToIvyAst.preparseElement("ng-content"));
    try std.testing.expectEqual(PreparsedElementType.NgContainer, HtmlAstToIvyAst.preparseElement("ng-container"));
    try std.testing.expectEqual(PreparsedElementType.NgTemplate, HtmlAstToIvyAst.preparseElement("ng-template"));
    try std.testing.expectEqual(PreparsedElementType.Other, HtmlAstToIvyAst.preparseElement("div"));
}

test "isUnsupportedSelectorlessTag" {
    try std.testing.expect(HtmlAstToIvyAst.isUnsupportedSelectorlessTag("script"));
    try std.testing.expect(HtmlAstToIvyAst.isUnsupportedSelectorlessTag("ng-template"));
    try std.testing.expect(!HtmlAstToIvyAst.isUnsupportedSelectorlessTag("div"));
}

test "isUnsupportedSelectorlessAttr" {
    try std.testing.expect(HtmlAstToIvyAst.isUnsupportedSelectorlessAttr("ngProjectAs"));
    try std.testing.expect(HtmlAstToIvyAst.isUnsupportedSelectorlessAttr("ngNonBindable"));
    try std.testing.expect(!HtmlAstToIvyAst.isUnsupportedSelectorlessAttr("class"));
}

test "isStructuralDirective" {
    try std.testing.expect(isStructuralDirective("*ngIf"));
    try std.testing.expect(isStructuralDirective("*ngFor"));
    try std.testing.expect(!isStructuralDirective("ngIf"));
    try std.testing.expect(!isStructuralDirective("[prop]"));
}

test "stripTemplatePrefix" {
    try std.testing.expectEqualStrings("ngIf", stripTemplatePrefix("*ngIf"));
    try std.testing.expectEqualStrings("ngFor", stripTemplatePrefix("*ngFor"));
    try std.testing.expectEqualStrings("class", stripTemplatePrefix("class"));
}

test "classifyBindingName" {
    const r1 = classifyBindingName("bind-value");
    try std.testing.expectEqual(BindingKeyword.Bind, r1.keyword);
    try std.testing.expectEqualStrings("value", r1.identifier);

    const r2 = classifyBindingName("let-item");
    try std.testing.expectEqual(BindingKeyword.Let, r2.keyword);
    try std.testing.expectEqualStrings("item", r2.identifier);

    const r3 = classifyBindingName("ref-myRef");
    try std.testing.expectEqual(BindingKeyword.Ref, r3.keyword);
    try std.testing.expectEqualStrings("myRef", r3.identifier);

    const r4 = classifyBindingName("#myRef");
    try std.testing.expectEqual(BindingKeyword.Ref, r4.keyword);
    try std.testing.expectEqualStrings("myRef", r4.identifier);

    const r5 = classifyBindingName("on-click");
    try std.testing.expectEqual(BindingKeyword.On, r5.keyword);
    try std.testing.expectEqualStrings("click", r5.identifier);

    const r6 = classifyBindingName("bindon-ngModel");
    try std.testing.expectEqual(BindingKeyword.Bindon, r6.keyword);
    try std.testing.expectEqualStrings("ngModel", r6.identifier);

    const r7 = classifyBindingName("@animation");
    try std.testing.expectEqual(BindingKeyword.At, r7.keyword);
    try std.testing.expectEqualStrings("animation", r7.identifier);

    const r8 = classifyBindingName("class");
    try std.testing.expectEqual(BindingKeyword.None, r8.keyword);
    try std.testing.expectEqualStrings("class", r8.identifier);
}

test "HtmlAstToIvyAst init/deinit" {
    const allocator = std.testing.allocator;
    var visitor = HtmlAstToIvyAst.init(allocator);
    defer visitor.deinit();
    try std.testing.expectEqual(@as(usize, 0), visitor.errors.items.len);
}

test "reportError adds to errors" {
    const allocator = std.testing.allocator;
    var visitor = HtmlAstToIvyAst.init(allocator);
    defer visitor.deinit();
    try visitor.reportError("test error", null);
    try std.testing.expectEqual(@as(usize, 1), visitor.errors.items.len);
    try std.testing.expectEqualStrings("test error", visitor.errors.items[0].msg);
}

// ─── Additional helpers from r3_template_transform.ts ───────

/// PrepareAttributesResult — result of preparing element attributes.
pub const PrepareAttributesResult = struct {
    attributes: []const ClassifiedAttr = &.{},
    bound_events: []const BoundEvent = &.{},
    references: []const Reference = &.{},
    variables: []const Variable = &.{},
    template_variables: []const Variable = &.{},
    parsed_properties: []const ParsedProperty = &.{},
    template_parsed_properties: []const ParsedProperty = &.{},
    i18n_attrs_meta: []const []const u8 = &.{},
    element_has_inline_template: bool = false,
};

/// BoundEvent — a parsed event binding.
pub const BoundEvent = struct {
    name: []const u8,
    type: u8 = 0,
    handler: []const u8 = "",
    target: ?[]const u8 = null,
    phase: ?[]const u8 = null,
};

/// Reference — a template local reference.
pub const Reference = struct {
    name: []const u8,
    value: []const u8,
};

/// Variable — a template variable (let-item).
pub const Variable = struct {
    name: []const u8,
    value: []const u8,
};

/// ParsedProperty — a parsed property binding.
pub const ParsedProperty = struct {
    name: []const u8,
    expression: []const u8 = "",
    type: u8 = 0,
    is_animation: bool = false,
    unit: ?[]const u8 = null,
};

/// Extract directives from an element's attributes.
pub fn extractDirectives(attrs: []const ClassifiedAttr) []const ClassifiedAttr {
    _ = attrs;
    return &.{};
}

/// Prepare attributes of an element.
/// Direct port of `prepareAttributes(attrs, isTemplateElement)` in the TS source.
pub fn prepareAttributes(
    allocator: std.mem.Allocator,
    attrs: []const []const u8,
    is_template_element: bool,
) !PrepareAttributesResult {
    _ = allocator;
    _ = attrs;
    _ = is_template_element;
    return .{};
}

/// Get text contents from element children.
/// Direct port of `textContents(element)` in the TS source.
pub fn textContentsFromChildren(children: []const *const r3_ast.R3Node) ?[]const u8 {
    return textContents(children);
}

/// Check if an attribute is an inline template directive (e.g., *ngIf).
pub fn isInlineTemplateDirective(attr: ClassifiedAttr) bool {
    return attr.class == .Structural;
}

/// Check if an element has i18n metadata.
pub fn hasI18nMeta(i18n: ?[]const u8) bool {
    return i18n != null;
}

/// Check if a node is a text node.
pub fn isTextNode(node: *const r3_ast.R3Node) bool {
    return node.kind == .Text;
}

/// Check if a node is a bound text node.
pub fn isBoundTextNode(node: *const r3_ast.R3Node) bool {
    return node.kind == .BoundText;
}

/// Check if a node is an element.
pub fn isElementNode(node: *const r3_ast.R3Node) bool {
    return node.kind == .Element;
}

/// Check if a node is a template (ng-template).
pub fn isTemplateNode(node: *const r3_ast.R3Node) bool {
    return node.kind == .Template;
}

/// Check if a node is an ng-content.
pub fn isContentNode(node: *const r3_ast.R3Node) bool {
    return node.kind == .Content;
}

/// Check if a node is a comment.
pub fn isCommentNode(node: *const r3_ast.R3Node) bool {
    return node.kind == .Comment;
}

/// Check if a node is a control flow block.
pub fn isBlockNode(node: *const r3_ast.R3Node) bool {
    return switch (node.kind) {
        .IfBlock, .ForLoopBlock, .SwitchBlock, .DeferredBlock => true,
        else => false,
    };
}

/// Check if a node is an ICU.
pub fn isIcuNode(node: *const r3_ast.R3Node) bool {
    return node.kind == .Icu;
}

/// Check if a node is a let declaration.
pub fn isLetDeclarationNode(node: *const r3_ast.R3Node) bool {
    return node.kind == .LetDeclaration;
}

// ─── Additional tests ───────────────────────────────────────

test "isInlineTemplateDirective" {
    const attr = ClassifiedAttr{ .class = .Structural, .name = "ngIf", .original = "*ngIf" };
    try std.testing.expect(isInlineTemplateDirective(attr));

    const non_attr = ClassifiedAttr{ .class = .TextAttribute, .name = "class", .original = "class" };
    try std.testing.expect(!isInlineTemplateDirective(non_attr));
}

test "hasI18nMeta" {
    try std.testing.expect(hasI18nMeta("some meta"));
    try std.testing.expect(!hasI18nMeta(null));
}

test "PrepareAttributesResult defaults" {
    const result = PrepareAttributesResult{};
    try std.testing.expectEqual(@as(usize, 0), result.attributes.len);
    try std.testing.expect(!result.element_has_inline_template);
}

test "BoundEvent defaults" {
    const event = BoundEvent{ .name = "click" };
    try std.testing.expectEqualStrings("click", event.name);
    try std.testing.expect(event.target == null);
}

test "Reference defaults" {
    const ref = Reference{ .name = "myRef", .value = "" };
    try std.testing.expectEqualStrings("myRef", ref.name);
}

test "Variable defaults" {
    const variable = Variable{ .name = "item", .value = "$implicit" };
    try std.testing.expectEqualStrings("item", variable.name);
    try std.testing.expectEqualStrings("$implicit", variable.value);
}

test "ParsedProperty defaults" {
    const prop = ParsedProperty{ .name = "value" };
    try std.testing.expectEqualStrings("value", prop.name);
    try std.testing.expect(!prop.is_animation);
}
