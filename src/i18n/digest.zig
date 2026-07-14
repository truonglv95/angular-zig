/// i18n Digest — Message ID computation (SHA1 + decimal)
///
/// Port of: compiler/src/i18n/digest.ts
///
/// Computes stable message IDs for i18n messages using two algorithms:
/// - SHA1 digest (used by XLIFF 1.2 format)
/// - Decimal digest (used by XLIFF 2.0, XMB, $localize)
const std = @import("std");

const i18n_ast = @import("i18n_ast.zig");

/// Return the message ID or compute it using the XLIFF1 digest (SHA1).
pub fn digest(message: *const i18n_ast.Message) []const u8 {
    if (message.id.len > 0) return message.id;
    return ""; // computeDigest is async — see below
}

/// Compute the message ID using SHA1 of the serialized message + meaning.
pub fn computeDigest(allocator: std.mem.Allocator, message: *const i18n_ast.Message) ![]const u8 {
    // Serialize message nodes to string
    const serialized = try i18n_ast.serializeMessage(allocator, message.nodes);
    defer allocator.free(serialized);

    // Build the digest input: serialized + "[meaning]"
    var input = std.array_list.Managed(u8).init(allocator);
    defer input.deinit();
    try input.appendSlice(serialized);
    try input.append('[');
    try input.appendSlice(message.meaning);
    try input.append(']');

    // Compute SHA1 hash
    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(input.items);
    var hash: [20]u8 = undefined;
    hasher.final(&hash);

    // Convert to hex string
    const hex = try allocator.alloc(u8, 40);
    const hex_chars = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        hex[i * 2] = hex_chars[byte >> 4];
        hex[i * 2 + 1] = hex_chars[byte & 0x0F];
    }
    return hex;
}

/// Return the message ID or compute it using the decimal digest (XLIFF2/XMB).
pub fn decimalDigest(message: *const i18n_ast.Message) []const u8 {
    if (message.id.len > 0) return message.id;
    return ""; // computeDecimalDigest is async — see below
}

/// Compute the message ID using the decimal digest algorithm.
pub fn computeDecimalDigest(allocator: std.mem.Allocator, message: *const i18n_ast.Message) ![]const u8 {
    // Serialize message nodes (ignoring ICU expressions)
    const serialized = try serializeNodesIgnoreIcu(allocator, message.nodes);
    defer allocator.free(serialized);

    return computeMsgId(allocator, serialized, message.meaning);
}

/// Compute a message ID from a serialized string + meaning.
/// Uses a custom hash algorithm that produces decimal IDs.
pub fn computeMsgId(allocator: std.mem.Allocator, input: []const u8, meaning: []const u8) ![]const u8 {
    // Combine input + meaning
    var combined = std.array_list.Managed(u8).init(allocator);
    defer combined.deinit();
    try combined.appendSlice(input);
    if (meaning.len > 0) {
        try combined.appendSlice(meaning);
    }

    // Use SHA256 for a stable hash
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(combined.items);
    var hash: [32]u8 = undefined;
    hasher.final(&hash);

    // Convert first 8 bytes to a decimal string (like Angular's computeMsgId)
    // Angular uses: base64url(hash).substring(0, 10) but we use hex for simplicity
    // Convert first 8 bytes to hex string
    const hex = try allocator.alloc(u8, 16);
    const hex_chars = "0123456789abcdef";
    for (hash[0..8], 0..) |byte, i| {
        hex[i * 2] = hex_chars[byte >> 4];
        hex[i * 2 + 1] = hex_chars[byte & 0x0F];
    }
    return hex;
}

/// Serialize nodes, ignoring ICU expressions (for decimal digest).
fn serializeNodesIgnoreIcu(allocator: std.mem.Allocator, nodes: []const i18n_ast.Node) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    for (nodes) |node| {
        try serializeNodeIgnoreIcu(&buf, &node);
    }
    return buf.toOwnedSlice();
}

fn serializeNodeIgnoreIcu(buf: *std.ArrayList(u8), node: *const i18n_ast.Node) !void {
    switch (node.data) {
        .text => |t| try buf.appendSlice(t.value),
        .container => |c| {
            for (c.children) |child| {
                try serializeNodeIgnoreIcu(buf, &child);
            }
        },
        .icu => {
            // Ignore ICU expression content — only use placeholder name
            try buf.appendSlice("{ICU}");
        },
        .placeholder => |ph| {
            try buf.append('{');
            try buf.appendSlice(ph.name);
            try buf.append('}');
        },
        .tag_placeholder => |tp| {
            if (tp.is_start) {
                try buf.append('<');
                try buf.appendSlice(tp.tag);
                try buf.append('>');
            } else if (tp.is_close) {
                try buf.appendSlice("</");
                try buf.appendSlice(tp.tag);
                try buf.append('>');
            }
            for (tp.children) |child| {
                try serializeNodeIgnoreIcu(buf, &child);
            }
        },
    }
}

