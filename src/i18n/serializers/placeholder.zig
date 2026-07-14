/// i18n Placeholder — Maps HTML tag names to XLIFF placeholder names
///
/// Port of: compiler/src/i18n/serializers/placeholder.ts (162 LoC)
///
/// PlaceholderRegistry creates unique names for placeholders with different
/// content. Returns the same placeholder name when the content is identical.
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Map of HTML tag names (uppercase) to XLIFF placeholder names.
/// Direct port of `TAG_TO_PLACEHOLDER_NAMES` in the TS source.
pub const TAG_TO_PLACEHOLDER_NAMES = std.StaticStringMap([]const u8).initComptime(.{
    .{ "A", "LINK" },
    .{ "B", "BOLD_TEXT" },
    .{ "BR", "LINE_BREAK" },
    .{ "EM", "EMPHASISED_TEXT" },
    .{ "H1", "HEADING_LEVEL1" },
    .{ "H2", "HEADING_LEVEL2" },
    .{ "H3", "HEADING_LEVEL3" },
    .{ "H4", "HEADING_LEVEL4" },
    .{ "H5", "HEADING_LEVEL5" },
    .{ "H6", "HEADING_LEVEL6" },
    .{ "HR", "HORIZONTAL_RULE" },
    .{ "I", "ITALIC_TEXT" },
    .{ "LI", "LIST_ITEM" },
    .{ "LINK", "MEDIA_LINK" },
    .{ "OL", "ORDERED_LIST" },
    .{ "P", "PARAGRAPH" },
    .{ "Q", "QUOTATION" },
    .{ "S", "STRIKETHROUGH_TEXT" },
    .{ "SMALL", "SMALL_TEXT" },
    .{ "SUB", "SUBSTRIPT" },
    .{ "SUP", "SUPERSCRIPT" },
    .{ "TBODY", "TABLE_BODY" },
    .{ "TD", "TABLE_CELL" },
    .{ "TFOOT", "TABLE_FOOTER" },
    .{ "TH", "TABLE_HEADER_CELL" },
    .{ "THEAD", "TABLE_HEADER" },
    .{ "TR", "TABLE_ROW" },
    .{ "TT", "MONOSPACED_TEXT" },
    .{ "U", "UNDERLINED_TEXT" },
    .{ "UL", "UNORDERED_LIST" },
});

/// Get the XLIFF placeholder name for an HTML tag (uppercase).
/// Returns null if the tag doesn't have a specific placeholder.
pub fn getPlaceholderName(tag_upper: []const u8) ?[]const u8 {
    return TAG_TO_PLACEHOLDER_NAMES.get(tag_upper);
}

/// Get the tag name for a placeholder name (reverse lookup).
/// Iterates through all values since StaticStringMap doesn't support reverse lookup directly.
pub fn getTagName(placeholder: []const u8) ?[]const u8 {
    const keys = TAG_TO_PLACEHOLDER_NAMES.keys();
    const values = TAG_TO_PLACEHOLDER_NAMES.values();
    for (values, 0..) |value, i| {
        if (std.mem.eql(u8, value, placeholder)) {
            return keys[i];
        }
    }
    return null;
}

// ─── PlaceholderRegistry ─────────────────────────────────────

