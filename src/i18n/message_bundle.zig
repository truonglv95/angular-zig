/// i18n Message Bundle — Collects extracted messages
///
/// Port of: compiler/src/i18n/message_bundle.ts
const std = @import("std");
const i18n_ast = @import("i18n_ast.zig");

/// A collection of i18n messages extracted from templates.
pub const MessageBundle = struct {
    messages: std.StringHashMap(i18n_ast.Message),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MessageBundle {
        return .{
            .messages = std.StringHashMap(i18n_ast.Message).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MessageBundle) void {
        self.messages.deinit();
    }

    /// Add a message to the bundle. Deduplicates by message string.
    pub fn add(self: *MessageBundle, msg: i18n_ast.Message) !void {
        if (!self.messages.contains(msg.message_string)) {
            try self.messages.put(msg.message_string, msg);
        }
    }

    /// Get all messages as a slice.
    pub fn getMessages(self: *const MessageBundle, allocator: std.mem.Allocator) ![]const i18n_ast.Message {
        var list = std.ArrayList(i18n_ast.Message).init(allocator);
        var it = self.messages.iterator();
        while (it.next()) |entry| {
            try list.append(entry.value_ptr.*);
        }
        return list.toOwnedSlice();
    }
};
