/// i18n Translation Bundle — Loads and looks up translations
///
/// Port of: compiler/src/i18n/translation_bundle.ts
const std = @import("std");
const i18n_ast = @import("i18n_ast.zig");

/// A bundle of translations loaded from a serialized format (XLIFF, XMB, XTB).
pub const TranslationBundle = struct {
    translations: std.StringHashMap(i18n_ast.Message),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TranslationBundle {
        return .{
            .translations = std.StringHashMap(i18n_ast.Message).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TranslationBundle) void {
        self.translations.deinit();
    }

    /// Look up a translation by message ID.
    pub fn get(self: *const TranslationBundle, id: []const u8) ?i18n_ast.Message {
        return self.translations.get(id);
    }
};
