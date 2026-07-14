/// R3 Deferred Blocks — Parse @defer block syntax
///
/// Port of: compiler/src/render3/r3_deferred_blocks.ts (308 LoC)
///
/// Creates deferred blocks from HTML AST nodes. Handles @defer, @placeholder,
/// @loading, and @error sub-blocks, as well as trigger and prefetch parsing.
const std = @import("std");

/// Check if a string starts with `prefetch when `.
/// Direct port of `PREFETCH_WHEN_PATTERN = /^prefetch\s+when\s/` in the TS source.
pub fn isPrefetchWhenTrigger(s: []const u8) bool {
    return std.mem.startsWith(u8, s, "prefetch when ");
}

/// Check if a string starts with `prefetch on `.
/// Direct port of `PREFETCH_ON_PATTERN = /^prefetch\s+on\s/` in the TS source.
pub fn isPrefetchOnTrigger(s: []const u8) bool {
    return std.mem.startsWith(u8, s, "prefetch on ");
}

/// Check if a string starts with `hydrate when `.
/// Direct port of `HYDRATE_WHEN_PATTERN = /^hydrate\s+when\s/` in the TS source.
pub fn isHydrateWhenTrigger(s: []const u8) bool {
    return std.mem.startsWith(u8, s, "hydrate when ");
}

/// Check if a string starts with `hydrate on `.
/// Direct port of `HYDRATE_ON_PATTERN = /^hydrate\s+on\s/` in the TS source.
pub fn isHydrateOnTrigger(s: []const u8) bool {
    return std.mem.startsWith(u8, s, "hydrate on ");
}

/// Check if a string is `hydrate never`.
/// Direct port of `HYDRATE_NEVER_PATTERN = /^hydrate\s+never(\s*)$/` in the TS source.
pub fn isHydrateNeverTrigger(s: []const u8) bool {
    const trimmed = std.mem.trim(u8, s, " \t");
    return std.mem.eql(u8, trimmed, "hydrate never");
}

/// Check if a parameter starts with `minimum `.
/// Direct port of `MINIMUM_PARAMETER_PATTERN = /^minimum\s/` in the TS source.
pub fn isMinimumParameter(s: []const u8) bool {
    return std.mem.startsWith(u8, s, "minimum ");
}

/// Check if a parameter starts with `after `.
/// Direct port of `AFTER_PARAMETER_PATTERN = /^after\s/` in the TS source.
pub fn isAfterParameter(s: []const u8) bool {
    return std.mem.startsWith(u8, s, "after ");
}

/// Check if a parameter starts with `when `.
/// Direct port of `WHEN_PARAMETER_PATTERN = /^when\s/` in the TS source.
pub fn isWhenParameter(s: []const u8) bool {
    return std.mem.startsWith(u8, s, "when ");
}

/// Check if a parameter starts with `on `.
/// Direct port of `ON_PARAMETER_PATTERN = /^on\s/` in the TS source.
pub fn isOnParameter(s: []const u8) bool {
    return std.mem.startsWith(u8, s, "on ");
}

/// Predicate function that determines if a block with a specific name can
/// be connected to a `defer` block.
/// Direct port of `isConnectedDeferLoopBlock(name)` in the TS source.
pub fn isConnectedDeferLoopBlock(name: []const u8) bool {
    return std.mem.eql(u8, name, "placeholder") or
        std.mem.eql(u8, name, "loading") or
        std.mem.eql(u8, name, "error");
}

/// DeferredSubBlockType — the type of a @defer sub-block.
pub const DeferredSubBlockType = enum(u8) {
    Placeholder,
    Loading,
    Error,
};

/// Parse a sub-block name into a DeferredSubBlockType.
pub fn parseSubBlockType(name: []const u8) ?DeferredSubBlockType {
    if (std.mem.eql(u8, name, "placeholder")) return .Placeholder;
    if (std.mem.eql(u8, name, "loading")) return .Loading;
    if (std.mem.eql(u8, name, "error")) return .Error;
    return null;
}

/// DeferredSubBlockConfig — configuration for a @defer sub-block.
/// Direct port of the sub-block config in the TS source.
pub const DeferredSubBlockConfig = struct {
    type: DeferredSubBlockType,
    /// For @loading: minimum time to show the loading block.
    minimum_time: ?u64 = null,
    /// For @loading: time after which to show the loading block.
    after_time: ?u64 = null,
};

