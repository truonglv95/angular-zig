/// i18n Serializer — Abstract interface for translation file serializers
///
/// Port of: compiler/src/i18n/serializers/serializer.ts
const std = @import("std");

const i18n_ast = @import("../i18n_ast.zig");
const Message = i18n_ast.Message;

/// Abstract serializer interface.
/// Each format (XLIFF 1.2, XLIFF 2.0, XMB, XTB) implements this.
pub const Serializer = struct {
    name: []const u8,
    extension: []const u8,
    /// Serialize a list of messages to the format's string representation.
    write: *const fn (allocator: std.mem.Allocator, messages: []const Message) anyerror![]const u8,
    /// Load messages from a serialized string (for translation bundles).
    load: *const fn (allocator: std.mem.Allocator, content: []const u8, url: []const u8) anyerror!std.StringHashMap(Message),
};

/// Placeholder mapper — maps placeholder names between source and translation.
pub const PlaceholderMapper = struct {
    /// Map source placeholder names to translation placeholder names.
    map: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) PlaceholderMapper {
        return .{ .map = std.StringHashMap([]const u8).init(allocator) };
    }

    pub fn deinit(self: *PlaceholderMapper) void {
        self.map.deinit();
    }

    pub fn get(self: *const PlaceholderMapper, name: []const u8) ?[]const u8 {
        return self.map.get(name);
    }

    pub fn put(self: *PlaceholderMapper, name: []const u8, value: []const u8) !void {
        try self.map.put(name, value);
    }
};
