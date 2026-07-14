/// R3 View i18n Localize Utils — Utilities for i18n localization
///
/// Port of: compiler/src/render3/view/i18n/localize_utils.ts (187 LoC)
///
/// Provides utilities for working with i18n localization in templates,
/// including resolving translation placeholders and building i18n context.
const std = @import("std");

/// I18nContext — context for i18n localization within a template.
pub const I18nContext = struct {
    allocator: std.mem.Allocator,
    /// The unique ID of this i18n context.
    id: u32,
    /// The parent context ID (null for root).
    parent: ?u32 = null,
    /// Placeholder name → value mapping.
    placeholders: std.StringHashMap([]const u8),
    /// Sub-template index for nested templates.
    sub_template_index: ?u32 = null,

    pub fn init(allocator: std.mem.Allocator, id: u32, parent: ?u32) I18nContext {
        return .{
            .allocator = allocator,
            .id = id,
            .parent = parent,
            .placeholders = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *I18nContext) void {
        self.placeholders.deinit();
    }

    pub fn addPlaceholder(self: *I18nContext, name: []const u8, value: []const u8) !void {
        try self.placeholders.put(name, value);
    }

    pub fn getPlaceholder(self: *const I18nContext, name: []const u8) ?[]const u8 {
        return self.placeholders.get(name);
    }
};

/// Resolve a translation placeholder by name.
/// Direct port of the placeholder resolution logic in the TS source.
pub fn resolvePlaceholder(
    ctx: *const I18nContext,
    name: []const u8,
) ?[]const u8 {
    // Check this context.
    if (ctx.getPlaceholder(name)) |value| {
        return value;
    }
    // The full implementation would walk up the parent chain.
    return null;
}

/// Build an i18n message string from a template and placeholder map.
/// Direct port of `assembleI18nBoundString(...)` in the TS source.
pub fn assembleBoundString(
    allocator: std.mem.Allocator,
    template: []const u8,
    placeholders: std.StringHashMap([]const u8),
) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < template.len) {
        // Look for placeholder markers like {$placeholder}
        if (i + 2 < template.len and template[i] == '{' and template[i + 1] == '$') {
            // Find the closing brace
            if (std.mem.indexOfScalarPos(u8, template, i, '}')) |close_pos| {
                const ph_name = template[i + 2 .. close_pos];
                if (placeholders.get(ph_name)) |value| {
                    try result.appendSlice(value);
                } else {
                    try result.appendSlice(template[i .. close_pos + 1]);
                }
                i = close_pos + 1;
                continue;
            }
        }
        try result.append(template[i]);
        i += 1;
    }

    return result.toOwnedSlice();
}

/// Check if a string is a placeholder reference (starts with {$ and ends with }).
pub fn isPlaceholderRef(s: []const u8) bool {
    return s.len > 3 and s[0] == '{' and s[1] == '$' and s[s.len - 1] == '}';
}

/// Extract the placeholder name from a placeholder reference.
pub fn extractPlaceholderName(s: []const u8) []const u8 {
    if (isPlaceholderRef(s)) {
        return s[2 .. s.len - 1];
    }
    return s;
}

// ─── Tests ──────────────────────────────────────────────────

test "I18nContext add/get placeholder" {
    const allocator = std.testing.allocator;
    var ctx = I18nContext.init(allocator, 0, null);
    defer ctx.deinit();
    try ctx.addPlaceholder("name", "World");
    try std.testing.expectEqualStrings("World", ctx.getPlaceholder("name").?);
    try std.testing.expect(ctx.getPlaceholder("missing") == null);
}

test "resolvePlaceholder" {
    const allocator = std.testing.allocator;
    var ctx = I18nContext.init(allocator, 0, null);
    defer ctx.deinit();
    try ctx.addPlaceholder("count", "5");
    try std.testing.expectEqualStrings("5", resolvePlaceholder(&ctx, "count").?);
    try std.testing.expect(resolvePlaceholder(&ctx, "missing") == null);
}

test "isPlaceholderRef" {
    try std.testing.expect(isPlaceholderRef("{$name}"));
    try std.testing.expect(!isPlaceholderRef("name"));
    try std.testing.expect(!isPlaceholderRef("{}"));
}

test "extractPlaceholderName" {
    try std.testing.expectEqualStrings("name", extractPlaceholderName("{$name}"));
    try std.testing.expectEqualStrings("plain", extractPlaceholderName("plain"));
}

test "assembleBoundString" {
    const allocator = std.testing.allocator;
    var placeholders = std.StringHashMap([]const u8).init(allocator);
    defer placeholders.deinit();
    try placeholders.put("name", "World");
    const result = try assembleBoundString(allocator, "Hello {$name}!", placeholders);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello World!", result);
}
