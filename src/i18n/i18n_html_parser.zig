/// i18n HTML Parser — Orchestrates extraction + merging during parsing
///
/// Port of: compiler/src/i18n/i18n_html_parser.ts
const std = @import("std");

/// Wrapper that runs i18n extraction/merging during HTML parsing.
/// This is the main entry point for the i18n pipeline.
pub fn parse(allocator: std.mem.Allocator, source: []const u8) !void {
    _ = allocator;
    _ = source;
    // TODO: orchestrate i18n extraction during HTML parse
}
