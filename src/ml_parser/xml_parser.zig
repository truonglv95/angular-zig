/// XML Parser — Thin wrapper extending the base Parser for XML parsing
///
/// Port of: compiler/src/ml_parser/xml_parser.ts (27 LoC)
const parser_mod = @import("parser.zig");

pub const XmlParser = struct {
    inner: parser_mod.Parser,

    pub fn init(allocator: std.mem.Allocator, arena: anytype, source: []const u8, tokens: anytype) XmlParser {
        return .{ .inner = parser_mod.Parser.init(allocator, arena, source, tokens) };
    }

    pub fn parse(self: *XmlParser) !parser_mod.ParseTreeResult {
        return self.inner.parse();
    }

    pub fn deinit(self: *XmlParser) void {
        self.inner.deinit();
    }
};

const std = @import("std");