/// Parse a @loading block's parameters: "minimum 500ms; after 1s".
/// Direct port of the loading block parameter parsing in the TS source.
pub fn parseLoadingParams(params: []const u8) DeferredSubBlockConfig {
    var config = DeferredSubBlockConfig{ .type = .Loading };
    var it = std.mem.splitSequence(u8, params, ";");
    while (it.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t\n\r");
        if (isMinimumParameter(trimmed)) {
            const value = std.mem.trim(u8, trimmed[8..], " \t\n\r");
            config.minimum_time = parseTimeValue(value);
        } else if (isAfterParameter(trimmed)) {
            const value = std.mem.trim(u8, trimmed[6..], " \t\n\r");
            config.after_time = parseTimeValue(value);
        }
    }
    return config;
}

/// Parse a @placeholder block's parameters: "minimum 500ms".
pub fn parsePlaceholderParams(params: []const u8) DeferredSubBlockConfig {
    var config = DeferredSubBlockConfig{ .type = .Placeholder };
    var it = std.mem.splitSequence(u8, params, ";");
    while (it.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t\n\r");
        if (isMinimumParameter(trimmed)) {
            const value = std.mem.trim(u8, trimmed[8..], " \t\n\r");
            config.minimum_time = parseTimeValue(value);
        }
    }
    return config;
}

/// Parse a time value string (e.g., "500ms", "2s") into milliseconds.
fn parseTimeValue(s: []const u8) ?u64 {
    if (s.len == 0) return null;
    var i: usize = 0;
    var value: f64 = 0;
    while (i < s.len and (s[i] >= '0' and s[i] <= '9')) : (i += 1) {
        value = value * 10 + @as(f64, @floatFromInt(s[i] - '0'));
    }
    if (i == 0) return null;
    if (i + 2 == s.len and std.mem.eql(u8, s[i..], "ms")) {
        return @intFromFloat(value);
    }
    if (i + 1 == s.len and s[i] == 's') {
        return @intFromFloat(value * 1000);
    }
    return @intFromFloat(value);
}

// ─── Tests ──────────────────────────────────────────────────

test "isConnectedDeferLoopBlock" {
    try std.testing.expect(isConnectedDeferLoopBlock("placeholder"));
    try std.testing.expect(isConnectedDeferLoopBlock("loading"));
    try std.testing.expect(isConnectedDeferLoopBlock("error"));
    try std.testing.expect(!isConnectedDeferLoopBlock("defer"));
    try std.testing.expect(!isConnectedDeferLoopBlock("else"));
}

test "isPrefetchWhenTrigger" {
    try std.testing.expect(isPrefetchWhenTrigger("prefetch when condition"));
    try std.testing.expect(!isPrefetchWhenTrigger("prefetch on idle"));
}

test "isPrefetchOnTrigger" {
    try std.testing.expect(isPrefetchOnTrigger("prefetch on idle"));
    try std.testing.expect(!isPrefetchOnTrigger("prefetch when condition"));
}

test "isHydrateNeverTrigger" {
    try std.testing.expect(isHydrateNeverTrigger("hydrate never"));
    try std.testing.expect(isHydrateNeverTrigger("hydrate never "));
    try std.testing.expect(!isHydrateNeverTrigger("hydrate when condition"));
}

test "isMinimumParameter" {
    try std.testing.expect(isMinimumParameter("minimum 500ms"));
    try std.testing.expect(!isMinimumParameter("after 1s"));
}

test "isAfterParameter" {
    try std.testing.expect(isAfterParameter("after 1s"));
    try std.testing.expect(!isAfterParameter("minimum 500ms"));
}

test "parseSubBlockType" {
    try std.testing.expectEqual(DeferredSubBlockType.Placeholder, parseSubBlockType("placeholder").?);
    try std.testing.expectEqual(DeferredSubBlockType.Loading, parseSubBlockType("loading").?);
    try std.testing.expectEqual(DeferredSubBlockType.Error, parseSubBlockType("error").?);
    try std.testing.expect(parseSubBlockType("unknown") == null);
}

test "parseLoadingParams" {
    const config = parseLoadingParams("minimum 500ms; after 1s");
    try std.testing.expectEqual(@as(u64, 500), config.minimum_time.?);
    try std.testing.expectEqual(@as(u64, 1000), config.after_time.?);
}

test "parsePlaceholderParams" {
    const config = parsePlaceholderParams("minimum 200ms");
    try std.testing.expectEqual(@as(u64, 200), config.minimum_time.?);
    try std.testing.expect(config.after_time == null);
}
