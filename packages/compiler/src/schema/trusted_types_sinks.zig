/// Trusted Types Sinks — Set of tagName|prop pairs that are Trusted Types sinks
///
/// Port of: compiler/src/schema/trusted_types_sinks.ts (49 LoC)
///
/// Set of tagName|propertyName corresponding to Trusted Types sinks.
/// Properties applying to all tags use '*'.
/// Extracted from https://www.w3.org/TR/trusted-types/#integrations
const std = @import("std");

/// Set of "tagName|prop" pairs that are Trusted Types sinks.
/// Direct port of `TRUSTED_TYPES_SINKS` in the TS source.
/// NOTE: All strings in this set *must* be lowercase!
pub const TRUSTED_TYPES_SINKS = std.StaticStringMap(void).initComptime(.{
    // TrustedHTML
    .{ "iframe|srcdoc", {} },
    .{ "*|innerhtml", {} },
    .{ "*|outerhtml", {} },
    // NB: no TrustedScript here, as the corresponding tags are stripped by the compiler.
    // TrustedScriptURL
    .{ "embed|src", {} },
    .{ "iframe|src", {} },
    .{ "object|codebase", {} },
    .{ "object|data", {} },
});

/// Check if a tagName|prop pair is a Trusted Types sink.
/// Direct port of `isTrustedTypesSink(tagName, propName)` in the TS source.
///
/// Returns true if the given property on the given DOM tag is a Trusted Types
/// sink. In that case, use `ElementSchemaRegistry.securityContext` to determine
/// which particular Trusted Type is required:
/// - SecurityContext.HTML corresponds to TrustedHTML
/// - SecurityContext.RESOURCE_URL corresponds to TrustedScriptURL
pub fn isTrustedTypesSink(tag_name: []const u8, prop_name: []const u8) bool {
    // Make sure comparisons are case insensitive, so that case differences between
    // attribute and property names do not have a security impact.
    var tag_lower_buf: [128]u8 = undefined;
    var prop_lower_buf: [128]u8 = undefined;
    const tag_lower = std.ascii.lowerString(&tag_lower_buf, tag_name);
    const prop_lower = std.ascii.lowerString(&prop_lower_buf, prop_name);

    // Check specific tag|prop
    var key_buf: [256]u8 = undefined;
    const specific_key = std.fmt.bufPrint(&key_buf, "{s}|{s}", .{ tag_lower, prop_lower }) catch return false;
    if (TRUSTED_TYPES_SINKS.has(specific_key)) return true;

    // Check wildcard *|prop
    var wildcard_buf: [256]u8 = undefined;
    const wildcard_key = std.fmt.bufPrint(&wildcard_buf, "*|{s}", .{prop_lower}) catch return false;
    if (TRUSTED_TYPES_SINKS.has(wildcard_key)) return true;

    return false;
}

// ─── Tests ──────────────────────────────────────────────────

test "isTrustedTypesSink innerHTML" {
    try std.testing.expect(isTrustedTypesSink("div", "innerHTML"));
    try std.testing.expect(isTrustedTypesSink("div", "innerhtml"));
    try std.testing.expect(isTrustedTypesSink("span", "INNERHTML"));
}

test "isTrustedTypesSink outerHTML" {
    try std.testing.expect(isTrustedTypesSink("div", "outerHTML"));
}

test "isTrustedTypesSink iframe srcdoc" {
    try std.testing.expect(isTrustedTypesSink("iframe", "srcdoc"));
    try std.testing.expect(isTrustedTypesSink("IFRAME", "SRCDOC"));
}

test "isTrustedTypesSink embed src" {
    try std.testing.expect(isTrustedTypesSink("embed", "src"));
}

test "isTrustedTypesSink iframe src" {
    try std.testing.expect(isTrustedTypesSink("iframe", "src"));
}

test "isTrustedTypesSink object data" {
    try std.testing.expect(isTrustedTypesSink("object", "data"));
    try std.testing.expect(isTrustedTypesSink("object", "codebase"));
}

test "isTrustedTypesSink not a sink" {
    try std.testing.expect(!isTrustedTypesSink("div", "class"));
    try std.testing.expect(!isTrustedTypesSink("div", "textContent"));
    try std.testing.expect(!isTrustedTypesSink("a", "href"));
}

test "isTrustedTypesSink case insensitive" {
    try std.testing.expect(isTrustedTypesSink("DIV", "InnerHTML"));
    try std.testing.expect(isTrustedTypesSink("IFrame", "SrcDoc"));
}
