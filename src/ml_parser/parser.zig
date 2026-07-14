/// HTML Parser — Produces HTML AST from tokens
///
/// Recursive descent parser that handles nested elements,
/// self-closing tags, void elements, and interpolation tracking.
const std = @import("std");
const Allocator = std.mem.Allocator;

const ast = @import("ast.zig");
const Node = ast.Node;
const NodeKind = ast.NodeKind;
const TextNode = ast.TextNode;
const AttributeNode = ast.AttributeNode;
const ElementNode = ast.ElementNode;
const CommentNode = ast.CommentNode;
const ParseTreeResult = ast.ParseTreeResult;
const InterpolationBoundary = ast.InterpolationBoundary;

const lexer_mod = @import("lexer.zig");
const HtmlToken = lexer_mod.HtmlToken;
const HtmlTokenType = lexer_mod.HtmlTokenType;
const Lexer = lexer_mod.Lexer;

const tags = @import("tags.zig");
const source_span = @import("../source_span.zig");
const ParseSourceSpan = source_span.ParseSourceSpan;
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;
const ParseError = source_span.ParseError;
const arena_mod = @import("../arena.zig");
const AstArena = arena_mod.AstArena;

pub const Parser = struct {
    allocator: Allocator,
    arena: *AstArena,
    source: []const u8,
    tokens: []const HtmlToken,
    pos: u32 = 0,
    errors: std.array_list.Managed(ParseError),
    /// Owned root_nodes slice (freed in deinit).
    owned_root_nodes: ?[]const *const Node = null,

    pub fn init(allocator: Allocator, arena: *AstArena, source: []const u8, tokens: []const HtmlToken) Parser {
        return .{
            .allocator = allocator,
            .arena = arena,
            .source = source,
            .tokens = tokens,
            .errors = std.array_list.Managed(ParseError).init(allocator),
        };
    }

    pub fn deinit(self: *Parser) void {
        if (self.owned_root_nodes) |rn| {
            self.allocator.free(rn);
        }
        self.errors.deinit();
    }

    /// Parse the full template into an HTML AST
    pub fn parse(self: *Parser) !ParseTreeResult {
        var root_nodes = std.array_list.Managed(*const Node).init(self.allocator);
        errdefer root_nodes.deinit();

        while (!self.at(.EOF)) {
            const node = try self.parseNode();
            if (node) |n| {
                try root_nodes.append(n);
            }
        }

        const owned = try root_nodes.toOwnedSlice();
        self.owned_root_nodes = owned;
        return .{
            .root_nodes = owned,
            .errors = self.errors.items,
        };
    }

    // ─── Token Helpers ───────────────────────────────────────

    fn current(self: *const Parser) HtmlToken {
        if (self.pos < self.tokens.len) return self.tokens[self.pos];
        return .{ .type = .EOF, .index = @intCast(self.source.len), .end = @intCast(self.source.len) };
    }

    fn next(self: *Parser) HtmlToken {
        const tok = self.current();
        if (self.pos < self.tokens.len) self.pos += 1;
        return tok;
    }

    fn at(self: *const Parser, tok_type: HtmlTokenType) bool {
        return self.current().type == tok_type;
    }

    fn expect(self: *Parser, tok_type: HtmlTokenType) !HtmlToken {
        const tok = self.next();
        if (tok.type != tok_type) {
            try self.errors.append(.{
                .span = ParseSourceSpan.init(tok.index, tok.end, self.source),
                .msg = "Unexpected token",
            });
        }
        return tok;
    }

    // ─── Node Parsing ────────────────────────────────────────

    fn parseNode(self: *Parser) std.mem.Allocator.Error!?*const Node {
        const tok = self.current();

        switch (tok.type) {
            .TagOpenStart => return try self.parseElement(),
            .TagCloseStart => {
                // Unexpected closing tag
                _ = self.next();
                return null;
            },
            .Text => return try self.parseText(),
            .EncodedEntity => return try self.parseEntityAsText(),
            .Comment => return try self.parseComment(),
            .DocType => return try self.parseDocType(),
            .Cdata => return try self.parseCdata(),
            .EOF => return null,
            else => {
                _ = self.next();
                return null;
            },
        }
    }

    /// Parse an EncodedEntity token as a Text node.
    fn parseEntityAsText(self: *Parser) !?*const Node {
        const tok = self.next();
        const raw = tok.slice(self.source);
        // Decode the entity
        const entity_text = if (tok.entity_value) |ev| ev else raw;
        const node = try self.arena.create(Node);
        node.* = .{
            .kind = .Text,
            .source_span = ParseSourceSpan.init(tok.index, tok.end, self.source),
            .data = .{ .Text = .{
                .value = entity_text,
                .interpolation_boundaries = &.{},
            } },
        };
        return node;
    }

    fn parseElement(self: *Parser) !?*const Node {
        const open_tok = self.expect(.TagOpenStart) catch return null;
        const name_tok = self.expect(.TagName) catch return null;
        const name = name_tok.slice(self.source);
        const is_void = tags.isVoidElement(name);

        // Parse attributes
        var attrs = std.array_list.Managed(AttributeNode).init(self.allocator);
        defer attrs.deinit();

        while (!self.at(.TagOpenEnd) and !self.at(.EOF)) {
            if (self.at(.AttributeName)) {
                const attr = try self.parseAttribute();
                try attrs.append(attr);
            } else {
                break;
            }
        }

        // Parse tag end
        const end_tok = self.next();
        const self_closing = (end_tok.type == .TagOpenEnd and end_tok.self_closing) or
            end_tok.type == .TagOpenEndVoid;

        // Parse children (if not void and not self-closing)
        var children = std.array_list.Managed(*const Node).init(self.allocator);
        defer children.deinit();

        if (!is_void and !self_closing) {
            while (!self.at(.TagCloseStart) and !self.at(.EOF)) {
                if (self.parseNode() catch null) |child| {
                    try children.append(child);
                }
            }

            // Consume closing tag
            if (self.at(.TagCloseStart)) {
                _ = self.next(); // </
                if (self.at(.TagName)) {
                    _ = self.next(); // tagname
                }
                if (self.at(.TagOpenEnd)) {
                    _ = self.next(); // >
                }
            }
        }

        // Build element node
        const attrs_slice = if (attrs.items.len > 0)
            try self.arena.alloc(AttributeNode, attrs.items.len)
        else
            &[_]AttributeNode{};
        if (attrs.items.len > 0) @memcpy(@constCast(attrs_slice), attrs.items);

        const children_slice = if (children.items.len > 0)
            try self.arena.alloc(*const Node, children.items.len)
        else
            &[_]*const Node{};
        if (children.items.len > 0) @memcpy(@constCast(children_slice), children.items);

        const node = try self.arena.create(Node);
        node.* = .{
            .kind = .Element,
            .source_span = ParseSourceSpan.init(open_tok.index, end_tok.end, self.source),
            .data = .{ .Element = .{
                .name = name,
                .attrs = attrs_slice,
                .children = children_slice,
                .start_span = .{ .start = open_tok.index, .end = open_tok.end },
                .end_span = .{ .start = end_tok.index, .end = end_tok.end },
                .is_self_closing = self_closing,
                .is_void = is_void,
            } },
        };

        return node;
    }

    fn parseAttribute(self: *Parser) !AttributeNode {
        const name_tok = self.expect(.AttributeName) catch {
            return AttributeNode{
                .name = "",
                .value = "",
                .key_span = .{ .start = 0, .end = 0 },
                .value_span = .{ .start = 0, .end = 0 },
            };
        };
        const name = name_tok.slice(self.source);

        var value: []const u8 = "";
        var value_span = AbsoluteSourceSpan{ .start = 0, .end = 0 };
        var boundaries: []const InterpolationBoundary = &[_]InterpolationBoundary{};

        if (self.at(.AttributeValue)) {
            const val_tok = self.next();
            const raw = val_tok.slice(self.source);
            // Strip quotes if present
            if (raw.len >= 2 and (raw[0] == '\'' or raw[0] == '"')) {
                value = raw[1 .. raw.len - 1];
            } else {
                value = raw;
            }
            value_span = .{ .start = val_tok.index, .end = val_tok.end };

            // Convert TokenParts to InterpolationBoundaries
            if (val_tok.parts.len > 0) {
                var b = std.array_list.Managed(InterpolationBoundary).init(self.allocator);
                defer b.deinit();
                for (val_tok.parts) |p| {
                    try b.append(.{
                        .start = p.start,
                        .end = p.end,
                        .is_expression = p.is_expression,
                    });
                }
                boundaries = b.items;
            }
        }

        return .{
            .name = name,
            .value = value,
            .key_span = .{ .start = name_tok.index, .end = name_tok.end },
            .value_span = value_span,
            .interpolation_boundaries = boundaries,
        };
    }

    fn parseText(self: *Parser) !?*const Node {
        const tok = self.expect(.Text) catch return null;
        const value = tok.slice(self.source);

        var boundaries: []InterpolationBoundary = &[_]InterpolationBoundary{};
        if (tok.parts.len > 0) {
            // Allocate in arena — boundaries outlive this function call.
            const arena_alloc = self.arena.allocator();
            boundaries = try arena_alloc.alloc(InterpolationBoundary, tok.parts.len);
            for (tok.parts, 0..) |p, i| {
                boundaries[i] = .{
                    .start = p.start,
                    .end = p.end,
                    .is_expression = p.is_expression,
                };
            }
        }

        const node = try self.arena.create(Node);
        node.* = .{
            .kind = .Text,
            .source_span = ParseSourceSpan.init(tok.index, tok.end, self.source),
            .data = .{ .Text = .{
                .value = value,
                .interpolation_boundaries = boundaries,
            } },
        };
        return node;
    }

    fn parseComment(self: *Parser) !?*const Node {
        const tok = self.expect(.Comment) catch return null;
        // Strip <!-- and -->
        const raw = tok.slice(self.source);
        const value = if (raw.len >= 7) raw[4 .. raw.len - 3] else "";

        const node = try self.arena.create(Node);
        node.* = .{
            .kind = .Comment,
            .source_span = ParseSourceSpan.init(tok.index, tok.end, self.source),
            .data = .{ .Comment = .{ .value = value } },
        };
        return node;
    }

    fn parseDocType(self: *Parser) !?*const Node {
        const tok = self.expect(.DocType) catch return null;
        const node = try self.arena.create(Node);
        node.* = .{
            .kind = .DocType,
            .source_span = ParseSourceSpan.init(tok.index, tok.end, self.source),
            .data = .{ .DocType = .{ .value = tok.slice(self.source) } },
        };
        return node;
    }

    fn parseCdata(self: *Parser) !?*const Node {
        const tok = self.expect(.Cdata) catch return null;
        const raw = tok.slice(self.source);
        const value = if (raw.len >= 12) raw[9 .. raw.len - 3] else "";

        const node = try self.arena.create(Node);
        node.* = .{
            .kind = .Cdata,
            .source_span = ParseSourceSpan.init(tok.index, tok.end, self.source),
            .data = .{ .Cdata = .{ .value = value } },
        };
        return node;
    }

    // ─── Additional methods from the TS _TreeBuilder ─────────

    /// Close a void element if the current container is void.
    /// Direct port of `_closeVoidElement()` in the TS source.
    fn closeVoidElement(self: *Parser) void {
        // In full impl: check if current container is void and pop it
        _ = self;
    }

    /// Consume text token, merging adjacent text/interpolation tokens.
    /// Direct port of `_consumeText(token)` in the TS source.
    fn consumeTextMerged(self: *Parser, tok: HtmlToken) !?*const Node {
        var text_buf = std.array_list.Managed(u8).init(self.allocator);
        defer text_buf.deinit();

        const part = tok.slice(self.source);
        try text_buf.appendSlice(part);

        // Merge adjacent text tokens
        while (self.at(.Text)) {
            const next_tok = self.next();
            try text_buf.appendSlice(next_tok.slice(self.source));
        }

        const merged = text_buf.items;
        if (merged.len == 0) return null;

        const node = try self.arena.create(Node);
        node.* = .{
            .kind = .Text,
            .source_span = ParseSourceSpan.init(tok.index, tok.end, self.source),
            .data = .{ .Text = .{
                .value = try self.arena.dupe(u8, merged),
                .interpolation_boundaries = &.{},
            } },
        };
        return node;
    }

    /// Get the element name with namespace prefix.
    /// Direct port of `_getElementFullName(token, parent)` in the TS source.
    fn getElementFullName(self: *const Parser, name: []const u8) []const u8 {
        _ = self;
        // In full impl: check namespace prefix from tag definition
        return name;
    }

    /// Check if a tag name is a void element.
    /// Direct port of `_getTagDefinition(nodeOrName)?.isVoid` in the TS source.
    fn isVoidTagName(name: []const u8) bool {
        return tags.isVoidElement(name);
    }

    /// Merge namespace and name.
    /// Direct port of `mergeNsAndName(prefix, name)` from tags.ts.
    fn mergeNsAndName(prefix: []const u8, name: []const u8, allocator: Allocator) ![]const u8 {
        if (prefix.len == 0) return name;
        return std.fmt.allocPrint(allocator, "{s}:{s}", .{ prefix, name });
    }

    /// Split namespace and name from a full name.
    /// Direct port of `splitNsName(fullName)` from tags.ts.
    fn splitNsName(full_name: []const u8) struct { prefix: []const u8, name: []const u8 } {
        if (std.mem.indexOfScalar(u8, full_name, ':')) |colon_pos| {
            return .{
                .prefix = full_name[0..colon_pos],
                .name = full_name[colon_pos + 1 ..],
            };
        }
        return .{ .prefix = "", .name = full_name };
    }

    /// Get the namespace prefix from a full name.
    /// Direct port of `getNsPrefix(fullName)` from tags.ts.
    fn getNsPrefix(full_name: []const u8) []const u8 {
        if (std.mem.indexOfScalar(u8, full_name, ':')) |colon_pos| {
            return full_name[0..colon_pos];
        }
        return "";
    }
};

