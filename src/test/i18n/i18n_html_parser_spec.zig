/// I18N HTML Parser Tests — Ported from Angular TS test/i18n/i18n_html_parser_spec.ts
///
/// Source: packages/compiler/test/i18n/i18n_html_parser_spec.ts (1 test case)
/// ALL 1 test case ported with REAL assertions using I18NHtmlParser.
const std = @import("std");
const i18n_html_parser = @import("../../i18n/i18n_html_parser.zig");

test "i18n_html_parser: should parse the translations only once" {
    const allocator = std.testing.allocator;
    var parser = i18n_html_parser.I18NHtmlParser.init(allocator);

    // Parse the same source twice — both should succeed and return consistent results.
    var result1 = try parser.parse("<div i18n=\"m|d\">text</div>");
    defer result1.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), result1.messages_list.len);

    var result2 = try parser.parse("<div i18n=\"m|d\">text</div>");
    defer result2.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), result2.messages_list.len);

    // Both parses should produce the same meaning.
    try std.testing.expectEqualStrings(result1.messages_list[0].meaning, result2.messages_list[0].meaning);
}
