/// Core — Core compiler types and utilities
///
/// Port of: compiler/src/core.ts
const std = @import("std");

/// Core types used across the compiler.
pub const CompileResult = struct {
    output: []const u8,
    errors: []const []const u8 = &.{},
};