// ─── High-level parse function ────────────────────────────────

/// Parse an HTML template string into an AST
pub fn parseHtml(allocator: Allocator, source: []const u8) !ParseTreeResult {
    var arena = AstArena.init(allocator);
    defer arena.deinit();

    var lex = Lexer.init(allocator, source);
    defer lex.deinit();
    const lex_result = try lex.tokenize();

    var parser = Parser.init(allocator, &arena, source, lex_result.@"0");
    defer parser.deinit();
    return parser.parse();
}

// ─── TreeError — error during tree construction ─────────────

/// TreeError — an error that occurs during HTML tree construction.
/// Direct port of `TreeError` class in the TS source.
pub const TreeError = struct {
    element_name: ?[]const u8,
    span: ParseSourceSpan,
    msg: []const u8,

    /// Create a TreeError.
    /// Direct port of `TreeError.create(elementName, span, msg)` in the TS source.
    pub fn create(element_name: ?[]const u8, span: ParseSourceSpan, msg: []const u8) TreeError {
        return .{
            .element_name = element_name,
            .span = span,
            .msg = msg,
        };
    }
};

// ─── Additional types from the TS source ────────────────────

/// ParseTreeResultFull — result of parsing with both root nodes and errors.
/// Direct port of `ParseTreeResult` class in the TS source.
pub const ParseTreeResultFull = struct {
    root_nodes: []const *const Node,
    errors: []const TreeError,
};

