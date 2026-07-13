/// R3 Deferred Triggers — Parse @defer trigger expressions
///
/// Port of: compiler/src/render3/render3/.ts (771 LoC)
const std = @import("std");

/// DeferTriggerKind — kinds of @defer triggers.
pub const DeferTriggerKind = enum(u8) {
    Idle, Timer, Viewport, Interaction, Hover, Never, When,
};

/// ParsedDeferTrigger — a single parsed @defer trigger.
pub const ParsedDeferTrigger = struct {
    kind: DeferTriggerKind,
    parameter: ?[]const u8 = null,
};

/// Parse "on viewport" trigger.
pub fn parseOnTrigger(expr: []const u8) ?ParsedDeferTrigger {
    const trimmed = std.mem.trim(u8, expr, " ");
    if (std.mem.eql(u8, trimmed, "viewport")) return .{ .kind = .Viewport };
    if (std.mem.eql(u8, trimmed, "idle")) return .{ .kind = .Idle };
    if (std.mem.eql(u8, trimmed, "interaction")) return .{ .kind = .Interaction };
    if (std.mem.eql(u8, trimmed, "hover")) return .{ .kind = .Hover };
    if (std.mem.startsWith(u8, trimmed, "timer(")) return .{ .kind = .Timer, .parameter = trimmed[6..trimmed.len-1] };
    if (std.mem.eql(u8, trimmed, "never")) return .{ .kind = .Never };
    return null;
}

/// Parse "when condition" trigger.
pub fn parseWhenTrigger(expr: []const u8) ParsedDeferTrigger {
    return .{ .kind = .When, .parameter = expr };
}

/// Parse "never" trigger.
pub fn parseNeverTrigger() ParsedDeferTrigger {
    return .{ .kind = .Never };
}