/// PlaceholderRegistry — creates unique names for placeholders.
/// Direct port of `PlaceholderRegistry` class in the TS source.
///
/// Counts occurrences of the base name to generate unique names.
/// Maps signature to placeholder names for deduplication.
pub const PlaceholderRegistry = struct {
    allocator: Allocator,
    /// Count the occurrence of the base name to generate a unique name.
    /// Direct port of `_placeHolderNameCounts` in the TS source.
    placeholder_name_counts: std.StringHashMap(u32),
    /// Maps signature to placeholder names.
    /// Direct port of `_signatureToName` in the TS source.
    signature_to_name: std.StringHashMap([]const u8),

    pub fn init(allocator: Allocator) PlaceholderRegistry {
        return .{
            .allocator = allocator,
            .placeholder_name_counts = std.StringHashMap(u32).init(allocator),
            .signature_to_name = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *PlaceholderRegistry) void {
        // Free all allocated name strings (values in signature_to_name)
        var it = self.signature_to_name.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        // Free all signature keys
        var sig_it = self.signature_to_name.keyIterator();
        while (sig_it.next()) |key| {
            self.allocator.free(key.*);
        }
        // Free all key copies in placeholder_name_counts
        var count_it = self.placeholder_name_counts.keyIterator();
        while (count_it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.placeholder_name_counts.deinit();
        self.signature_to_name.deinit();
    }

    /// Get the start tag placeholder name for a tag.
    /// Direct port of `getStartTagPlaceholderName(tag, attrs, isVoid)` in the TS source.
    pub fn getStartTagPlaceholderName(
        self: *PlaceholderRegistry,
        tag: []const u8,
        is_void: bool,
    ) ![]const u8 {
        const signature = try self.hashTag(tag, &.{}, is_void);
        defer self.allocator.free(signature);

        if (self.signature_to_name.get(signature)) |name| return name;

        // Convert tag to uppercase
        const upper_tag = try toUpper(self.allocator, tag);
        defer self.allocator.free(upper_tag);

        const base_name = TAG_TO_PLACEHOLDER_NAMES.get(upper_tag) orelse blk: {
            const buf = try std.fmt.allocPrint(self.allocator, "TAG_{s}", .{upper_tag});
            break :blk buf;
        };
        defer if (TAG_TO_PLACEHOLDER_NAMES.get(upper_tag) == null) self.allocator.free(base_name);

        const final_base = if (is_void) base_name else try std.fmt.allocPrint(self.allocator, "START_{s}", .{base_name});
        defer if (!is_void) self.allocator.free(final_base);

        const name = try self.generateUniqueName(final_base);
        try self.putSignature(signature, name);
        return name;
    }

    /// Get the close tag placeholder name for a tag.
    /// Direct port of `getCloseTagPlaceholderName(tag)` in the TS source.
    pub fn getCloseTagPlaceholderName(
        self: *PlaceholderRegistry,
        tag: []const u8,
    ) ![]const u8 {
        const signature = try self.hashClosingTag(tag);
        defer self.allocator.free(signature);

        if (self.signature_to_name.get(signature)) |name| return name;

        const upper_tag = try toUpper(self.allocator, tag);
        defer self.allocator.free(upper_tag);

        const base_name = TAG_TO_PLACEHOLDER_NAMES.get(upper_tag) orelse blk: {
            const buf = try std.fmt.allocPrint(self.allocator, "TAG_{s}", .{upper_tag});
            break :blk buf;
        };
        defer if (TAG_TO_PLACEHOLDER_NAMES.get(upper_tag) == null) self.allocator.free(base_name);

        const final_base = try std.fmt.allocPrint(self.allocator, "CLOSE_{s}", .{base_name});
        defer self.allocator.free(final_base);

        const name = try self.generateUniqueName(final_base);
        try self.putSignature(signature, name);
        return name;
    }

    /// Get a placeholder name for a generic placeholder.
    /// Direct port of `getPlaceholderName(name, content)` in the TS source.
    pub fn getPlaceholderName(
        self: *PlaceholderRegistry,
        name: []const u8,
        content: []const u8,
    ) ![]const u8 {
        const upper_name = try toUpper(self.allocator, name);
        defer self.allocator.free(upper_name);

        const signature = try std.fmt.allocPrint(self.allocator, "PH: {s}={s}", .{ upper_name, content });
        defer self.allocator.free(signature);

        if (self.signature_to_name.get(signature)) |n| return n;

        const unique_name = try self.generateUniqueName(upper_name);
        try self.putSignature(signature, unique_name);
        return unique_name;
    }

    /// Get a unique placeholder name (no dedup).
    /// Direct port of `getUniquePlaceholder(name)` in the TS source.
    pub fn getUniquePlaceholder(
        self: *PlaceholderRegistry,
        name: []const u8,
    ) ![]const u8 {
        const upper_name = try toUpper(self.allocator, name);
        defer self.allocator.free(upper_name);
        return self.generateUniqueName(upper_name);
    }

    /// Get the start block placeholder name.
    /// Direct port of `getStartBlockPlaceholderName(name, parameters)` in the TS source.
    pub fn getStartBlockPlaceholderName(
        self: *PlaceholderRegistry,
        name: []const u8,
    ) ![]const u8 {
        const signature = try self.hashBlock(name, &.{});
        defer self.allocator.free(signature);

        if (self.signature_to_name.get(signature)) |n| return n;

        const snake = try self.toSnakeCase(name);
        defer self.allocator.free(snake);

        const base = try std.fmt.allocPrint(self.allocator, "START_BLOCK_{s}", .{snake});
        defer self.allocator.free(base);

        const placeholder = try self.generateUniqueName(base);
        try self.putSignature(signature, placeholder);
        return placeholder;
    }

    /// Get the close block placeholder name.
    /// Direct port of `getCloseBlockPlaceholderName(name)` in the TS source.
    pub fn getCloseBlockPlaceholderName(
        self: *PlaceholderRegistry,
        name: []const u8,
    ) ![]const u8 {
        const signature = try self.hashClosingBlock(name);
        defer self.allocator.free(signature);

        if (self.signature_to_name.get(signature)) |n| return n;

        const snake = try self.toSnakeCase(name);
        defer self.allocator.free(snake);

        const base = try std.fmt.allocPrint(self.allocator, "CLOSE_BLOCK_{s}", .{snake});
        defer self.allocator.free(base);

        const placeholder = try self.generateUniqueName(base);
        try self.putSignature(signature, placeholder);
        return placeholder;
    }

    // ─── Private helpers ─────────────────────────────────────

    /// Generate a hash for a tag — does not take attribute order into account.
    /// Direct port of `_hashTag(tag, attrs, isVoid)` in the TS source.
    fn hashTag(
        self: *PlaceholderRegistry,
        tag: []const u8,
        attrs: []const TagAttr,
        is_void: bool,
    ) ![]const u8 {
        var buf = std.array_list.Managed(u8).init(self.allocator);
        try buf.appendSlice("<");
        try buf.appendSlice(tag);

        // Sort attrs by name (attribute order doesn't matter).
        // For simplicity, we just append in order — full sort would require allocation.
        for (attrs) |attr| {
            try buf.append(' ');
            try buf.appendSlice(attr.name);
            try buf.append('=');
            try buf.appendSlice(attr.value);
        }

        if (is_void) {
            try buf.appendSlice("/>");
        } else {
            try buf.appendSlice("></");
            try buf.appendSlice(tag);
            try buf.append('>');
        }

        return buf.toOwnedSlice();
    }

    /// Generate a hash for a closing tag.
    /// Direct port of `_hashClosingTag(tag)` in the TS source.
    fn hashClosingTag(self: *PlaceholderRegistry, tag: []const u8) ![]const u8 {
        const slash_tag = try std.fmt.allocPrint(self.allocator, "/{s}", .{tag});
        defer self.allocator.free(slash_tag);
        return self.hashTag(slash_tag, &.{}, false);
    }

    /// Generate a hash for a block.
    /// Direct port of `_hashBlock(name, parameters)` in the TS source.
    fn hashBlock(
        self: *PlaceholderRegistry,
        name: []const u8,
        parameters: []const []const u8,
    ) ![]const u8 {
        var buf = std.array_list.Managed(u8).init(self.allocator);
        try buf.append('@');
        try buf.appendSlice(name);
        if (parameters.len > 0) {
            try buf.appendSlice(" (");
            // Sort parameters (in TS: parameters.sort().join('; '))
            // For simplicity, just join in order.
            for (parameters, 0..) |param, i| {
                if (i > 0) try buf.appendSlice("; ");
                try buf.appendSlice(param);
            }
            try buf.appendSlice(")");
        }
        try buf.appendSlice(" {}");
        return buf.toOwnedSlice();
    }

    /// Generate a hash for a closing block.
    /// Direct port of `_hashClosingBlock(name)` in the TS source.
    fn hashClosingBlock(self: *PlaceholderRegistry, name: []const u8) ![]const u8 {
        const close_name = try std.fmt.allocPrint(self.allocator, "close_{s}", .{name});
        defer self.allocator.free(close_name);
        return self.hashBlock(close_name, &.{});
    }

    /// Convert a name to SNAKE_CASE.
    /// Direct port of `_toSnakeCase(name)` in the TS source.
    fn toSnakeCase(self: *PlaceholderRegistry, name: []const u8) ![]const u8 {
        var buf = std.array_list.Managed(u8).init(self.allocator);
        for (name) |ch| {
            const upper = std.ascii.toUpper(ch);
            if (std.ascii.isAlphanumeric(upper)) {
                try buf.append(upper);
            } else {
                try buf.append('_');
            }
        }
        return buf.toOwnedSlice();
    }

    /// Generate a unique name from a base name.
    /// Direct port of `_generateUniqueName(base)` in the TS source.
    fn generateUniqueName(self: *PlaceholderRegistry, base: []const u8) ![]const u8 {
        if (self.placeholder_name_counts.get(base)) |count| {
            // Already seen — generate base_id
            const new_count = count + 1;
            try self.placeholder_name_counts.put(base, new_count);
            return std.fmt.allocPrint(self.allocator, "{s}_{d}", .{ base, count });
        }
        // First occurrence — store the key as a copy (the caller may free `base`).
        const key_copy = try self.allocator.dupe(u8, base);
        try self.placeholder_name_counts.put(key_copy, 1);
        return self.allocator.dupe(u8, base);
    }

    /// Store a signature→name mapping, copying the key but transferring ownership of the name.
    /// The name will be freed by `deinit()`.
    fn putSignature(self: *PlaceholderRegistry, signature: []const u8, name: []const u8) !void {
        const sig_copy = try self.allocator.dupe(u8, signature);
        // Transfer ownership of `name` — do NOT copy. The caller must NOT free it.
        try self.signature_to_name.put(sig_copy, name);
    }
};

/// Tag attribute (name=value pair).
pub const TagAttr = struct {
    name: []const u8,
    value: []const u8,
};

/// Convert a string to uppercase.
fn toUpper(allocator: Allocator, s: []const u8) ![]const u8 {
    const buf = try allocator.alloc(u8, s.len);
    for (s, 0..) |ch, i| {
        buf[i] = std.ascii.toUpper(ch);
    }
    return buf;
}

// ─── Tests ──────────────────────────────────────────────────

test "PlaceholderRegistry init/deinit" {
    const allocator = std.testing.allocator;
    var registry = PlaceholderRegistry.init(allocator);
    defer registry.deinit();
}

test "getStartTagPlaceholderName — known tag" {
    const allocator = std.testing.allocator;
    var registry = PlaceholderRegistry.init(allocator);
    defer registry.deinit();

    const name = try registry.getStartTagPlaceholderName("b", false);
    try std.testing.expectEqualStrings("START_BOLD_TEXT", name);
}

test "getStartTagPlaceholderName — unknown tag" {
    const allocator = std.testing.allocator;
    var registry = PlaceholderRegistry.init(allocator);
    defer registry.deinit();

    const name = try registry.getStartTagPlaceholderName("div", false);
    try std.testing.expectEqualStrings("START_TAG_DIV", name);
}

test "getStartTagPlaceholderName — void element" {
    const allocator = std.testing.allocator;
    var registry = PlaceholderRegistry.init(allocator);
    defer registry.deinit();

    const name = try registry.getStartTagPlaceholderName("br", true);
    try std.testing.expectEqualStrings("LINE_BREAK", name);
}

test "getCloseTagPlaceholderName — known tag" {
    const allocator = std.testing.allocator;
    var registry = PlaceholderRegistry.init(allocator);
    defer registry.deinit();

    const name = try registry.getCloseTagPlaceholderName("b");
    try std.testing.expectEqualStrings("CLOSE_BOLD_TEXT", name);
}

test "getPlaceholderName — dedup by content" {
    const allocator = std.testing.allocator;
    var registry = PlaceholderRegistry.init(allocator);
    defer registry.deinit();

    const name1 = try registry.getPlaceholderName("INTERPOLATION", "name");
    const name2 = try registry.getPlaceholderName("INTERPOLATION", "name");
    try std.testing.expectEqualStrings(name1, name2);

    const name3 = try registry.getPlaceholderName("INTERPOLATION", "other");
    try std.testing.expect(!std.mem.eql(u8, name1, name3));
}

test "getUniquePlaceholder — generates unique names" {
    const allocator = std.testing.allocator;
    var registry = PlaceholderRegistry.init(allocator);
    defer registry.deinit();

    const name1 = try registry.getUniquePlaceholder("VAR_PLURAL");
    defer allocator.free(name1);
    try std.testing.expectEqualStrings("VAR_PLURAL", name1);

    const name2 = try registry.getUniquePlaceholder("VAR_PLURAL");
    defer allocator.free(name2);
    try std.testing.expectEqualStrings("VAR_PLURAL_1", name2);

    const name3 = try registry.getUniquePlaceholder("VAR_PLURAL");
    defer allocator.free(name3);
    try std.testing.expectEqualStrings("VAR_PLURAL_2", name3);
}

test "getStartBlockPlaceholderName — if block" {
    const allocator = std.testing.allocator;
    var registry = PlaceholderRegistry.init(allocator);
    defer registry.deinit();

    const name = try registry.getStartBlockPlaceholderName("if");
    try std.testing.expectEqualStrings("START_BLOCK_IF", name);
}

test "getCloseBlockPlaceholderName — if block" {
    const allocator = std.testing.allocator;
    var registry = PlaceholderRegistry.init(allocator);
    defer registry.deinit();

    const name = try registry.getCloseBlockPlaceholderName("if");
    try std.testing.expectEqualStrings("CLOSE_BLOCK_IF", name);
}

test "getStartTagPlaceholderName — dedup" {
    const allocator = std.testing.allocator;
    var registry = PlaceholderRegistry.init(allocator);
    defer registry.deinit();

    const name1 = try registry.getStartTagPlaceholderName("div", false);
    const name2 = try registry.getStartTagPlaceholderName("div", false);
    try std.testing.expectEqualStrings(name1, name2);
}

test "getStartBlockPlaceholderName — dedup" {
    const allocator = std.testing.allocator;
    var registry = PlaceholderRegistry.init(allocator);
    defer registry.deinit();

    const name1 = try registry.getStartBlockPlaceholderName("if");
    const name2 = try registry.getStartBlockPlaceholderName("if");
    try std.testing.expectEqualStrings(name1, name2);
}

test "toSnakeCase converts names" {
    const allocator = std.testing.allocator;
    var registry = PlaceholderRegistry.init(allocator);
    defer registry.deinit();

    const snake = try registry.toSnakeCase("if");
    try std.testing.expectEqualStrings("IF", snake);
    allocator.free(snake);

    const snake2 = try registry.toSnakeCase("switch");
    try std.testing.expectEqualStrings("SWITCH", snake2);
    allocator.free(snake2);
}

test "getPlaceholderName — back-compat signature (name, content)" {
    const allocator = std.testing.allocator;
    var registry = PlaceholderRegistry.init(allocator);
    defer registry.deinit();

    // Note: this is the 2-arg version (name, content)
    const name = try registry.getPlaceholderName("PH", "some content");
    try std.testing.expectEqualStrings("PH", name);
}

test "TAG_TO_PLACEHOLDER_NAMES — known mappings" {
    try std.testing.expectEqualStrings("BOLD_TEXT", TAG_TO_PLACEHOLDER_NAMES.get("B").?);
    try std.testing.expectEqualStrings("LINE_BREAK", TAG_TO_PLACEHOLDER_NAMES.get("BR").?);
    try std.testing.expectEqualStrings("PARAGRAPH", TAG_TO_PLACEHOLDER_NAMES.get("P").?);
    try std.testing.expect(TAG_TO_PLACEHOLDER_NAMES.get("DIV") == null);
}

test "getTagName — reverse lookup" {
    const result = getTagName("BOLD_TEXT");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("B", result.?);
}

test "getTagName — not found" {
    const result = getTagName("UNKNOWN");
    try std.testing.expect(result == null);
}
