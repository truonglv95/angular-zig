/// Output JIT Trusted Types — Trusted types sink policy for JIT
///
/// Port of: compiler/src/output/output_jit_trusted_types.ts (144 LoC)
const std = @import("std");

/// Trusted types policy for JIT-compiled code.
pub const TrustedTypesPolicy = struct {
    name: []const u8,

    pub fn createScript(self: *const TrustedTypesPolicy, code: []const u8) []const u8 {
        _ = self;
        return code; // In non-browser environments, pass through
    }
};

/// Create a trusted types policy for JIT compilation.
pub fn createJitPolicy(allocator: std.mem.Allocator) !TrustedTypesPolicy {
    _ = allocator;
    return .{ .name = "ngJit" };
}
