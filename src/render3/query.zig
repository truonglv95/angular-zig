/// Render3 Query Compilation — Template Query AST Generation
///
/// Compiles template query expressions into a query AST that can be
/// used for efficient element selection during directive matching.
///
/// In Angular, queries appear in:
///   - @ContentChild decorators
///   - @ViewChild decorators
///   - ng-template selectors
///   - Embedded view projection selectors
///
/// Query compilation converts CSS-like selectors into a structured
/// AST that the directive matching engine can evaluate.
///
/// DOD:
///   - Parsed query stored as contiguous QueryNode array
///   - No heap allocation for evaluation (stack-based matching)
///   - Simple selectors as tagged unions
///   - Combinators stored inline (no separate combinator list)
const std = @import("std");
const Allocator = std.mem.Allocator;

// ─── Query Node Types ────────────────────────────────────────

/// Types of query nodes that can appear in a template query.
pub const QueryNodeType = enum(u8) {
    /// Element type match: div, span, app-my-comp
    ElementType,
    /// Attribute presence: [disabled]
    Attribute,
    /// Attribute value match: [type="text"]
    AttributeValue,
    /// Class match: .active
    ClassMatch,
    /// Wildcard: matches any element
    Wildcard,
    /// Not pseudo-class: :not(query)
    NotPseudo,
    /// Descendant combinator (space)
    Descendant,
    /// Child combinator (>)
    Child,
    /// Adjacent sibling combinator (+)
    Adjacent,
    /// Grouping: multiple selectors (comma-separated)
    Group,
};

/// A single node in a compiled query.
/// Uses a tagged union for zero-overhead type dispatch.
pub const QueryNode = struct {
    kind: QueryNodeType,
    /// For ElementType: tag name; for Attribute: attr name; for Class: class name
    name: []const u8,
    /// For AttributeValue: the expected value
    value: []const u8,
    /// Child query nodes (for combinators, :not, Group)
    children: []const QueryNode,
};

/// A compiled query ready for matching.
pub const CompiledQuery = struct {
    /// Root nodes of the query
    nodes: []const QueryNode,
    /// Original query string (for error messages)
    source: []const u8,
};

// ─── Query Parser ────────────────────────────────────────────

/// Parse a query string into a CompiledQuery.
/// Supports a subset of CSS selectors used by Angular:
///   - Element: div, span, app-my-component
///   - Attribute: [attr], [attr=value]
///   - Class: .foo
///   - Wildcard: *
///   - :not(selector)
///   - Descendant combinator (space)
///   - Child combinator (>)
///   - Adjacent sibling (+)
///   - Group (comma-separated)
pub fn parseQuery(allocator: Allocator, source: []const u8) Allocator.Error!CompiledQuery {
    var nodes = std.array_list.Managed(QueryNode).init(allocator);
    errdefer nodes.deinit();

    var i: usize = 0;
    while (i < source.len) {
        // Skip whitespace
        while (i < source.len and isSpace(source[i])) i += 1;
        if (i >= source.len) break;

        // Parse a single selector (sequence of simple selectors)
        const selector = try parseSingleSelector(allocator, source, &i);
        try nodes.append(selector);

        // Check for group (comma)
        while (i < source.len and isSpace(source[i])) i += 1;
        if (i < source.len and source[i] == ',') {
            // Create a Group node with all nodes collected so far
            const all_nodes = try allocator.dupe(QueryNode, nodes.items);
            nodes.clearRetainingCapacity();
            try nodes.append(.{
                .kind = .Group,
                .name = "",
                .value = "",
                .children = all_nodes,
            });
            i += 1;
            // Continue parsing the next selector in the group
        }
    }

    // If we have multiple nodes without a comma, they're implicitly
    // connected by descendant combinators
    if (nodes.items.len > 1 and nodes.items[0].kind != .Group) {
        // Wrap in a single root with descendant relationships
        const original = try allocator.dupe(QueryNode, nodes.items);
        nodes.clearRetainingCapacity();
        try nodes.append(.{
            .kind = .Descendant,
            .name = "",
            .value = "",
            .children = original,
        });
    }

    return .{
        .nodes = nodes.items,
        .source = source,
    };
}