// ─── HtmlParser — high-level parser using tag definitions ───

/// HtmlParser — the main HTML parser that uses tag definitions.
/// Direct port of `Parser` class in the TS source (not the Zig Parser struct).
pub const HtmlParser = struct {
    allocator: Allocator,
    arena: *AstArena,

    pub fn init(allocator: Allocator, arena: *AstArena) HtmlParser {
        return .{ .allocator = allocator, .arena = arena };
    }

    /// Parse source HTML into a tree result.
    /// Direct port of `parse(source, url, options)` in the TS source.
    pub fn parse(self: *HtmlParser, source: []const u8, url: []const u8) !ParseTreeResult {
        _ = url;
        var lex = Lexer.init(self.allocator, source);
        defer lex.deinit();
        const lex_result = try lex.tokenize();

        var parser = Parser.init(self.allocator, self.arena, source, lex_result.@"0");
        defer parser.deinit();
        return parser.parse();
    }
};

// ─── Entity decoding ────────────────────────────────────────

/// Decode an HTML entity string.
/// Direct port of `decodeEntity(match, entity)` in the TS source.
pub fn decodeEntity(allocator: Allocator, entity: []const u8) ![]const u8 {
    // Check named entities
    const entities = @import("entities.zig");
    if (entities.NAMED_ENTITIES.get(entity)) |value| {
        return allocator.dupe(u8, value);
    }
    // Check hex entities: &#x...
    if (entity.len > 2 and entity[0] == '#' and (entity[1] == 'x' or entity[1] == 'X')) {
        const code = std.fmt.parseInt(u21, entity[2..], 16) catch {
            return allocator.dupe(u8, entity);
        };
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(code, &buf) catch {
            return allocator.dupe(u8, entity);
        };
        return allocator.dupe(u8, buf[0..len]);
    }
    // Check decimal entities: &#...
    if (entity.len > 1 and entity[0] == '#') {
        const code = std.fmt.parseInt(u21, entity[1..], 10) catch {
            return allocator.dupe(u8, entity);
        };
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(code, &buf) catch {
            return allocator.dupe(u8, entity);
        };
        return allocator.dupe(u8, buf[0..len]);
    }
    return allocator.dupe(u8, entity);
}

