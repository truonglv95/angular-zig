/// Trusted Types Sinks — Set of tagName|prop pairs that are Trusted Types sinks
///
/// Port of: compiler/src/schema/trusted_types_sinks.ts
const std = @import("std");

/// Set of "tagName|prop" pairs that are Trusted Types sinks.
/// These properties require Trusted Types values in browsers with TT enabled.
pub const TRUSTED_TYPES_SINKS = std.StaticStringMap(void).initComptime(.{
    .{ "iframe|srcdoc", {} },
    .{ "*|innerHTML", {} },
    .{ "*|outerHTML", {} },
    .{ "*|srcdoc", {} },
    .{ "embed|src", {} },
    .{ "object|data", {} },
    .{ "script|src", {} },
    .{ "script|text", {} },
    .{ "script|textContent", {} },
    .{ "script|innerText", {} },
});

/// Check if a tagName|prop pair is a Trusted Types sink.
pub fn isTrustedTypesSink(tag: []const u8, prop: []const u8) bool {
    // Check specific tag|prop
    var key_buf: [128]u8 = undefined;
    const specific_key = std.fmt.bufPrint(&key_buf, "{s}|{s}", .{ tag, prop }) catch return false;
    if (TRUSTED_TYPES_SINKS.has(specific_key)) return true;

    // Check wildcard *|prop
    var wildcard_buf: [128]u8 = undefined;
    const wildcard_key = std.fmt.bufPrint(&wildcard_buf, "*|{s}", .{prop}) catch return false;
    if (TRUSTED_TYPES_SINKS.has(wildcard_key)) return true;

    return false;
}