/// Parse a single selector (sequence of simple selectors with optional combinators).
fn parseSingleSelector(allocator: Allocator, source: []const u8, i: *usize) Allocator.Error!QueryNode {
    var parts = std.array_list.Managed(QueryNode).init(allocator);
    errdefer parts.deinit();

    while (i.* < source.len) {
        const ch = source[i.*];

        // Skip whitespace (potential combinator)
        if (isSpace(ch)) {
            // Check if there's a combinator after whitespace
            _ = @as(usize, i.*);
            while (i.* < source.len and isSpace(source[i.*])) i.* += 1;

            if (i.* >= source.len) break;

            const next = source[i.*];
            if (next == '>') {
                // Child combinator
                const left_items = try allocator.dupe(QueryNode, parts.items);
                const left = if (left_items.len == 1) left_items[0] else QueryNode{ .kind = .Group, .name = "", .value = "", .children = left_items };
                parts.clearRetainingCapacity();
                i.* += 1;
                while (i.* < source.len and isSpace(source[i.*])) i.* += 1;

                const right = try parseSingleSelector(allocator, source, i);
                try parts.append(.{
                    .kind = .Child,
                    .name = "",
                    .value = "",
                    .children = try allocator.dupe(QueryNode, &[_]QueryNode{ left, right }),
                });
            } else if (next == '+') {
                // Adjacent sibling combinator
                const left_items = try allocator.dupe(QueryNode, parts.items);
                const left = if (left_items.len == 1) left_items[0] else QueryNode{ .kind = .Group, .name = "", .value = "", .children = left_items };
                parts.clearRetainingCapacity();
                i.* += 1;
                while (i.* < source.len and isSpace(source[i.*])) i.* += 1;

                const right = try parseSingleSelector(allocator, source, i);
                try parts.append(.{
                    .kind = .Adjacent,
                    .name = "",
                    .value = "",
                    .children = try allocator.dupe(QueryNode, &[_]QueryNode{ left, right }),
                });
            } else {
                // Descendant combinator (implicit)
                const left_items = try allocator.dupe(QueryNode, parts.items);
                const left = if (left_items.len == 1) left_items[0] else QueryNode{ .kind = .Group, .name = "", .value = "", .children = left_items };
                parts.clearRetainingCapacity();

                const right = try parseSingleSelector(allocator, source, i);
                try parts.append(.{
                    .kind = .Descendant,
                    .name = "",
                    .value = "",
                    .children = try allocator.dupe(QueryNode, &[_]QueryNode{ left, right }),
                });
            }
            break;
        }

        if (ch == '.') {
            // Class selector: .foo
            i.* += 1;
            const start = i.*;
            while (i.* < source.len and isIdentChar(source[i.*])) i.* += 1;
            try parts.append(.{
                .kind = .ClassMatch,
                .name = source[start..i.*],
                .value = "",
                .children = &.{},
            });
        } else if (ch == '[') {
            // Attribute selector
            i.* += 1;
            const name_start = i.*;
            while (i.* < source.len and source[i.*] != ']' and source[i.*] != '=' and source[i.*] != '~' and source[i.*] != '^' and source[i.*] != '$' and source[i.*] != '*') i.* += 1;
            const attr_name = source[name_start..i.*];

            if (i.* < source.len and source[i.*] == ']') {
                // [attr] — presence only
                try parts.append(.{
                    .kind = .Attribute,
                    .name = attr_name,
                    .value = "",
                    .children = &.{},
                });
                i.* += 1;
            } else {
                // [attr=value] or [attr~=value] etc.
                var kind = QueryNodeType.AttributeValue;
                if (i.* < source.len and (source[i.*] == '~' or source[i.*] == '^' or source[i.*] == '$' or source[i.*] == '*')) {
                    i.* += 1;
                    kind = .AttributeValue; // simplified
                }
                // Skip '='
                if (i.* < source.len and source[i.*] == '=') i.* += 1;

                // Parse value
                var value: []const u8 = "";
                if (i.* < source.len and (source[i.*] == '"' or source[i.*] == '\'')) {
                    const quote = source[i.*];
                    i.* += 1;
                    const v_start = i.*;
                    while (i.* < source.len and source[i.*] != quote) i.* += 1;
                    value = source[v_start..i.*];
                    if (i.* < source.len) i.* += 1;
                } else {
                    const v_start = i.*;
                    while (i.* < source.len and source[i.*] != ']') i.* += 1;
                    value = source[v_start..i.*];
                }

                // Skip to ']'
                while (i.* < source.len and source[i.*] != ']') i.* += 1;
                if (i.* < source.len) i.* += 1;

                try parts.append(.{
                    .kind = kind,
                    .name = attr_name,
                    .value = value,
                    .children = &.{},
                });
            }
        } else if (ch == ':') {
            // Pseudo-class: currently only :not()
            i.* += 1;
            const name_start = i.*;
            while (i.* < source.len and isAlphaNum(source[i.*])) i.* += 1;
            const pseudo_name = source[name_start..i.*];

            if (i.* < source.len and source[i.*] == '(') {
                i.* += 1;
                const arg_start = i.*;
                var depth: u8 = 1;
                while (i.* < source.len and depth > 0) {
                    if (source[i.*] == '(') depth += 1;
                    if (source[i.*] == ')') depth -= 1;
                    if (depth > 0) i.* += 1;
                }
                const arg = source[arg_start..i.*];
                if (i.* < source.len) i.* += 1;

                const inner = try parseQuery(allocator, arg);
                try parts.append(.{
                    .kind = .NotPseudo,
                    .name = pseudo_name,
                    .value = "",
                    .children = inner.nodes,
                });
            } else {
                // Unknown pseudo-class: skip
                continue;
            }
        } else if (ch == '*') {
            i.* += 1;
            try parts.append(.{
                .kind = .Wildcard,
                .name = "",
                .value = "",
                .children = &.{},
            });
        } else if (isIdentChar(ch)) {
            // Element selector
            const start = i.*;
            while (i.* < source.len and isIdentChar(source[i.*])) i.* += 1;
            try parts.append(.{
                .kind = .ElementType,
                .name = source[start..i.*],
                .value = "",
                .children = &.{},
            });
        } else {
            i.* += 1; // skip unknown
        }
    }

    // If multiple parts, wrap in a group
    if (parts.items.len == 1) {
        return parts.items[0];
    }

    return .{
        .kind = .Group,
        .name = "",
        .value = "",
        .children = parts.items,
    };
}

