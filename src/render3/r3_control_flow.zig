/// R3 Control Flow — Parse @if/@for/@switch block syntax
///
/// Port of: compiler/src/render3/render3/.ts (804 LoC)
const std = @import("std");

/// Parse @if block parameters: "@if (condition; as alias)".
pub const IfBlockParams = struct {
    condition: []const u8,
    alias: ?[]const u8 = null,
};

/// Parse @for block parameters: "item of items; track item.id; let i = $index".
pub const ForBlockParams = struct {
    item_name: []const u8,
    iterable: []const u8,
    track_expr: ?[]const u8 = null,
    context_vars: []const ContextVar = &.{},
};

pub const ContextVar = struct {
    name: []const u8,
    value: []const u8,
};

/// Parse @if expression.
pub fn parseIfExpression(expr: []const u8) IfBlockParams {
    var params = IfBlockParams{ .condition = expr };
    // Check for "; as alias"
    if (std.mem.indexOf(u8, expr, "; as")) |pos| {
        params.condition = std.mem.trim(u8, expr[0..pos], " ");
        params.alias = std.mem.trim(u8, expr[pos + 4 ..], " ");
    }
    return params;
}

/// Parse @for microsyntax: "item of items; track item.id".
pub fn parseForExpression(expr: []const u8) ForBlockParams {
    var params = ForBlockParams{ .item_name = "", .iterable = "" };
    var it = std.mem.splitSequence(u8, expr, ";");
    if (it.next()) |part1| {
        const trimmed = std.mem.trim(u8, part1, " ");
        if (std.mem.indexOf(u8, trimmed, " of ")) |of_pos| {
            params.item_name = std.mem.trim(u8, trimmed[0..of_pos], " ");
            params.iterable = std.mem.trim(u8, trimmed[of_pos + 4 ..], " ");
        }
    }
    while (it.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " ");
        if (std.mem.startsWith(u8, trimmed, "track ")) {
            params.track_expr = std.mem.trim(u8, trimmed[6..], " ");
        }
    }
    return params;
}
