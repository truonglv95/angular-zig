/// i18n Placeholder — Maps HTML tag names to XLIFF placeholder names
///
/// Port of: compiler/src/i18n/serializers/placeholder.ts
const std = @import("std");

/// Map of HTML tag names to XLIFF placeholder names.
/// E.g. <b> → BOLD_TEXT, <br> → LINE_BREAK
pub const TAG_PLACEHOLDER_MAP = std.StaticStringMap([]const u8).initComptime(.{
    .{ "b", "BOLD_TEXT" },
    .{ "br", "LINE_BREAK" },
    .{ "i", "ITALIC_TEXT" },
    .{ "h1", "HEADING_1" },
    .{ "h2", "HEADING_2" },
    .{ "h3", "HEADING_3" },
    .{ "h4", "HEADING_4" },
    .{ "h5", "HEADING_5" },
    .{ "h6", "HEADING_6" },
    .{ "a", "LINK" },
    .{ "p", "PARAGRAPH" },
    .{ "strong", "STRONG_TEXT" },
    .{ "em", "EMPHASIZED_TEXT" },
    .{ "code", "CODE" },
    .{ "pre", "PRE_FORMATTED" },
    .{ "img", "IMAGE" },
    .{ "ul", "UNORDERED_LIST" },
    .{ "ol", "ORDERED_LIST" },
    .{ "li", "LIST_ITEM" },
    .{ "table", "TABLE" },
    .{ "tr", "TABLE_ROW" },
    .{ "td", "TABLE_CELL" },
    .{ "th", "TABLE_HEADER" },
    .{ "thead", "TABLE_HEAD" },
    .{ "tbody", "TABLE_BODY" },
    .{ "tfoot", "TABLE_FOOT" },
    .{ "span", "SPAN" },
    .{ "div", "DIV" },
    .{ "blockquote", "BLOCKQUOTE" },
    .{ "hr", "HORIZONTAL_RULE" },
    .{ "label", "LABEL" },
    .{ "input", "INPUT" },
    .{ "button", "BUTTON" },
    .{ "select", "SELECT" },
    .{ "option", "OPTION" },
    .{ "textarea", "TEXTAREA" },
    .{ "form", "FORM" },
    .{ "fieldset", "FIELDSET" },
    .{ "legend", "LEGEND" },
    .{ "datalist", "DATALIST" },
    .{ "output", "OUTPUT" },
    .{ "progress", "PROGRESS" },
    .{ "meter", "METER" },
    .{ "details", "DETAILS" },
    .{ "summary", "SUMMARY" },
    .{ "dialog", "DIALOG" },
    .{ "canvas", "CANVAS" },
    .{ "svg", "SVG" },
    .{ "math", "MATH" },
});

/// Get the XLIFF placeholder name for an HTML tag.
/// Returns null if the tag doesn't have a specific placeholder.
pub fn getPlaceholderName(tag: []const u8) ?[]const u8 {
    return TAG_PLACEHOLDER_MAP.get(tag);
}

/// Get the tag name for a placeholder name (reverse lookup).
pub fn getTagName(placeholder: []const u8) ?[]const u8 {
    var it = TAG_PLACEHOLDER_MAP.iterator();
    while (it.next()) |entry| {
        if (std.mem.eql(u8, entry.value_ptr.*, placeholder)) {
            return entry.key_ptr.*;
        }
    }
    return null;
}

// ─── Full PlaceholderRegistry (from placeholder.ts) ─────────

