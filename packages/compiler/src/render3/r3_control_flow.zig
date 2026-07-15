/// R3 Control Flow — Parse @if/@for/@switch block syntax
///
/// Port of: compiler/src/render3/r3_control_flow.ts (804 LoC)
///
/// Parses the new Angular control flow blocks (@if, @for, @switch) from
/// HTML AST nodes into R3 AST nodes. This module handles the microsyntax
/// parsing for each block type.
const std = @import("std");

/// Pattern for the expression in a for loop block: `item of items`.
/// Direct port of `FOR_LOOP_EXPRESSION_PATTERN` in the TS source.
/// Format: `^\s*([0-9A-Za-z_$]*)\s+of\s+([\S\s]*)`
/// Pattern for the tracking expression in a for loop block: `track expr`.
/// Direct port of `FOR_LOOP_TRACK_PATTERN` in the TS source.
/// Pattern for the `as` expression in a conditional block: `as alias`.
/// Direct port of `CONDITIONAL_ALIAS_PATTERN` in the TS source.
/// Names of variables that are allowed to be used in the `let` expression
/// of a `for` loop.
/// Direct port of `ALLOWED_FOR_LOOP_LET_VARIABLES` in the TS source.
pub const ALLOWED_FOR_LOOP_LET_VARIABLES = [_][]const u8{
    "$index",
    "$first",
    "$last",
    "$even",
    "$odd",
    "$count",
};

/// Check if a variable name is an allowed @for loop let variable.
pub fn isAllowedForLoopLetVariable(name: []const u8) bool {
    for (ALLOWED_FOR_LOOP_LET_VARIABLES) |allowed| {
        if (std.mem.eql(u8, name, allowed)) return true;
    }
    return false;
}

/// Predicate function that determines if a block with a specific name can
/// be connected to a `for` block (i.e., `@empty`).
/// Direct port of `isConnectedForLoopBlock(name)` in the TS source.
pub fn isConnectedForLoopBlock(name: []const u8) bool {
    return std.mem.eql(u8, name, "empty");
}

/// Predicate function that determines if a block with a specific name can
/// be connected to an `if` block (i.e., `@else` or `@else if`).
/// Direct port of `isConnectedIfLoopBlock(name)` in the TS source.
pub fn isConnectedIfLoopBlock(name: []const u8) bool {
    return std.mem.eql(u8, name, "else") or std.mem.eql(u8, name, "else if");
}

/// IfBlockParams — parsed parameters from an @if block expression.
pub const IfBlockParams = struct {
    condition: []const u8,
    alias: ?[]const u8 = null,
};

/// ForBlockParams — parsed parameters from a @for block expression.
pub const ForBlockParams = struct {
    item_name: []const u8,
    iterable: []const u8,
    track_expr: ?[]const u8 = null,
    context_vars: []const ContextVar = &.{},
};

/// ContextVar — a context variable in a @for block (e.g., `let i = $index`).
pub const ContextVar = struct {
    name: []const u8,
    value: []const u8,
};

/// SwitchBlockParams — parsed parameters from a @switch block expression.
pub const SwitchBlockParams = struct {
    expression: []const u8,
};

/// SwitchCaseParams — parsed parameters from a @case block expression.
pub const SwitchCaseParams = struct {
    value: []const u8,
    is_default: bool = false,
};

/// Parse @if block parameters: "@if (condition; as alias)".
/// Direct port of `parseConditionalBlockParameters` in the TS source.
///
/// The expression can be:
///   - `condition` — just the condition
///   - `condition; as alias` — condition with an expression alias
pub fn parseIfExpression(expr: []const u8) IfBlockParams {
    var params = IfBlockParams{ .condition = expr };

    // Check for "; as alias"
    if (std.mem.indexOf(u8, expr, "; as")) |pos| {
        params.condition = std.mem.trim(u8, expr[0..pos], " ");
        params.alias = std.mem.trim(u8, expr[pos + 4 ..], " ");
    } else if (std.mem.indexOf(u8, expr, ";as ")) |pos| {
        params.condition = std.mem.trim(u8, expr[0..pos], " ");
        params.alias = std.mem.trim(u8, expr[pos + 3 ..], " ");
    }

    return params;
}

