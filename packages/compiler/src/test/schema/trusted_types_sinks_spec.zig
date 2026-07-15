/// Trusted Types Sinks Tests — Ported from Angular TS test/schema/trusted_types_sinks_spec.ts
///
/// Source: packages/compiler/test/schema/trusted_types_sinks_spec.ts (3 test cases)
/// ALL 3 test cases ported with REAL assertions using isTrustedTypesSink.
const std = @import("std");
const tts = @import("../../schema/trusted_types_sinks.zig");

test "trusted_types_sinks: should classify Trusted Types sinks" {
    try std.testing.expect(tts.isTrustedTypesSink("iframe", "srcdoc"));
    try std.testing.expect(tts.isTrustedTypesSink("p", "innerHTML"));
    try std.testing.expect(tts.isTrustedTypesSink("embed", "src"));
    try std.testing.expect(tts.isTrustedTypesSink("iframe", "src"));
    try std.testing.expect(!tts.isTrustedTypesSink("a", "href"));
    try std.testing.expect(!tts.isTrustedTypesSink("base", "href"));
    try std.testing.expect(!tts.isTrustedTypesSink("div", "style"));
}

test "trusted_types_sinks: should classify Trusted Types sinks case insensitive" {
    try std.testing.expect(tts.isTrustedTypesSink("p", "iNnErHtMl"));
    try std.testing.expect(!tts.isTrustedTypesSink("p", "formaction"));
    try std.testing.expect(!tts.isTrustedTypesSink("p", "formAction"));
}

test "trusted_types_sinks: should classify attributes as Trusted Types sinks" {
    try std.testing.expect(tts.isTrustedTypesSink("p", "innerHtml"));
    try std.testing.expect(!tts.isTrustedTypesSink("p", "formaction"));
}
