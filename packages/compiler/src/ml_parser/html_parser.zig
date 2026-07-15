/// HTML Parser — Thin wrapper extending the base Parser for HTML parsing
///
/// Port of: compiler/src/ml_parser/html_parser.ts (21 LoC)
const parser_mod = @import("parser.zig");

pub const HtmlParser = struct {
    inner: parser_mod.Parser,

    pub fn init(allocator: std.mem.Allocator, arena: anytype, source: []const u8, tokens: anytype) HtmlParser {
        return .{ .inner = parser_mod.Parser.init(allocator, arena, source, tokens) };
    }

    pub fn parse(self: *HtmlParser) !parser_mod.ParseTreeResult {
        return self.inner.parse();
    }

    pub fn deinit(self: *HtmlParser) void {
        self.inner.deinit();
    }
};

const std = @import("std");