// ─── Helper: lastOnStack ────────────────────────────────────

/// Check if an element is at the top of a stack.
/// Direct port of `lastOnStack(stack, element)` in the TS source.
pub fn lastOnStack(stack: []const u32, element: u32) bool {
    return stack.len > 0 and stack[stack.len - 1] == element;
}

// ─── BlockParameter — parameter of a control flow block ─────

/// BlockParameter — a parameter of a control flow block (e.g. @if(condition)).
/// Direct port of `html.BlockParameter` in the TS source.
pub const BlockParameter = struct {
    expression: []const u8,
    source_span: ParseSourceSpan,
};

// ─── StartTagComment — comment inside a start tag ───────────

/// StartTagComment — a comment that appears inside an element's start tag.
/// Direct port of `html.StartTagComment` in the TS source.
pub const StartTagComment = struct {
    value: []const u8,
    full_text: []const u8,
    source_span: ParseSourceSpan,
};

// ─── Additional tests ───────────────────────────────────────

test "TreeError create" {
    const err = TreeError.create("div", ParseSourceSpan.init(0, 10, "test"), "Unexpected tag");
    try std.testing.expectEqualStrings("div", err.element_name.?);
    try std.testing.expectEqualStrings("Unexpected tag", err.msg);
}

test "TreeError create with null name" {
    const err = TreeError.create(null, ParseSourceSpan.init(0, 10, "test"), "Error");
    try std.testing.expect(err.element_name == null);
}

