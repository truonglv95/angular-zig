/// R3 View i18n Util — i18n helper constants and functions
///
/// Port of: compiler/src/render3/view/i18n/util.ts (93 LoC)
const std = @import("std");

/// i18n attribute name.
pub const I18N_ATTR = "i18n";

/// i18n attribute prefix (e.g. "i18n-xxx").
pub const I18N_ATTR_PREFIX = "i18n-";

/// Prefix of var expressions used in ICUs
pub const I18N_ICU_VAR_PREFIX = "VAR_";

/// Check if an attribute name is an i18n attribute.
pub fn isI18nAttribute(name: []const u8) bool {
    return std.mem.eql(u8, name, I18N_ATTR) or
        std.mem.startsWith(u8, name, I18N_ATTR_PREFIX);
}

/// Convert internal placeholder name to public name.
/// Direct port of `toPublicName(name)` from xmb.ts.
/// Converts to UPPERCASE and replaces non-alphanumeric chars (except _) with _.
pub fn toPublicName(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    errdefer result.deinit();
    for (name) |ch| {
        if ((ch >= 'A' and ch <= 'Z') or (ch >= '0' and ch <= '9') or ch == '_') {
            try result.append(ch);
        } else if (ch >= 'a' and ch <= 'z') {
            try result.append(ch - 32); // to uppercase
        } else {
            try result.append('_'); // replace invalid chars
        }
    }
    return result.toOwnedSlice();
}

/// Converts internal placeholder names to public-facing format.
/// Example: `START_TAG_DIV_1` is converted to `startTagDiv_1`.
/// Direct port of `formatI18nPlaceholderName(name, useCamelCase)`.
pub fn formatI18nPlaceholderName(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    return try formatI18nPlaceholderNameEx(allocator, name, true);
}

/// Extended version with useCamelCase parameter.
pub fn formatI18nPlaceholderNameEx(allocator: std.mem.Allocator, name: []const u8, use_camel_case: bool) ![]const u8 {
    const public_name = try toPublicName(allocator, name);
    if (!use_camel_case) {
        return public_name;
    }
    defer allocator.free(public_name);

    // Split by '_'
    var chunks = std.array_list.Managed([]const u8).init(allocator);
    defer chunks.deinit();
    var start: usize = 0;
    for (public_name, 0..) |ch, i| {
        if (ch == '_') {
            if (i > start) try chunks.append(public_name[start..i]);
            start = i + 1;
        }
    }
    if (start < public_name.len) try chunks.append(public_name[start..]);

    if (chunks.items.len == 0) {
        return allocator.dupe(u8, name);
    }

    var result = std.array_list.Managed(u8).init(allocator);
    errdefer result.deinit();

    // Check if last chunk is a number
    var last_is_number = false;
    var postfix: []const u8 = "";
    const last_chunk = chunks.items[chunks.items.len - 1];
    var all_digits = true;
    for (last_chunk) |c| {
        if (c < '0' or c > '9') {
            all_digits = false;
            break;
        }
    }
    if (all_digits and last_chunk.len > 0) {
        last_is_number = true;
        postfix = last_chunk;
        _ = chunks.swapRemove(chunks.items.len - 1);
    }

    // First chunk: lowercase
    if (chunks.items.len > 0) {
        for (chunks.items[0]) |ch| {
            try result.append(std.ascii.toLower(ch));
        }
    }

    // Remaining chunks: capitalize first letter, lowercase rest
    for (chunks.items[1..]) |chunk| {
        if (chunk.len > 0) {
            try result.append(std.ascii.toUpper(chunk[0]));
            for (chunk[1..]) |ch| {
                try result.append(std.ascii.toLower(ch));
            }
        }
    }

    if (last_is_number) {
        try result.append('_');
        try result.appendSlice(postfix);
    }

    return result.toOwnedSlice();
}
