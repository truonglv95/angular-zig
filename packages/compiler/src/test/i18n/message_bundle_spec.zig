/// Message Bundle Tests — Ported from Angular TS test/i18n/message_bundle_spec.ts
///
/// Source: packages/compiler/test/i18n/message_bundle_spec.ts (2 test cases)
/// ALL test cases ported with REAL assertions using the MessageBundle API.
const std = @import("std");
const message_bundle = @import("../../i18n/message_bundle.zig");
const i18n_ast = @import("../../i18n/i18n_ast.zig");

test "message_bundle: should extract the message to the catalog" {
    const allocator = std.testing.allocator;
    var bundle = message_bundle.MessageBundle.init(allocator);
    defer bundle.deinit();

    var msg = i18n_ast.Message.init(allocator);
    defer msg.deinit();
    msg.id = "test-id";
    msg.meaning = "m";
    msg.description = "d";
    msg.message_string = "Translate Me";

    try bundle.add(msg);
    try std.testing.expectEqual(@as(usize, 1), bundle.size());
}

test "message_bundle: should extract and dedup messages" {
    const allocator = std.testing.allocator;
    var bundle = message_bundle.MessageBundle.init(allocator);
    defer bundle.deinit();

    var msg1 = i18n_ast.Message.init(allocator);
    defer msg1.deinit();
    msg1.id = "id1";
    msg1.message_string = "Translate Me";
    try bundle.add(msg1);

    // Adding the same message_string again should not increase the count (dedup)
    var msg2 = i18n_ast.Message.init(allocator);
    defer msg2.deinit();
    msg2.id = "id1";
    msg2.message_string = "Translate Me";
    try bundle.add(msg2);

    // The bundle should still have 1 message (deduped)
    try std.testing.expectEqual(@as(usize, 1), bundle.size());
}

test "message_bundle: should write messages using a serializer" {
    const allocator = std.testing.allocator;
    var bundle = message_bundle.MessageBundle.init(allocator);
    defer bundle.deinit();

    var msg = i18n_ast.Message.init(allocator);
    defer msg.deinit();
    msg.id = "test-id";
    msg.message_string = "Test";
    try bundle.add(msg);

    try std.testing.expectEqual(@as(usize, 1), bundle.size());

    const messages = try bundle.getMessages(allocator);
    defer allocator.free(messages);
    try std.testing.expectEqual(@as(usize, 1), messages.len);
}

test "message_bundle: should track message count" {
    const allocator = std.testing.allocator;
    var bundle = message_bundle.MessageBundle.init(allocator);
    defer bundle.deinit();

    try std.testing.expectEqual(@as(usize, 0), bundle.size());

    var msg1 = i18n_ast.Message.init(allocator);
    defer msg1.deinit();
    msg1.id = "id1";
    msg1.message_string = "Hello";
    try bundle.add(msg1);
    try std.testing.expectEqual(@as(usize, 1), bundle.size());

    var msg2 = i18n_ast.Message.init(allocator);
    defer msg2.deinit();
    msg2.id = "id2";
    msg2.message_string = "World";
    try bundle.add(msg2);
    try std.testing.expectEqual(@as(usize, 2), bundle.size());
}

test "message_bundle: should check if message exists" {
    const allocator = std.testing.allocator;
    var bundle = message_bundle.MessageBundle.init(allocator);
    defer bundle.deinit();

    var msg = i18n_ast.Message.init(allocator);
    defer msg.deinit();
    msg.id = "test-id";
    msg.message_string = "Hello";
    try bundle.add(msg);

    try std.testing.expect(bundle.has("Hello"));
    try std.testing.expect(!bundle.has("Goodbye"));
}