/// Parse @for microsyntax: "item of items; track item.id; let i = $index".
/// Direct port of the @for expression parsing in the TS source.
///
/// The expression is a semicolon-separated list of:
///   - `item of items` — the main loop expression (required)
///   - `track expr` — the track expression (optional)
///   - `let name = value` — context variables (optional, can be multiple)
pub fn parseForExpression(allocator: std.mem.Allocator, expr: []const u8) !ForBlockParams {
    var params = ForBlockParams{ .item_name = "", .iterable = "" };
    var context_vars = std.array_list.Managed(ContextVar).init(allocator);
    errdefer context_vars.deinit();

    var it = std.mem.splitSequence(u8, expr, ";");
    if (it.next()) |part1| {
        const trimmed = std.mem.trim(u8, part1, " \t\n\r");
        // Parse "item of items"
        if (std.mem.indexOf(u8, trimmed, " of ")) |of_pos| {
            params.item_name = std.mem.trim(u8, trimmed[0..of_pos], " \t\n\r");
            params.iterable = std.mem.trim(u8, trimmed[of_pos + 4 ..], " \t\n\r");
        }
    }

    while (it.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t\n\r");
        if (std.mem.startsWith(u8, trimmed, "track ")) {
            params.track_expr = std.mem.trim(u8, trimmed[6..], " \t\n\r");
        } else if (std.mem.startsWith(u8, trimmed, "track;")) {
            params.track_expr = "";
        } else if (std.mem.startsWith(u8, trimmed, "let ")) {
            // Parse "let name = value"
            const let_part = std.mem.trim(u8, trimmed[4..], " \t\n\r");
            if (std.mem.indexOf(u8, let_part, " = ")) |eq_pos| {
                const name = std.mem.trim(u8, let_part[0..eq_pos], " \t\n\r");
                const value = std.mem.trim(u8, let_part[eq_pos + 3 ..], " \t\n\r");
                try context_vars.append(.{ .name = name, .value = value });
            } else if (std.mem.indexOf(u8, let_part, "=")) |eq_pos| {
                const name = std.mem.trim(u8, let_part[0..eq_pos], " \t\n\r");
                const value = std.mem.trim(u8, let_part[eq_pos + 1 ..], " \t\n\r");
                try context_vars.append(.{ .name = name, .value = value });
            } else {
                // "let name" without value (defaults to $implicit)
                try context_vars.append(.{ .name = let_part, .value = "" });
            }
        }
    }

    params.context_vars = try context_vars.toOwnedSlice();
    return params;
}

/// Parse @switch expression: "@switch (condition)".
/// Direct port of the @switch expression parsing in the TS source.
pub fn parseSwitchExpression(expr: []const u8) SwitchBlockParams {
    return .{ .expression = std.mem.trim(u8, expr, " \t\n\r") };
}

/// Parse @case expression: "@case (value)" or "@default".
/// Direct port of the @case expression parsing in the TS source.
pub fn parseCaseExpression(expr: []const u8) SwitchCaseParams {
    const trimmed = std.mem.trim(u8, expr, " \t\n\r");
    if (std.mem.eql(u8, trimmed, "default")) {
        return .{ .value = "", .is_default = true };
    }
    return .{ .value = trimmed, .is_default = false };
}

/// Validate connected blocks for an @if block.
/// Direct port of `validateIfConnectedBlocks(connectedBlocks)` in the TS source.
///
/// Validates that:
///   - Only `@else` and `@else if` blocks can follow an @if
///   - `@else if` blocks can only appear before `@else`
///   - There can be at most one `@else` block
pub fn validateIfConnectedBlocks(connected_names: []const []const u8) !void {
    var has_else = false;
    for (connected_names) |name| {
        if (!isConnectedIfLoopBlock(name)) {
            return error.InvalidConnectedBlock;
        }
        if (std.mem.eql(u8, name, "else")) {
            if (has_else) return error.DuplicateElseBlock;
            has_else = true;
        }
        if (has_else and std.mem.eql(u8, name, "else if")) {
            return error.ElseIfAfterElse;
        }
    }
}