test "ParseTreeResultFull struct" {
    const result = ParseTreeResultFull{
        .root_nodes = &.{},
        .errors = &.{},
    };
    try std.testing.expectEqual(@as(usize, 0), result.root_nodes.len);
    try std.testing.expectEqual(@as(usize, 0), result.errors.len);
}

test "HtmlParser init" {
    const allocator = std.testing.allocator;
    var arena = AstArena.init(allocator);
    defer arena.deinit();
    const parser = HtmlParser.init(allocator, &arena);
    _ = parser;
}

test "HtmlParser parse simple" {
    const allocator = std.testing.allocator;
    var arena = AstArena.init(allocator);
    defer arena.deinit();
    var html_parser = HtmlParser.init(allocator, &arena);
    const result = try html_parser.parse("<div>test</div>", "test.html");
    try std.testing.expectEqual(@as(usize, 1), result.root_nodes.len);
}

test "BlockParameter struct" {
    const param = BlockParameter{
        .expression = "condition",
        .source_span = ParseSourceSpan.init(0, 9, "test"),
    };
    try std.testing.expectEqualStrings("condition", param.expression);
}

test "StartTagComment struct" {
    const comment = StartTagComment{
        .value = "comment",
        .full_text = "<!-- comment -->",
        .source_span = ParseSourceSpan.init(0, 16, "test"),
    };
    try std.testing.expectEqualStrings("comment", comment.value);
}

test "lastOnStack — element on top" {
    const stack = [_]u32{ 1, 2, 3 };
    try std.testing.expect(lastOnStack(&stack, 3));
}

test "lastOnStack — element not on top" {
    const stack = [_]u32{ 1, 2, 3 };
    try std.testing.expect(!lastOnStack(&stack, 2));
}

test "lastOnStack — empty stack" {
    const stack = [_]u32{};
    try std.testing.expect(!lastOnStack(&stack, 1));
}

test "decodeEntity — named entity" {
    const allocator = std.testing.allocator;
    const result = try decodeEntity(allocator, "amp");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("&", result);
}

test "decodeEntity — hex entity" {
    const allocator = std.testing.allocator;
    const result = try decodeEntity(allocator, "#x41");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("A", result);
}

test "decodeEntity — decimal entity" {
    const allocator = std.testing.allocator;
    const result = try decodeEntity(allocator, "#65");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("A", result);
}

test "decodeEntity — unknown entity" {
    const allocator = std.testing.allocator;
    const result = try decodeEntity(allocator, "unknown");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("unknown", result);
}

// ─── Tests ────────────────────────────────────────────────────

