/// i18n HTML Parser — Orchestrate i18n extraction during HTML parsing
const std = @import("std");
const extractor_merger = @import("extractor_merger.zig");

pub const I18NHtmlParser = struct {
    allocator: std.mem.Allocator,
    pub fn init(allocator: std.mem.Allocator) I18NHtmlParser { return .{ .allocator = allocator }; }
    pub fn parse(self: *I18NHtmlParser, source: []const u8) !extractor_merger.ExtractionResult {
        return extractor_merger.extract(self.allocator, source);
    }
};
