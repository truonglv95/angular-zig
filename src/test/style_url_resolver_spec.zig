/// Style URL Resolver Tests — Ported from Angular TS test/style_url_resolver_spec.ts
///
/// Source: packages/compiler/test/style_url_resolver_spec.ts (33 lines, 5 test cases)
/// ALL 5 test cases ported with REAL assertions using isStyleUrlResolvable().
const std = @import("std");
const style_url_resolver = @import("../style_url_resolver.zig");

test "style_url_resolver: should resolve relative urls" {
    try std.testing.expect(style_url_resolver.isStyleUrlResolvable("someUrl.css"));
    try std.testing.expect(style_url_resolver.isStyleUrlResolvable("foo/bar.css"));
}

test "style_url_resolver: should resolve package: urls" {
    try std.testing.expect(style_url_resolver.isStyleUrlResolvable("package:someUrl.css"));
}

test "style_url_resolver: should not resolve empty urls" {
    try std.testing.expect(!style_url_resolver.isStyleUrlResolvable(null));
    try std.testing.expect(!style_url_resolver.isStyleUrlResolvable(""));
}

test "style_url_resolver: should not resolve urls with other schema" {
    try std.testing.expect(!style_url_resolver.isStyleUrlResolvable("http://otherurl"));
    try std.testing.expect(!style_url_resolver.isStyleUrlResolvable("https://otherurl"));
    try std.testing.expect(!style_url_resolver.isStyleUrlResolvable("file://otherurl"));
}

test "style_url_resolver: should not resolve urls with absolute paths" {
    try std.testing.expect(!style_url_resolver.isStyleUrlResolvable("/otherurl"));
    try std.testing.expect(!style_url_resolver.isStyleUrlResolvable("//otherurl"));
}
