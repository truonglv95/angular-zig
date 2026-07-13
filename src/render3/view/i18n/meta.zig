/// R3 View i18n Meta — Per-element i18n context
///
/// Port of: compiler/src/render3/render3/view/i18n/.ts (363 LoC)
const std = @import("std");

/// I18nMeta — per-element i18n context that flows through the template compiler.
pub const I18nMeta = struct {
    message_id: []const u8 = "",
    meaning: ?[]const u8 = null,
    description: ?[]const u8 = null,
    custom_id: ?[]const u8 = null,
    placeholders: std.StringHashMap([]const u8),
    icu_placeholders: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) I18nMeta {
        return .{
            .placeholders = std.StringHashMap([]const u8).init(allocator),
            .icu_placeholders = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *I18nMeta) void {
        self.placeholders.deinit();
        self.icu_placeholders.deinit();
    }
};
