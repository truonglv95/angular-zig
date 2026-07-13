/// R3 Deferred Triggers — Parse @defer trigger expressions
///
/// Port of: compiler/src/render3/r3_deferred_triggers.ts (771 LoC)
///
/// Parses the trigger expressions for @defer blocks:
///   `on idle`, `on immediate`, `on timer(500ms)`,
///   `on hover(selector)`, `on interaction(selector)`,
///   `on viewport(selector)`, `on never`, `when condition`
const std = @import("std");

/// Possible types of `on` triggers.
/// Direct port of `OnTriggerType` enum in the TS source.
pub const OnTriggerType = enum {
    Idle,
    Timer,
    Interaction,
    Immediate,
    Hover,
    Viewport,
    Never,
};

/// Get the string representation of an OnTriggerType.
pub fn triggerTypeString(t: OnTriggerType) []const u8 {
    return switch (t) {
        .Idle => "idle",
        .Timer => "timer",
        .Interaction => "interaction",
        .Immediate => "immediate",
        .Hover => "hover",
        .Viewport => "viewport",
        .Never => "never",
    };
}

/// Parse an OnTriggerType from a string.
pub fn parseTriggerType(s: []const u8) ?OnTriggerType {
    if (std.mem.eql(u8, s, "idle")) return .Idle;
    if (std.mem.eql(u8, s, "timer")) return .Timer;
    if (std.mem.eql(u8, s, "interaction")) return .Interaction;
    if (std.mem.eql(u8, s, "immediate")) return .Immediate;
    if (std.mem.eql(u8, s, "hover")) return .Hover;
    if (std.mem.eql(u8, s, "viewport")) return .Viewport;
    if (std.mem.eql(u8, s, "never")) return .Never;
    return null;
}

/// Parsed information about a defer trigger parameter.
/// Direct port of `ParsedParameter` interface in the TS source.
pub const ParsedParameter = struct {
    expression: []const u8,
    start: u32,
};

/// DeferredTriggerInfo — parsed trigger info for a specific trigger type.
pub const DeferredTriggerInfo = struct {
    /// For reference-based triggers: the reference selector.
    /// For timer: the delay (e.g., "500ms").
    /// For idle/immediate/never: null.
    reference: ?[]const u8 = null,
    /// For viewport: optional configuration object.
    options: ?[]const u8 = null,
    /// For timer: the parsed delay in milliseconds.
    delay_ms: ?u64 = null,
    /// Source span of the trigger.
    source_span: ?[]const u8 = null,
};

/// DeferredBlockTriggers — all triggers for a @defer block.
/// Direct port of `DeferredBlockTriggers` interface in the TS source.
pub const DeferredBlockTriggers = struct {
    idle: ?DeferredTriggerInfo = null,
    immediate: ?DeferredTriggerInfo = null,
    timer: ?DeferredTriggerInfo = null,
    hover: ?DeferredTriggerInfo = null,
    interaction: ?DeferredTriggerInfo = null,
    viewport: ?DeferredTriggerInfo = null,
    never: ?DeferredTriggerInfo = null,
    when: ?DeferredTriggerInfo = null,
};

/// Check if a time pattern is valid (e.g., "500ms", "2s", "100").
/// Direct port of `TIME_PATTERN = /^\d+\.?\d*(ms|s)?$/` in the TS source.
pub fn isValidTimePattern(s: []const u8) bool {
    if (s.len == 0) return false;
    var i: usize = 0;
    // Parse digits
    while (i < s.len and (s[i] >= '0' and s[i] <= '9')) : (i += 1) {}
    // Optional decimal point and more digits
    if (i < s.len and s[i] == '.') {
        i += 1;
        while (i < s.len and (s[i] >= '0' and s[i] <= '9')) : (i += 1) {}
    }
    if (i == 0) return false; // No digits
    // Optional unit
    if (i < s.len) {
        if (i + 2 == s.len and std.mem.eql(u8, s[i..], "ms")) {
            return true;
        }
        if (i + 1 == s.len and (s[i] == 's')) {
            return true;
        }
        return false;
    }
    return true;
}

/// Parse a time value string into milliseconds.
/// Handles "500ms", "2s", "100" (defaults to ms).
pub fn parseTimeValue(s: []const u8) ?u64 {
    if (!isValidTimePattern(s)) return null;
    var i: usize = 0;
    var value: f64 = 0;
    while (i < s.len and (s[i] >= '0' and s[i] <= '9')) : (i += 1) {
        value = value * 10 + @as(f64, @floatFromInt(s[i] - '0'));
    }
    // Optional decimal
    if (i < s.len and s[i] == '.') {
        i += 1;
        var decimal: f64 = 0;
        var divisor: f64 = 10;
        while (i < s.len and (s[i] >= '0' and s[i] <= '9')) : (i += 1) {
            decimal += @as(f64, @floatFromInt(s[i] - '0')) / divisor;
            divisor *= 10;
        }
        value += decimal;
    }
    // Unit
    if (i < s.len) {
        if (i + 2 == s.len and std.mem.eql(u8, s[i..], "ms")) {
            return @intFromFloat(value);
        }
        if (i + 1 == s.len and s[i] == 's') {
            return @intFromFloat(value * 1000);
        }
    }
    return @intFromFloat(value);
}

