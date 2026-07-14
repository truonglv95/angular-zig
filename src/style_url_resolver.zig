/// Style URL Resolver — Resolves style URLs relative to component
///
/// Port of: compiler/src/style_url_resolver.ts
const std = @import("std");

/// Check if a style URL is resolvable.
/// Direct port of `isStyleUrlResolvable(url)` in the TS source.
///
/// Returns true if the URL is a relative URL or a package: URL.
/// Returns false for empty, absolute paths, or URLs with other schemas.
pub fn isStyleUrlResolvable(url: ?[]const u8) bool {
    if (url == null) return false;
    const u = url.?;
    if (u.len == 0) return false;
    if (std.mem.startsWith(u8, u, "package:")) return true;
    // Absolute path
    if (u[0] == '/') return false;
    // Schema (e.g., http://, https://, file://)
    if (std.mem.indexOf(u8, u, "://") != null) return false;
    // Protocol-relative URL (//example.com)
    if (u.len >= 2 and u[0] == '/' and u[1] == '/') return false;
    return true;
}

/// Resolves style URLs relative to the component's template URL.
pub fn resolveStyleUrl(base: []const u8, url: []const u8) []const u8 {
    // Simple resolution: if url is absolute, return as-is; otherwise join with base
    _ = base;
    if (url.len > 0 and (url[0] == '/' or std.mem.startsWith(u8, url, "http"))) {
        return url;
    }
    return url; // TODO: proper URL resolution
}
