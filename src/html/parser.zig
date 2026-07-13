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
        const self_closing = end_tok.type == .TagOpenEnd and end_tok.self_closing;

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
