/// R3 View i18n Util — i18n helper constants and functions
///
/// Port of: compiler/src/render3/render3/view/i18n/.ts (93 LoC)
const std = @import("std");

/// i18n attribute name.
pub const I18N_ATTR = "i18n";

/// i18n attribute prefix (e.g. "i18n-xxx").
pub const I18N_ATTR_PREFIX = "i18n-";

/// Check if an attribute name is an i18n attribute.
pub fn isI18nAttribute(name: []const u8) bool {
    return std.mem.eql(u8, name, I18N_ATTR) or
           std.mem.startsWith(u8, name, I18N_ATTR_PREFIX);
}

/// Format a placeholder name for display.
pub fn formatI18nPlaceholderName(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    return allocator.dupe(u8, name);
}