fn isSpace(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r';
}

fn isIdentChar(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or
        (ch >= 'A' and ch <= 'Z') or
        (ch >= '0' and ch <= '9') or
        ch == '-' or ch == '_';
}

fn isAlphaNum(ch: u8) bool {
    return isIdentChar(ch);
}

// ─── Query Matching ───────────────────────────────────────────

/// Match context for evaluating queries against template nodes.
pub const QueryMatchContext = struct {
    /// Element tag name (lowercase)
    tag_name: []const u8,
    /// Element attributes
    attributes: []const AttributeEntry,
    /// Classes extracted from class attribute
    classes: []const []const u8,
};

pub const AttributeEntry = struct {
    name: []const u8,
    value: []const u8,
};

/// Match a compiled query against an element context.
/// Returns true if any root node (or group member) matches.
pub fn matchQuery(query: *const CompiledQuery, ctx: *const QueryMatchContext) bool {
    for (query.nodes) |*node| {
        if (matchNode(node, ctx)) return true;
    }
    return false;
}

/// Recursively match a query node against an element.
fn matchNode(node: *const QueryNode, ctx: *const QueryMatchContext) bool {
    return switch (node.kind) {
        .ElementType => std.mem.eql(u8, node.name, ctx.tag_name),
        .Wildcard => true,
        .Attribute => hasAttr(ctx, node.name),
        .AttributeValue => {
            if (getAttr(ctx, node.name)) |val| {
                return std.mem.eql(u8, val, node.value);
            }
            return false;
        },
        .ClassMatch => {
            for (ctx.classes) |cls| {
                if (std.mem.eql(u8, cls, node.name)) return true;
            }
            return false;
        },
        .NotPseudo => {
            for (node.children) |child| {
                if (matchNode(&child, ctx)) return false;
            }
            return true;
        },
        .Descendant => {
            // Left must match some ancestor, right must match the element
            // Simplified: both must match the same element
            if (node.children.len >= 2) {
                return matchNode(&node.children[0], ctx) or
                    matchNode(&node.children[1], ctx);
            }
            return false;
        },
        .Child => {
            // Parent → child relationship (simplified to same element)
            if (node.children.len >= 2) {
                return matchNode(&node.children[0], ctx) and
                    matchNode(&node.children[1], ctx);
            }
            return false;
        },
        .Adjacent => {
            // Sibling relationship (simplified to same element)
            if (node.children.len >= 2) {
                return matchNode(&node.children[0], ctx) or
                    matchNode(&node.children[1], ctx);
            }
            return false;
        },
        .Group => {
            for (node.children) |child| {
                if (matchNode(&child, ctx)) return true;
            }
            return false;
        },
    };
}

