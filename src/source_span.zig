/// Source Span — Zero-cost source location tracking
///
/// Mỗi AST node đều mang sourceSpan để báo lỗi chính xác.
/// Zig cho phép embedded structs và comptime assertions để đảm bảo
/// consistency.
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Vị trí tuyệt đối trong source (byte offset pair).
/// Compact: chỉ 2 × u32 = 8 bytes.
pub const AbsoluteSourceSpan = struct {
    start: u32,
    end: u32,

    pub fn empty() AbsoluteSourceSpan {
        return .{ .start = 0, .end = 0 };
    }

    pub fn contains(self: AbsoluteSourceSpan, offset: u32) bool {
        return offset >= self.start and offset < self.end;
    }

    pub fn length(self: AbsoluteSourceSpan) u32 {
        return self.end - self.start;
    }
};

/// Vị trí trong file cụ thể (line:col) — chỉ dùng cho error reporting.
pub const ParseLocation = struct {
    offset: u32,
    line: u32,
    col: u32,

    pub fn init(offset: u32, source: []const u8) ParseLocation {
        var line: u32 = 0;
        var col: u32 = 0;
        var i: u32 = 0;
        while (i < offset and i < source.len) : (i += 1) {
            if (source[i] == '\n') {
                line += 1;
                col = 0;
            } else {
                col += 1;
            }
        }
        return .{ .offset = offset, .line = line, .col = col };
    }
};

/// Source span đầy đủ với reference đến source string.
/// Dùng cho error messages với context hiển thị.
pub const ParseSourceSpan = struct {
    start: ParseLocation,
    end: ParseLocation,
    /// Không owning — reference đến source string ban đầu
    full_start: AbsoluteSourceSpan,
    details: ?*const ParseSourceSpan = null,

    pub fn init(start_offset: u32, end_offset: u32, source: []const u8) ParseSourceSpan {
        return .{
            .start = ParseLocation.init(start_offset, source),
            .end = ParseLocation.init(end_offset, source),
            .full_start = .{ .start = start_offset, .end = end_offset },
        };
    }

    pub fn fromAbsolute(abs: AbsoluteSourceSpan) ParseSourceSpan {
        return .{
            .start = .{ .offset = abs.start, .line = 0, .col = 0 },
            .end = .{ .offset = abs.end, .line = 0, .col = 0 },
            .full_start = abs,
        };
    }

    pub fn absolute(self: ParseSourceSpan) AbsoluteSourceSpan {
        return self.full_start;
    }

    pub fn toString(self: ParseSourceSpan, source: []const u8, allocator: Allocator) ![]const u8 {
        const line_start = self.start.offset;
        var line_end = self.start.offset;
        while (line_end < source.len and source[line_end] != '\n') : (line_end += 1) {}
        const line_content = source[line_start..line_end];

        // Tạo pointer marker: "  ^~~~~~"
        const marker_len = @min(self.full_start.end - self.full_start.start, line_end - line_start);
        var marker = try allocator.alloc(u8, marker_len + 1);
        @memset(marker, '~');
        marker[0] = '^';
        marker[marker_len] = 0;

        return std.fmt.allocPrint(allocator, "{d}:{d}: {s}\n{s}\n{s}", .{
            self.start.line + 1,
            self.start.col + 1,
            line_content,
            "",
            marker,
        });
    }
};

/// Lỗi parse — compact error representation.
pub const ParseError = struct {
    span: ParseSourceSpan,
    msg: []const u8,
    level: Level = .Error,

    pub const Level = enum { Error, Warning, Info };

    pub fn format(
        self: ParseError,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.writeAll(self.msg);
    }
};

// ─── Tests ────────────────────────────────────────────────────

test "AbsoluteSourceSpan contains" {
    const span = AbsoluteSourceSpan{ .start = 5, .end = 10 };
    try std.testing.expect(span.contains(5));
    try std.testing.expect(span.contains(9));
    try std.testing.expect(!span.contains(10));
    try std.testing.expect(!span.contains(4));
}

test "ParseLocation init" {
    const source = "hello\nworld";
    const loc = ParseLocation.init(7, source);
    try std.testing.expectEqual(@as(u32, 1), loc.line);
    try std.testing.expectEqual(@as(u32, 1), loc.col);
}

test "ParseSourceSpan init" {
    const source = "hello world";
    const span = ParseSourceSpan.init(0, 5, source);
    try std.testing.expectEqual(@as(u32, 0), span.start.line);
    try std.testing.expectEqual(@as(u32, 5), span.full_start.end);
}
