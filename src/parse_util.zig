/// Parse Util — Shared parsing utilities (source spans, errors)
///
/// Port of: compiler/src/parse_util.ts (241 LoC)
///
/// Re-exports source span types and provides parsing utility functions.
const std = @import("std");

// Re-export source span types
pub const AbsoluteSourceSpan = @import("source_span.zig").AbsoluteSourceSpan;
pub const ParseSourceSpan = @import("source_span.zig").ParseSourceSpan;
pub const ParseLocation = @import("source_span.zig").ParseLocation;
pub const ParseError = @import("source_span.zig").ParseError;
pub const ParseErrorLevel = @import("source_span.zig").ParseErrorLevel;

/// Parse a template string and return the source span for a given range.
pub fn createSpan(source: []const u8, start: u32, end: u32) ParseSourceSpan {
    return ParseSourceSpan.init(start, end, source);
}

/// Format a parse error for display.
pub fn formatError(allocator: std.mem.Allocator, error: ParseError, source: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "Error at {d}-{d}: {s}",
        .{ error.span.start, error.span.end, error.msg });
}
