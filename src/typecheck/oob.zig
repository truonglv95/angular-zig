/// TCB OOB — OutOfBandDiagnosticRecorder
///
/// Port of: compiler/src/typecheck/typecheck/oob.ts (236 LoC)
const std = @import("std");

/// OutOfBandDiagnosticRecorder — collects non-type-checker errors.
pub const OutOfBandDiagnosticRecorder = struct {
    errors: std.ArrayList(OobError),
    allocator: std.mem.Allocator,

    pub const OobError = struct {
        message: []const u8,
        code: u32,
    };

    pub fn init(allocator: std.mem.Allocator) OutOfBandDiagnosticRecorder {
        return .{ .errors = std.ArrayList(OobError).init(allocator), .allocator = allocator };
    }

    pub fn deinit(self: *OutOfBandDiagnosticRecorder) void {
        self.errors.deinit();
    }

    pub fn addError(self: *OutOfBandDiagnosticRecorder, message: []const u8, code: u32) !void {
        try self.errors.append(.{ .message = message, .code = code });
    }
};
