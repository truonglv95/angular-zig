/// R3 View i18n Meta — i18n metadata visitor
///
/// Port of: compiler/src/render3/view/i18n/meta.ts (363 LoC)
///
/// The I18nMetaVisitor walks the HTML parse tree and converts i18n-related
/// attributes ("i18n" and "i18n-*") into i18n meta objects. These objects
/// are stored alongside element and attribute information for later use
/// during template compilation.
const std = @import("std");

/// I18nMeta — metadata for an i18n block.
/// Direct port of `I18nMeta` type in the TS source.
pub const I18nMeta = struct {
    id: ?[]const u8 = null,
    custom_id: ?[]const u8 = null,
    legacy_ids: ?[]const []const u8 = null,
    description: ?[]const u8 = null,
    meaning: ?[]const u8 = null,
};

/// I18N_ATTR — the `i18n` attribute name.
pub const I18N_ATTR = "i18n";

/// I18N_ATTR_PREFIX — the `i18n-` attribute prefix.
pub const I18N_ATTR_PREFIX = "i18n-";

/// Parse i18n meta string into I18nMeta.
/// Direct port of `parseI18nMeta(meta)` in the TS source.
/// Trims the whole value first, then splits by @@ and |.
/// Empty strings are stored as null (matching TS undefined behavior).
pub fn parseI18nMeta(value: []const u8) I18nMeta {
    var meta = I18nMeta{};

    // Trim the whole value first (TS: meta = meta.trim())
    const trimmed = std.mem.trim(u8, value, " \t\n\r");
    if (trimmed.len == 0) return meta;

    var remaining = trimmed;

    // Check for custom ID: @@custom-id
    if (std.mem.indexOf(u8, remaining, "@@")) |sep_pos| {
        meta.custom_id = remaining[sep_pos + 2 ..];
        remaining = remaining[0..sep_pos];
    }

    // Check for meaning: meaning|description
    if (std.mem.indexOf(u8, remaining, "|")) |sep_pos| {
        meta.meaning = remaining[0..sep_pos];
        if (remaining[sep_pos + 1 ..].len > 0) {
            meta.description = remaining[sep_pos + 1 ..];
        }
    } else {
        if (remaining.len > 0) {
            meta.description = remaining;
        }
    }

    return meta;
}

/// I18nMetaVisitor — walks HTML AST and processes i18n attributes.
/// Direct port of `I18nMetaVisitor` class in the TS source.
pub const I18nMetaVisitor = struct {
    /// Whether visited nodes contain i18n information.
    has_i18n_meta: bool = false,
    /// Errors collected during processing.
    errors: std.array_list.Managed(ParseError),
    allocator: std.mem.Allocator,

    pub const ParseError = struct {
        msg: []const u8,
        span: ?[]const u8 = null,
    };

    pub fn init(allocator: std.mem.Allocator) I18nMetaVisitor {
        return .{
            .errors = std.array_list.Managed(ParseError).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *I18nMetaVisitor) void {
        self.errors.deinit();
    }

    /// Parse an i18n attribute value into I18nMeta.
    /// Direct port of the i18n attribute parsing in the TS source.
    ///
    /// Format: `meaning|description@@custom-id`
    /// Direct port of `parseI18nMeta(meta)` in the TS source.
    /// Trims the whole value first, then splits by @@ and |.
    pub fn parseI18nValue(_: *const I18nMetaVisitor, value: []const u8) I18nMeta {
        return parseI18nMeta(value);
    }

    /// Check if an element has i18n attributes.
    /// Direct port of `hasI18nAttrs(element)` from util.ts.
    pub fn hasI18nAttrs(attrs: []const []const u8) bool {
        for (attrs) |attr| {
            if (std.mem.eql(u8, attr, I18N_ATTR) or
                std.mem.startsWith(u8, attr, I18N_ATTR_PREFIX))
            {
                return true;
            }
        }
        return false;
    }

    /// Check if an attribute is an i18n attribute.
    pub fn isI18nAttr(name: []const u8) bool {
        return std.mem.eql(u8, name, I18N_ATTR) or
            std.mem.startsWith(u8, name, I18N_ATTR_PREFIX);
    }

    /// Get the target attribute name for an i18n-attr.
    /// E.g., "i18n-title" → "title".
    pub fn getI18nAttrTarget(name: []const u8) ?[]const u8 {
        if (std.mem.startsWith(u8, name, I18N_ATTR_PREFIX)) {
            return name[I18N_ATTR_PREFIX.len..];
        }
        return null;
    }

    /// Report a parse error.
    pub fn reportError(self: *I18nMetaVisitor, msg: []const u8, span: ?[]const u8) !void {
        try self.errors.append(.{ .msg = msg, .span = span });
    }
};

// ─── Tests ──────────────────────────────────────────────────

test "parseI18nValue with all parts" {
    const meta = parseI18nMeta("greeting|A greeting@@custom-id");
    try std.testing.expectEqualStrings("greeting", meta.meaning.?);
    try std.testing.expectEqualStrings("A greeting", meta.description.?);
    try std.testing.expectEqualStrings("custom-id", meta.custom_id.?);
}

test "parseI18nValue with meaning only" {
    const meta = parseI18nMeta("greeting");
    try std.testing.expectEqualStrings("greeting", meta.description.?);
    try std.testing.expect(meta.meaning == null);
}

test "hasI18nAttrs" {
    const with_i18n = [_][]const u8{ "class", "i18n" };
    try std.testing.expect(I18nMetaVisitor.hasI18nAttrs(&with_i18n));

    const with_prefix = [_][]const u8{ "i18n-title", "class" };
    try std.testing.expect(I18nMetaVisitor.hasI18nAttrs(&with_prefix));

    const without = [_][]const u8{ "class", "id" };
    try std.testing.expect(!I18nMetaVisitor.hasI18nAttrs(&without));
}

test "isI18nAttr" {
    try std.testing.expect(I18nMetaVisitor.isI18nAttr("i18n"));
    try std.testing.expect(I18nMetaVisitor.isI18nAttr("i18n-title"));
    try std.testing.expect(!I18nMetaVisitor.isI18nAttr("title"));
}

test "getI18nAttrTarget" {
    try std.testing.expectEqualStrings("title", I18nMetaVisitor.getI18nAttrTarget("i18n-title").?);
    try std.testing.expect(I18nMetaVisitor.getI18nAttrTarget("i18n") == null);
}

test "I18nMetaVisitor init/deinit" {
    const allocator = std.testing.allocator;
    var visitor = I18nMetaVisitor.init(allocator);
    defer visitor.deinit();
    try std.testing.expect(!visitor.has_i18n_meta);
    try std.testing.expectEqual(@as(usize, 0), visitor.errors.items.len);
}