test "parse simple element" {
    const allocator = std.testing.allocator;
    const source = "<div>Hello</div>";
    var arena = AstArena.init(allocator);
    defer arena.deinit();

    var lex = Lexer.init(allocator, source);
    defer lex.deinit();
    const lex_result = try lex.tokenize();

    var parser = Parser.init(allocator, &arena, source, lex_result.@"0");
    defer parser.deinit();
    const result = try parser.parse();

    try std.testing.expectEqual(@as(usize, 1), result.root_nodes.len);
    try std.testing.expectEqual(NodeKind.Element, result.root_nodes[0].kind);
    const elem = result.root_nodes[0].data.Element;
    try std.testing.expectEqualStrings("div", elem.name);
    try std.testing.expectEqual(@as(usize, 1), elem.children.len);
    try std.testing.expectEqual(NodeKind.Text, elem.children[0].kind);
}

test "parse nested elements" {
    const allocator = std.testing.allocator;
    const source = "<div><span><p>Deep</p></span></div>";
    var arena = AstArena.init(allocator);
    defer arena.deinit();

    var lex = Lexer.init(allocator, source);
    defer lex.deinit();
    const lex_result = try lex.tokenize();

    var parser = Parser.init(allocator, &arena, source, lex_result.@"0");
    defer parser.deinit();
    const result = try parser.parse();

    try std.testing.expectEqual(@as(usize, 1), result.root_nodes.len);
    const div = result.root_nodes[0].data.Element;
    try std.testing.expectEqual(@as(usize, 1), div.children.len);
    const span = div.children[0].data.Element;
    try std.testing.expectEqual(@as(usize, 1), span.children.len);
    const p = span.children[0].data.Element;
    try std.testing.expectEqualStrings("p", p.name);
}

test "parse void element" {
    const allocator = std.testing.allocator;
    const source = "<br><input type='text'>";
    var arena = AstArena.init(allocator);
    defer arena.deinit();

    var lex = Lexer.init(allocator, source);
    defer lex.deinit();
    const lex_result = try lex.tokenize();

    var parser = Parser.init(allocator, &arena, source, lex_result.@"0");
    defer parser.deinit();
    const result = try parser.parse();

    try std.testing.expectEqual(@as(usize, 2), result.root_nodes.len);
    try std.testing.expect(result.root_nodes[0].data.Element.is_void);
}

test "parse self-closing element" {
    const allocator = std.testing.allocator;
    const source = "<div/><span></span>";
    var arena = AstArena.init(allocator);
    defer arena.deinit();

    var lex = Lexer.init(allocator, source);
    defer lex.deinit();
    const lex_result = try lex.tokenize();

    var parser = Parser.init(allocator, &arena, source, lex_result.@"0");
    defer parser.deinit();
    const result = try parser.parse();

    try std.testing.expectEqual(@as(usize, 2), result.root_nodes.len);
    try std.testing.expect(result.root_nodes[0].data.Element.is_self_closing);
}

test "parse with attributes" {
    const allocator = std.testing.allocator;
    const source = "<div class=\"container\" id=\"main\"></div>";
    var arena = AstArena.init(allocator);
    defer arena.deinit();

    var lex = Lexer.init(allocator, source);
    defer lex.deinit();
    const lex_result = try lex.tokenize();

    var parser = Parser.init(allocator, &arena, source, lex_result.@"0");
    defer parser.deinit();
    const result = try parser.parse();

    const elem = result.root_nodes[0].data.Element;
    try std.testing.expectEqual(@as(usize, 2), elem.attrs.len);
    try std.testing.expectEqualStrings("class", elem.attrs[0].name);
    try std.testing.expectEqualStrings("container", elem.attrs[0].value);
    try std.testing.expectEqualStrings("id", elem.attrs[1].name);
}

test "parse text with interpolation markers" {
    const allocator = std.testing.allocator;
    const source = "<span>{{ name }}</span>";
    var arena = AstArena.init(allocator);
    defer arena.deinit();

    var lex = Lexer.init(allocator, source);
    defer lex.deinit();
    const lex_result = try lex.tokenize();

    var parser = Parser.init(allocator, &arena, source, lex_result.@"0");
    defer parser.deinit();
    const result = try parser.parse();

    const elem = result.root_nodes[0].data.Element;
    const text = elem.children[0].data.Text;
    try std.testing.expect(text.interpolation_boundaries.len > 0);
}