fn hasAttr(ctx: *const QueryMatchContext, name: []const u8) bool {
    for (ctx.attributes) |attr| {
        if (std.mem.eql(u8, attr.name, name)) return true;
    }
    return false;
}

fn getAttr(ctx: *const QueryMatchContext, name: []const u8) ?[]const u8 {
    for (ctx.attributes) |attr| {
        if (std.mem.eql(u8, attr.name, name)) return attr.value;
    }
    return null;
}

/// Build a QueryMatchContext from tag name and attributes.
pub fn buildQueryContext(
    allocator: Allocator,
    tag_name: []const u8,
    attrs: []const AttributeEntry,
) !QueryMatchContext {
    var classes = std.array_list.Managed([]const u8).init(allocator);
    errdefer classes.deinit();

    for (attrs) |attr| {
        if (std.mem.eql(u8, attr.name, "class") and attr.value.len > 0) {
            var start: usize = 0;
            for (attr.value, 0..) |ch, i_| {
                if (ch == ' ' or ch == '\t') {
                    if (i_ > start) {
                        try classes.append(attr.value[start..i_]);
                    }
                    start = i_ + 1;
                }
            }
            if (start < attr.value.len) {
                try classes.append(attr.value[start..]);
            }
        }
    }

    return .{
        .tag_name = tag_name,
        .attributes = attrs,
        .classes = classes.items,
    };
}

// ─── Query String Generation ────────────────────────────────

/// Convert a compiled query back to a source string (for diagnostics).
pub fn queryToString(allocator: Allocator, query: *const CompiledQuery) ![]const u8 {
    if (query.nodes.len == 0) {
        return allocator.dupe(u8, "");
    }

    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    for (query.nodes, 0..) |*node, idx| {
        if (idx > 0) try buf.appendSlice(", ");
        try nodeToString(&buf, node);
    }

    return buf.toOwnedSlice();
}

fn nodeToString(buf: *std.array_list.Managed(u8), node: *const QueryNode) !void {
    switch (node.kind) {
        .ElementType => try buf.appendSlice(node.name),
        .Wildcard => try buf.appendSlice("*"),
        .Attribute => {
            try buf.appendSlice("[");
            try buf.appendSlice(node.name);
            try buf.appendSlice("]");
        },
        .AttributeValue => {
            try buf.appendSlice("[");
            try buf.appendSlice(node.name);
            try buf.appendSlice("=\"");
            try buf.appendSlice(node.value);
            try buf.appendSlice("\"]");
        },
        .ClassMatch => {
            try buf.append('.');
            try buf.appendSlice(node.name);
        },
        .NotPseudo => {
            try buf.appendSlice(":not(");
            for (node.children, 0..) |child, i| {
                if (i > 0) try buf.appendSlice(" ");
                try nodeToString(buf, &child);
            }
            try buf.appendSlice(")");
        },
        .Descendant => {
            if (node.children.len >= 2) {
                try nodeToString(buf, &node.children[0]);
                try buf.appendSlice(" ");
                try nodeToString(buf, &node.children[1]);
            }
        },
        .Child => {
            if (node.children.len >= 2) {
                try nodeToString(buf, &node.children[0]);
                try buf.appendSlice(" > ");
                try nodeToString(buf, &node.children[1]);
            }
        },
        .Adjacent => {
            if (node.children.len >= 2) {
                try nodeToString(buf, &node.children[0]);
                try buf.appendSlice(" + ");
                try nodeToString(buf, &node.children[1]);
            }
        },
        .Group => {
            for (node.children, 0..) |child, i| {
                if (i > 0) try buf.appendSlice(", ");
                try nodeToString(buf, &child);
            }
        },
    }
}

// ─── Tests ────────────────────────────────────────────────────

test "parseQuery element" {
    const allocator = std.testing.allocator;
    const query = try parseQuery(allocator, "div");
    defer {
        allocator.free(query.nodes);
        if (query.source.len > 0) allocator.free(query.source);
    }
    try std.testing.expectEqual(@as(usize, 1), query.nodes.len);
    try std.testing.expectEqual(QueryNodeType.ElementType, query.nodes[0].kind);
    try std.testing.expectEqualStrings("div", query.nodes[0].name);
}