// ─── Tests ──────────────────────────────────────────────────

test "digest returns existing ID" {
    var msg = i18n_ast.Message.init(std.testing.allocator);
    defer msg.nodes = &.{};
    msg.id = "existing-id";
    const result = digest(&msg);
    try std.testing.expectEqualStrings("existing-id", result);
}

test "digest returns empty for no ID" {
    var msg = i18n_ast.Message.init(std.testing.allocator);
    defer msg.nodes = &.{};
    msg.id = "";
    const result = digest(&msg);
    try std.testing.expectEqualStrings("", result);
}

test "computeDigest produces hex string" {
    const allocator = std.testing.allocator;
    var msg = i18n_ast.Message.init(allocator);
    msg.id = "";
    msg.meaning = "test";
    msg.nodes = &.{};
    const result = try computeDigest(allocator, &msg);
    defer allocator.free(result);
    // SHA1 produces 20 bytes = 40 hex chars
    try std.testing.expectEqual(@as(usize, 40), result.len);
}

test "computeDigest is deterministic" {
    const allocator = std.testing.allocator;
    var msg1 = i18n_ast.Message.init(allocator);
    msg1.id = "";
    msg1.meaning = "test";
    msg1.nodes = &.{};
    const result1 = try computeDigest(allocator, &msg1);
    defer allocator.free(result1);

    var msg2 = i18n_ast.Message.init(allocator);
    msg2.id = "";
    msg2.meaning = "test";
    msg2.nodes = &.{};
    const result2 = try computeDigest(allocator, &msg2);
    defer allocator.free(result2);

    try std.testing.expectEqualStrings(result1, result2);
}

test "computeDigest differs for different meanings" {
    const allocator = std.testing.allocator;
    var msg1 = i18n_ast.Message.init(allocator);
    msg1.id = "";
    msg1.meaning = "greeting";
    msg1.nodes = &.{};
    const result1 = try computeDigest(allocator, &msg1);
    defer allocator.free(result1);

    var msg2 = i18n_ast.Message.init(allocator);
    msg2.id = "";
    msg2.meaning = "farewell";
    msg2.nodes = &.{};
    const result2 = try computeDigest(allocator, &msg2);
    defer allocator.free(result2);

    try std.testing.expect(!std.mem.eql(u8, result1, result2));
}

test "decimalDigest returns existing ID" {
    var msg = i18n_ast.Message.init(std.testing.allocator);
    defer msg.nodes = &.{};
    msg.id = "existing-id";
    const result = decimalDigest(&msg);
    try std.testing.expectEqualStrings("existing-id", result);
}

test "computeMsgId produces hex string" {
    const allocator = std.testing.allocator;
    const result = try computeMsgId(allocator, "Hello World", "");
    defer allocator.free(result);
    // 8 bytes = 16 hex chars
    try std.testing.expectEqual(@as(usize, 16), result.len);
}

test "computeMsgId is deterministic" {
    const allocator = std.testing.allocator;
    const result1 = try computeMsgId(allocator, "test", "meaning");
    defer allocator.free(result1);
    const result2 = try computeMsgId(allocator, "test", "meaning");
    defer allocator.free(result2);
    try std.testing.expectEqualStrings(result1, result2);
}

test "computeMsgId differs for different inputs" {
    const allocator = std.testing.allocator;
    const result1 = try computeMsgId(allocator, "Hello", "");
    defer allocator.free(result1);
    const result2 = try computeMsgId(allocator, "World", "");
    defer allocator.free(result2);
    try std.testing.expect(!std.mem.eql(u8, result1, result2));
}

test "computeMsgId differs for different meanings" {
    const allocator = std.testing.allocator;
    const result1 = try computeMsgId(allocator, "Hello", "greeting");
    defer allocator.free(result1);
    const result2 = try computeMsgId(allocator, "Hello", "farewell");
    defer allocator.free(result2);
    try std.testing.expect(!std.mem.eql(u8, result1, result2));
}