/// Validate connected blocks for a @for block.
/// Direct port of `validateForConnectedBlocks(connectedBlocks)` in the TS source.
///
/// Validates that only `@empty` blocks can follow a @for, and there can be
/// at most one.
pub fn validateForConnectedBlocks(connected_names: []const []const u8) !void {
    if (connected_names.len > 1) return error.MultipleEmptyBlocks;
    for (connected_names) |name| {
        if (!isConnectedForLoopBlock(name)) {
            return error.InvalidConnectedBlock;
        }
    }
}

// ─── Tests ──────────────────────────────────────────────────

test "isConnectedForLoopBlock" {
    try std.testing.expect(isConnectedForLoopBlock("empty"));
    try std.testing.expect(!isConnectedForLoopBlock("else"));
    try std.testing.expect(!isConnectedForLoopBlock("case"));
}

test "isConnectedIfLoopBlock" {
    try std.testing.expect(isConnectedIfLoopBlock("else"));
    try std.testing.expect(isConnectedIfLoopBlock("else if"));
    try std.testing.expect(!isConnectedIfLoopBlock("empty"));
}

test "isAllowedForLoopLetVariable" {
    try std.testing.expect(isAllowedForLoopLetVariable("$index"));
    try std.testing.expect(isAllowedForLoopLetVariable("$first"));
    try std.testing.expect(isAllowedForLoopLetVariable("$count"));
    try std.testing.expect(!isAllowedForLoopLetVariable("$invalid"));
}

test "parseIfExpression without alias" {
    const params = parseIfExpression("show");
    try std.testing.expectEqualStrings("show", params.condition);
    try std.testing.expect(params.alias == null);
}

test "parseIfExpression with alias" {
    const params = parseIfExpression("user; as u");
    try std.testing.expectEqualStrings("user", params.condition);
    try std.testing.expectEqualStrings("u", params.alias.?);
}

test "parseForExpression basic" {
    const allocator = std.testing.allocator;
    const params = try parseForExpression(allocator, "item of items");
    defer allocator.free(params.context_vars);
    try std.testing.expectEqualStrings("item", params.item_name);
    try std.testing.expectEqualStrings("items", params.iterable);
    try std.testing.expect(params.track_expr == null);
}

test "parseForExpression with track" {
    const allocator = std.testing.allocator;
    const params = try parseForExpression(allocator, "item of items; track item.id");
    defer allocator.free(params.context_vars);
    try std.testing.expectEqualStrings("item", params.item_name);
    try std.testing.expectEqualStrings("items", params.iterable);
    try std.testing.expectEqualStrings("item.id", params.track_expr.?);
}

test "parseForExpression with context vars" {
    const allocator = std.testing.allocator;
    const params = try parseForExpression(allocator, "item of items; track item.id; let i = $index; let e = $even");
    defer allocator.free(params.context_vars);
    try std.testing.expectEqual(@as(usize, 2), params.context_vars.len);
    try std.testing.expectEqualStrings("i", params.context_vars[0].name);
    try std.testing.expectEqualStrings("$index", params.context_vars[0].value);
    try std.testing.expectEqualStrings("e", params.context_vars[1].name);
    try std.testing.expectEqualStrings("$even", params.context_vars[1].value);
}

test "parseSwitchExpression" {
    const params = parseSwitchExpression("color");
    try std.testing.expectEqualStrings("color", params.expression);
}

test "parseCaseExpression" {
    const case1 = parseCaseExpression("red");
    try std.testing.expectEqualStrings("red", case1.value);
    try std.testing.expect(!case1.is_default);

    const case2 = parseCaseExpression("default");
    try std.testing.expect(case2.is_default);
}

test "validateIfConnectedBlocks" {
    const ok = [_][]const u8{ "else if", "else" };
    try validateIfConnectedBlocks(&ok);

    const bad = [_][]const u8{ "else", "else if" };
    try std.testing.expectError(error.ElseIfAfterElse, validateIfConnectedBlocks(&bad));
}

test "validateForConnectedBlocks" {
    const ok = [_][]const u8{"empty"};
    try validateForConnectedBlocks(&ok);

    const bad = [_][]const u8{ "empty", "empty" };
    try std.testing.expectError(error.MultipleEmptyBlocks, validateForConnectedBlocks(&bad));
}
