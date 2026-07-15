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

// ─── Full Serializer interface (from serializer.ts) ─────────

/// Serializer — abstract interface for i18n serializers.
/// Direct port of `Serializer` abstract class in the TS source.
pub const Serializer = struct {
    /// Serialize messages to a string.
    write_fn: *const fn (allocator: std.mem.Allocator, messages: []const i18n_ast.Message, locale: ?[]const u8) anyerror![]const u8,
    /// Load messages from a string.
    load_fn: *const fn (allocator: std.mem.Allocator, content: []const u8, url: []const u8) anyerror!SerializerLoadResult,
    /// Compute the digest for a message.
    digest_fn: *const fn (msg: *const i18n_ast.Message) []const u8,
    /// Create a name mapper for a message.
    createNameMapper_fn: *const fn (msg: *const i18n_ast.Message) ?SimplePlaceholderMapper,

    pub fn write(self: *const Serializer, allocator: std.mem.Allocator, messages: []const i18n_ast.Message, locale: ?[]const u8) ![]const u8 {
        return self.write_fn(allocator, messages, locale);
    }

    pub fn load(self: *const Serializer, allocator: std.mem.Allocator, content: []const u8, url: []const u8) !SerializerLoadResult {
        return self.load_fn(allocator, content, url);
    }

    pub fn digest(self: *const Serializer, msg: *const i18n_ast.Message) []const u8 {
        return self.digest_fn(msg);
    }

    pub fn createNameMapper(self: *const Serializer, msg: *const i18n_ast.Message) ?SimplePlaceholderMapper {
        return self.createNameMapper_fn(msg);
    }
};

/// SerializerLoadResult — result of loading a translation file.
pub const SerializerLoadResult = struct {
    locale: ?[]const u8,
    messages: std.StringHashMap(i18n_ast.Message),

    pub fn deinit(self: *SerializerLoadResult) void {
        self.messages.deinit();
    }
};

/// SimplePlaceholderMapper — maps placeholder names.
/// Direct port of `SimplePlaceholderMapper` class in the TS source.
pub const SimplePlaceholderMapper = struct {
    public_name: ?[]const u8 = null,
    internal_name: ?[]const u8 = null,

    pub fn toPublicName(self: *const SimplePlaceholderMapper, internal_name: []const u8) ?[]const u8 {
        _ = internal_name;
        return self.public_name;
    }

    pub fn toInternalName(self: *const SimplePlaceholderMapper, public_name: []const u8) ?[]const u8 {
        _ = public_name;
        return self.internal_name;
    }
};

// ─── Tests ──────────────────────────────────────────────────

test "SimplePlaceholderMapper defaults" {
    const mapper = SimplePlaceholderMapper{};
    try std.testing.expect(mapper.public_name == null);
    try std.testing.expect(mapper.internal_name == null);
}

test "SimplePlaceholderMapper with names" {
    const mapper = SimplePlaceholderMapper{ .public_name = "pub", .internal_name = "int" };
    try std.testing.expectEqualStrings("pub", mapper.toPublicName("int").?);
    try std.testing.expectEqualStrings("int", mapper.toInternalName("pub").?);
}
