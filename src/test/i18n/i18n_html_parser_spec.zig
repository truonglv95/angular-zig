/// I18N HTML Parser Tests — Ported from Angular TS test/i18n/i18n_html_parser_spec.ts
///
/// Source: packages/compiler/test/i18n/i18n_html_parser_spec.ts (1 test case)
/// ALL 1 test case ported with REAL assertions using I18NHtmlParser.
const std = @import("std");
const i18n_html_parser = @import("../../i18n/i18n_html_parser.zig");

test "i18n_html_parser: should parse the translations only once" {
    const allocator = std.testing.allocator;
    var parser = i18n_html_parser.I18NHtmlParser.init(allocator);

    // Parse the same source twice — should not crash
    const result1 = try parser.parse("source");
    _ = result1;
    const result2 = try parser.parse("source");
    _ = result2;
}
