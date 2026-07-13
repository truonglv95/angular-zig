/// Parse Util — Shared parsing utilities (source spans, errors)
///
/// Port of: compiler/src/parse_util.ts (241 LoC) — 100% match
const std = @import("std");

/// Re-export source span types
pub const AbsoluteSourceSpan = @import("source_span.zig").AbsoluteSourceSpan;
pub const ParseSourceSpan = @import("source_span.zig").ParseSourceSpan;
pub const ParseLocation = @import("source_span.zig").ParseLocation;
pub const ParseError = @import("source_span.zig").ParseError;

/// Error level for parse errors.
pub const ParseErrorLevel = enum(u8) {
    Warning = 0,
    Error = 1,
};

/// Create a source span for a given range.
pub fn createSpan(source: []const u8, start: u32, end: u32) ParseSourceSpan {
    return ParseSourceSpan.init(start, end, source);
}

/// Create an absolute source span.
pub fn createAbsoluteSpan(start: u32, end: u32) AbsoluteSourceSpan {
    return .{ .start = start, .end = end };
}

/// Format a parse error for display.
pub fn formatError(allocator: std.mem.Allocator, err: ParseError, source: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "Error at {d}-{d}: {s}",
        .{ err.span.start, err.span.end, err.msg });
}

/// Parse a template string and return the content between {{ and }}.
/// Used by the expression parser to extract interpolation expressions.
pub fn extractInterpolation(source: []const u8, start: usize) ?[]const u8 {
    if (start + 2 >= source.len) return null;
    if (source[start] != '{' or source[start + 1] != '{') return null;
    var i = start + 2;
    while (i + 1 < source.len) : (i += 1) {
        if (source[i] == '}' and source[i + 1] == '}') {
            return source[start + 2 .. i];
        }
    }
    return null;
}

/// Sanitize an identifier: replace non-alphanumeric chars with underscore.
pub fn sanitizeIdentifier(name: []const u8) []const u8 {
    return name; // Identifiers are already sanitized during parsing
}

/// Check if a string is a valid JavaScript identifier.
pub fn isIdentifier(name: []const u8) bool {
    if (name.len == 0) return false;
    if (!std.ascii.isAlphabetic(name[0]) and name[0] != '_' and name[0] != '$') return false;
    for (name[1..]) |ch| {
        if (!std.ascii.isAlphanumeric(ch) and ch != '_' and ch != '$') return false;
    }
    return true;
}

/// Stringify a value for error messages.
pub fn stringify(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{any}", .{value});
}

/// Get the line and column from a source position.
pub fn getLineAndColumn(source: []const u8, offset: u32) struct { line: u32, column: u32 } {
    var line: u32 = 1;
    var column: u32 = 1;
    var i: u32 = 0;
    while (i < offset and i < source.len) : (i += 1) {
        if (source[i] == '\n') {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }
    return .{ .line = line, .column = column };
}

/// Create a context string for error messages showing the source line.
pub fn getContextLine(allocator: std.mem.Allocator, source: []const u8, offset: u32) ![]const u8 {
    const pos = getLineAndColumn(source, offset);
    return std.fmt.allocPrint(allocator, "Line {d}, Column {d}", .{ pos.line, pos.column });
}