/// PlaceholderRegistry — registers and manages placeholder names.
/// Direct port of `PlaceholderRegistry` class in the TS source.
pub const PlaceholderRegistry = struct {
    allocator: std.mem.Allocator,
    /// Map of content → placeholder name.
    content_to_name: std.StringHashMap([]const u8),
    /// Map of placeholder name → content.
    name_to_content: std.StringHashMap([]const u8),
    /// Counter for generating unique placeholder names.
    ph_counter: u32 = 0,
    /// Counter for generating unique tag placeholder names.
    tag_counter: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) PlaceholderRegistry {
        return .{
            .allocator = allocator,
            .content_to_name = std.StringHashMap([]const u8).init(allocator),
            .name_to_content = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *PlaceholderRegistry) void {
        self.content_to_name.deinit();
        self.name_to_content.deinit();
    }

    /// Register a placeholder and return its name.
    /// Direct port of `registerPlaceholder(content)` in the TS source.
    pub fn registerPlaceholder(self: *PlaceholderRegistry, content: []const u8) ![]const u8 {
        // Check if already registered
        if (self.content_to_name.get(content)) |name| return name;

        self.ph_counter += 1;
        const name_buf = try std.fmt.allocPrint(self.allocator, "PH_{d}", .{self.ph_counter});
        try self.content_to_name.put(content, name_buf);
        try self.name_to_content.put(name_buf, content);
        return name_buf;
    }

    /// Register a tag placeholder and return its name.
    /// Direct port of `registerTagPlaceholder(content)` in the TS source.
    pub fn registerTagPlaceholder(self: *PlaceholderRegistry, tag: []const u8, is_close: bool) ![]const u8 {
        self.tag_counter += 1;
        const prefix: []const u8 = if (is_close) "CLOSE_TAG_" else "START_TAG_";
        const tag_upper_buf = try self.allocator.alloc(u8, tag.len);
        defer self.allocator.free(tag_upper_buf);
        const tag_upper = std.ascii.upperString(tag_upper_buf, tag);
        return std.fmt.allocPrint(self.allocator, "{s}{s}_{d}", .{ prefix, tag_upper, self.tag_counter });
    }

    /// Get the content for a placeholder name.
    pub fn getContent(self: *const PlaceholderRegistry, name: []const u8) ?[]const u8 {
        return self.name_to_content.get(name);
    }

    /// Get the placeholder name for content.
    pub fn getName(self: *const PlaceholderRegistry, content: []const u8) ?[]const u8 {
        return self.content_to_name.get(content);
    }
};

// ─── Tests ──────────────────────────────────────────────────

test "PlaceholderRegistry init/deinit" {
    const allocator = std.testing.allocator;
    var registry = PlaceholderRegistry.init(allocator);
    defer registry.deinit();
}

test "PlaceholderRegistry registerPlaceholder" {
    const allocator = std.testing.allocator;
    var registry = PlaceholderRegistry.init(allocator);
    defer registry.deinit();

    const name1 = try registry.registerPlaceholder("Hello");
    defer allocator.free(name1);
    try std.testing.expect(std.mem.startsWith(u8, name1, "PH_"));

    const name2 = try registry.registerPlaceholder("World");
    defer allocator.free(name2);
    try std.testing.expect(std.mem.startsWith(u8, name2, "PH_"));
    try std.testing.expect(!std.mem.eql(u8, name1, name2));
}

test "PlaceholderRegistry dedup" {
    const allocator = std.testing.allocator;
    var registry = PlaceholderRegistry.init(allocator);
    defer registry.deinit();

    const name1 = try registry.registerPlaceholder("Hello");
    defer allocator.free(name1);
    const name2 = try registry.registerPlaceholder("Hello");
    try std.testing.expectEqualStrings(name1, name2);
}

test "PlaceholderRegistry registerTagPlaceholder" {
    const allocator = std.testing.allocator;
    var registry = PlaceholderRegistry.init(allocator);
    defer registry.deinit();

    const start_name = try registry.registerTagPlaceholder("div", false);
    defer allocator.free(start_name);
    try std.testing.expect(std.mem.startsWith(u8, start_name, "START_TAG_DIV_"));

    const close_name = try registry.registerTagPlaceholder("div", true);
    defer allocator.free(close_name);
    try std.testing.expect(std.mem.startsWith(u8, close_name, "CLOSE_TAG_DIV_"));
}

test "PlaceholderRegistry getContent" {
    const allocator = std.testing.allocator;
    var registry = PlaceholderRegistry.init(allocator);
    defer registry.deinit();

    const name = try registry.registerPlaceholder("Hello");
    defer allocator.free(name);
    try std.testing.expectEqualStrings("Hello", registry.getContent(name).?);
    try std.testing.expect(registry.getContent("unknown") == null);
}