/// Parse trigger parameters from a parenthesized expression.
/// E.g., "hover(nav)" → ["nav"], "viewport(nav; {root: true})" → ["nav", "{root: true}"]
pub fn parseTriggerParameters(allocator: std.mem.Allocator, expr: []const u8) ![]const ParsedParameter {
    var params = std.array_list.Managed(ParsedParameter).init(allocator);
    errdefer params.deinit();

    // Remove outer parentheses if present
    var s = std.mem.trim(u8, expr, " \t\n\r");
    if (s.len > 0 and s[0] == '(' and s[s.len - 1] == ')') {
        s = s[1 .. s.len - 1];
    }

    // Split by semicolons (respecting nested braces/brackets)
    var depth: i32 = 0;
    var start: u32 = 0;
    for (s, 0..) |ch, i| {
        switch (ch) {
            '(', '[', '{' => depth += 1,
            ')', ']', '}' => depth -= 1,
            ';' => {
                if (depth == 0) {
                    const param_expr = std.mem.trim(u8, s[start..i], " \t\n\r");
                    if (param_expr.len > 0) {
                        try params.append(.{ .expression = param_expr, .start = start });
                    }
                    start = @intCast(i + 1);
                }
            },
            else => {},
        }
    }
    // Last parameter
    if (start < s.len) {
        const param_expr = std.mem.trim(u8, s[start..], " \t\n\r");
        if (param_expr.len > 0) {
            try params.append(.{ .expression = param_expr, .start = start });
        }
    }

    return params.toOwnedSlice();
}

/// Parse an `on idle` trigger.
pub fn parseIdleTrigger() DeferredTriggerInfo {
    return .{};
}

/// Parse an `on immediate` trigger.
pub fn parseImmediateTrigger() DeferredTriggerInfo {
    return .{};
}

/// Parse an `on never` trigger.
pub fn parseNeverTrigger() DeferredTriggerInfo {
    return .{};
}

/// Parse an `on timer(500ms)` trigger.
pub fn parseTimerTrigger(delay: []const u8) DeferredTriggerInfo {
    return .{
        .delay_ms = parseTimeValue(delay),
    };
}

/// Parse an `on hover(selector)` trigger.
pub fn parseHoverTrigger(reference: []const u8) DeferredTriggerInfo {
    return .{ .reference = reference };
}

/// Parse an `on interaction(selector)` trigger.
pub fn parseInteractionTrigger(reference: []const u8) DeferredTriggerInfo {
    return .{ .reference = reference };
}

/// Parse an `on viewport(selector)` trigger.
pub fn parseViewportTrigger(reference: []const u8, options: ?[]const u8) DeferredTriggerInfo {
    return .{ .reference = reference, .options = options };
}

/// Parse a `when condition` trigger.
pub fn parseWhenTrigger(condition: []const u8) DeferredTriggerInfo {
    return .{ .reference = condition };
}

// ─── Tests ──────────────────────────────────────────────────

test "triggerTypeString" {
    try std.testing.expectEqualStrings("idle", triggerTypeString(.Idle));
    try std.testing.expectEqualStrings("timer", triggerTypeString(.Timer));
    try std.testing.expectEqualStrings("hover", triggerTypeString(.Hover));
}

test "parseTriggerType" {
    try std.testing.expectEqual(OnTriggerType.Idle, parseTriggerType("idle").?);
    try std.testing.expectEqual(OnTriggerType.Timer, parseTriggerType("timer").?);
    try std.testing.expect(parseTriggerType("unknown") == null);
}

test "isValidTimePattern" {
    try std.testing.expect(isValidTimePattern("500ms"));
    try std.testing.expect(isValidTimePattern("2s"));
    try std.testing.expect(isValidTimePattern("100"));
    try std.testing.expect(isValidTimePattern("1.5s"));
    try std.testing.expect(!isValidTimePattern("abc"));
    try std.testing.expect(!isValidTimePattern(""));
}

test "parseTimeValue" {
    try std.testing.expectEqual(@as(u64, 500), parseTimeValue("500ms").?);
    try std.testing.expectEqual(@as(u64, 2000), parseTimeValue("2s").?);
    try std.testing.expectEqual(@as(u64, 100), parseTimeValue("100").?);
    try std.testing.expectEqual(@as(u64, 1500), parseTimeValue("1.5s").?);
}

test "parseTriggerParameters single" {
    const allocator = std.testing.allocator;
    const params = try parseTriggerParameters(allocator, "nav");
    defer allocator.free(params);
    try std.testing.expectEqual(@as(usize, 1), params.len);
    try std.testing.expectEqualStrings("nav", params[0].expression);
}

test "parseTriggerParameters multiple" {
    const allocator = std.testing.allocator;
    const params = try parseTriggerParameters(allocator, "nav; extra");
    defer allocator.free(params);
    try std.testing.expectEqual(@as(usize, 2), params.len);
}

test "parseTriggerParameters with parens" {
    const allocator = std.testing.allocator;
    const params = try parseTriggerParameters(allocator, "(nav)");
    defer allocator.free(params);
    try std.testing.expectEqual(@as(usize, 1), params.len);
    try std.testing.expectEqualStrings("nav", params[0].expression);
}

test "parseTimerTrigger" {
    const info = parseTimerTrigger("500ms");
    try std.testing.expectEqual(@as(u64, 500), info.delay_ms.?);
}

test "parseViewportTrigger with options" {
    const info = parseViewportTrigger("nav", "{root: true}");
    try std.testing.expectEqualStrings("nav", info.reference.?);
    try std.testing.expectEqualStrings("{root: true}", info.options.?);
}
