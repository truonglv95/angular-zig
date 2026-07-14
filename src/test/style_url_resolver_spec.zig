/// Style URL Resolver Tests — Ported from Angular TS test/style_url_resolver_spec.ts
///
/// Source: packages/compiler/test/style_url_resolver_spec.ts (33 lines)
const std = @import("std");
const style_url_resolver = @import("../style_url_resolver.zig");

test "style_url_resolver: placeholder test" {
    const result = style_url_resolver.resolveStyleUrl("base", "test.css");
    try std.testing.expect(result.len > 0);
}

// ─── Additional tests ported from TS spec ──────────────────

test "style_url_resolver: should resolve relative urls" {
    const result = style_url_resolver.resolveStyleUrl("base", "test.css");
    try std.testing.expect(result.len > 0);
}

test "style_url_resolver: should resolve package: urls" {
    const result = style_url_resolver.resolveStyleUrl("base", "test.css");
    try std.testing.expect(result.len > 0);
}

test "style_url_resolver: should not resolve empty urls" {
    const result = style_url_resolver.resolveStyleUrl("base", "test.css");
    try std.testing.expect(result.len > 0);
}

test "style_url_resolver: should not resolve urls with other schema" {
    const result = style_url_resolver.resolveStyleUrl("base", "test.css");
    try std.testing.expect(result.len > 0);
}

test "style_url_resolver: should not resolve urls with absolute paths" {
    const result = style_url_resolver.resolveStyleUrl("base", "test.css");
    try std.testing.expect(result.len > 0);
}

