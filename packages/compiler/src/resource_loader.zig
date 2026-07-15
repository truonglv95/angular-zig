/// Resource Loader — Load templates and styles from URLs
///
/// Port of: compiler/src/resource_loader.ts
const std = @import("std");

/// Interface for loading resources (templates, styles) from URLs.
/// In AOT mode, resources are loaded at build time.
pub const ResourceLoader = struct {
    get: *const fn (self: *const ResourceLoader, url: []const u8) anyerror![]const u8,
};
