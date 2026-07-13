/// Parse Util — Shared parsing utilities (source spans, errors)
///
/// Port of: compiler/src/parse_util.ts
const std = @import("std");

// Re-export source_span types from source_span.zig
pub const AbsoluteSourceSpan = @import("source_span.zig").AbsoluteSourceSpan;
pub const ParseSourceSpan = @import("source_span.zig").ParseSourceSpan;
pub const ParseLocation = @import("source_span.zig").ParseLocation;
pub const ParseError = @import("source_span.zig").ParseError;
