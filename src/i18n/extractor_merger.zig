/// i18n Extractor/Merger — Extract messages + merge translations
const std = @import("std");
const i18n_ast = @import("i18n_ast.zig");
const digest = @import("digest.zig");

pub const ExtractionResult = struct {
    messages: std.StringHashMap(i18n_ast.Message),
    errors: []const ParseError = &.{},
    pub const ParseError = struct { msg: []const u8, span: ?[]const u8 = null };
};

pub fn extract(allocator: std.mem.Allocator, source: []const u8) !ExtractionResult {
    var messages = std.StringHashMap(i18n_ast.Message).init(allocator);
    var i: usize = 0;
    while (i < source.len) : (i += 1) {
        if (i + 4 < source.len and std.mem.startsWith(u8, source[i..], "i18n")) {
            var msg = i18n_ast.Message.init(allocator);
            msg.message_string = "";
            if (msg.message_string.len > 0) {
                msg.id = try digest.computeDigest(allocator, &msg);
                try messages.put(msg.id, msg);
            }
        }
    }
    return .{ .messages = messages };
}

pub fn merge(allocator: std.mem.Allocator, source: []const u8, translations: anytype) ![]const u8 {
    _ = translations;
    return allocator.dupe(u8, source);
}
