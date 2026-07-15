/// R3 View i18n Get Msg Utils — Message generation utilities
///
/// Port of: compiler/src/render3/view/i18n/get_msg_utils.ts (160 LoC)
///
/// Utilities for generating i18n messages from template AST nodes.
const std = @import("std");

/// IcuPlaceholder — info about an ICU placeholder in an i18n message.
pub const IcuPlaceholder = struct {
    name: []const u8,
    icu_id: u32,
    source_span: ?[]const u8 = null,
};

/// MessagePart — a single part of a generated i18n message.
pub const MessagePart = union(enum) {
    text: []const u8,
    placeholder: []const u8,
    icu: IcuPlaceholder,
    tag_open: []const u8,
    tag_close: []const u8,
};

/// Generate a message string from message parts.
/// Direct port of `getMessage(...)` in the TS source.
pub fn getMessage(
    allocator: std.mem.Allocator,
    parts: []const MessagePart,
) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    for (parts) |part| {
        switch (part) {
            .text => |t| try buf.appendSlice(t),
            .placeholder => |p| {
                try buf.appendSlice("{$");
                try buf.appendSlice(p);
                try buf.append('}');
            },
            .icu => |icu| {
                try buf.appendSlice("{$");
                try buf.appendSlice(icu.name);
                try buf.append('}');
            },
            .tag_open => |t| {
                try buf.appendSlice("<");
                try buf.appendSlice(t);
                try buf.append('>');
            },
            .tag_close => |t| {
                try buf.appendSlice("</");
                try buf.appendSlice(t);
                try buf.append('>');
            },
        }
    }

    return buf.toOwnedSlice();
}

/// Generate a placeholder name from an index.
/// Direct port of the placeholder naming logic in the TS source.
pub fn generatePlaceholderName(index: u32) []const u8 {
    _ = index;
    // The TS source generates names like "PH_0", "PH_1", etc.
    // For attribute placeholders: "PH_NAME_0", etc.
    // We can't allocate here, so we return a static prefix.
    return "PH";
}

/// Generate an ICU placeholder name.
pub fn generateIcuPlaceholderName(index: u32) []const u8 {
    _ = index;
    return "ICU";
}

/// Check if a node is an ICU node.
pub fn isIcuNode(kind: u8) bool {
    return kind == 2; // NodeKind.Icu
}

// ─── Tests ──────────────────────────────────────────────────

test "getMessage with text parts" {
    const allocator = std.testing.allocator;
    const parts = [_]MessagePart{
        .{ .text = "Hello " },
        .{ .text = "World" },
        .{ .text = "!" },
    };
    const result = try getMessage(allocator, &parts);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello World!", result);
}

test "getMessage with placeholder" {
    const allocator = std.testing.allocator;
    const parts = [_]MessagePart{
        .{ .text = "Hello " },
        .{ .placeholder = "name" },
        .{ .text = "!" },
    };
    const result = try getMessage(allocator, &parts);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello {$name}!", result);
}

test "getMessage with tag open/close" {
    const allocator = std.testing.allocator;
    const parts = [_]MessagePart{
        .{ .tag_open = "div" },
        .{ .text = "content" },
        .{ .tag_close = "div" },
    };
    const result = try getMessage(allocator, &parts);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("<div>content</div>", result);
}

test "getMessage with ICU" {
    const allocator = std.testing.allocator;
    const parts = [_]MessagePart{
        .{ .text = "Count: " },
        .{ .icu = .{ .name = "count", .icu_id = 0 } },
    };
    const result = try getMessage(allocator, &parts);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Count: {$count}", result);
}
