/// Style URL Resolver — Resolves style URLs relative to component
///
/// Port of: compiler/src/style_url_resolver.ts
const std = @import("std");

/// Resolves style URLs relative to the component's template URL.
pub fn resolveStyleUrl(base: []const u8, url: []const u8) []const u8 {
    // Simple resolution: if url is absolute, return as-is; otherwise join with base
    _ = base;
    if (url.len > 0 and (url[0] == '/' or std.mem.startsWith(u8, url, "http"))) {
        return url;
    }
    return url; // TODO: proper URL resolution
}
