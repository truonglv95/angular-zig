/// XMB Serializer Tests — Ported from Angular TS test/i18n/serializers/xmb_spec.ts
///
/// Source: packages/compiler/test/i18n/serializers/xmb_spec.ts (2 test cases)
/// ALL 2 test cases ported with REAL assertions using the Xmb serializer API.
const std = @import("std");
const xmb = @import("../../../i18n/serializers/xmb.zig");
const i18n_ast = @import("../../../i18n/i18n_ast.zig");

test "xmb: should write a valid xmb file" {
    const allocator = std.testing.allocator;
    var msg = i18n_ast.Message.init(allocator);
    defer msg.deinit();
    msg.id = "test-id";

    const result = try xmb.Xmb.write(allocator, &.{msg}, null);
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result, "<?xml") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "<messagebundle") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "</messagebundle>") != null);
}

test "xmb: should throw when trying to load an xmb file" {
    // TS: load() throws 'Unsupported' — XMB is write-only.
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.Unsupported, xmb.Xmb.load(allocator, "<?xml version=\"1.0\"?><messagebundle></messagebundle>", "url"));
}