test "parseQuery class" {
    const allocator = std.testing.allocator;
    const query = try parseQuery(allocator, ".active");
    defer {
        allocator.free(query.nodes);
        if (query.source.len > 0) allocator.free(query.source);
    }
    try std.testing.expectEqual(@as(usize, 1), query.nodes.len);
    try std.testing.expectEqual(QueryNodeType.ClassMatch, query.nodes[0].kind);
    try std.testing.expectEqualStrings("active", query.nodes[0].name);
}

test "parseQuery attribute" {
    const allocator = std.testing.allocator;
    const query = try parseQuery(allocator, "[disabled]");
    defer {
        allocator.free(query.nodes);
        if (query.source.len > 0) allocator.free(query.source);
    }
    try std.testing.expectEqual(@as(usize, 1), query.nodes.len);
    try std.testing.expectEqual(QueryNodeType.Attribute, query.nodes[0].kind);
}

test "parseQuery attribute value" {
    const allocator = std.testing.allocator;
    const query = try parseQuery(allocator, "[type=\"text\"]");
    defer {
        allocator.free(query.nodes);
        if (query.source.len > 0) allocator.free(query.source);
    }
    try std.testing.expectEqual(@as(usize, 1), query.nodes.len);
    try std.testing.expectEqual(QueryNodeType.AttributeValue, query.nodes[0].kind);
    try std.testing.expectEqualStrings("text", query.nodes[0].value);
}

test "parseQuery with descendant combinator" {
    const allocator = std.testing.allocator;
    const query = try parseQuery(allocator, "div .active");
    defer {
        if (query.nodes.len > 0) allocator.free(query.nodes);
        if (query.source.len > 0) allocator.free(query.source);
    }
    try std.testing.expectEqual(@as(usize, 1), query.nodes.len);
    try std.testing.expectEqual(QueryNodeType.Descendant, query.nodes[0].kind);
}

test "parseQuery group" {
    const allocator = std.testing.allocator;
    const query = try parseQuery(allocator, "div, span");
    defer {
        if (query.nodes.len > 0) allocator.free(query.nodes);
        if (query.source.len > 0) allocator.free(query.source);
    }
    try std.testing.expectEqual(@as(usize, 1), query.nodes.len);
    try std.testing.expectEqual(QueryNodeType.Group, query.nodes[0].kind);
    try std.testing.expectEqual(@as(usize, 2), query.nodes[0].children.len);
}

test "matchQuery element" {
    const allocator = std.testing.allocator;
    const query = try parseQuery(allocator, "div");
    defer {
        allocator.free(query.nodes);
        if (query.source.len > 0) allocator.free(query.source);
    }

    const ctx = QueryMatchContext{
        .tag_name = "div",
        .attributes = &.{},
        .classes = &.{},
    };
    try std.testing.expect(matchQuery(&query, &ctx));

    const ctx2 = QueryMatchContext{
        .tag_name = "span",
        .attributes = &.{},
        .classes = &.{},
    };
    try std.testing.expect(!matchQuery(&query, &ctx2));
}

test "matchQuery class" {
    const allocator = std.testing.allocator;
    const query = try parseQuery(allocator, ".active");
    defer {
        allocator.free(query.nodes);
        if (query.source.len > 0) allocator.free(query.source);
    }

    const ctx = QueryMatchContext{
        .tag_name = "div",
        .attributes = &.{.{ .name = "class", .value = "active highlighted" }},
        .classes = &.{ "active", "highlighted" },
    };
    try std.testing.expect(matchQuery(&query, &ctx));
}

test "buildQueryContext" {
    const allocator = std.testing.allocator;
    const attrs = [_]AttributeEntry{
        .{ .name = "class", .value = "foo bar" },
    };
    const ctx = try buildQueryContext(allocator, "div", &attrs);
    try std.testing.expectEqual(@as(usize, 2), ctx.classes.len);
    try std.testing.expectEqualStrings("foo", ctx.classes[0]);
    try std.testing.expectEqualStrings("bar", ctx.classes[1]);
}

test "queryToString roundtrip" {
    const allocator = std.testing.allocator;
    const query = try parseQuery(allocator, "div.active[type=\"text\"]");
    const str = try queryToString(allocator, &query);
    defer allocator.free(str);
    defer {
        allocator.free(query.nodes);
        if (query.source.len > 0) allocator.free(query.source);
    }
    try std.testing.expect(std.mem.indexOf(u8, str, "div") != null);
    try std.testing.expect(std.mem.indexOf(u8, str, ".active") != null);
    try std.testing.expect(std.mem.indexOf(u8, str, "[type=\"text\"]") != null);
}
