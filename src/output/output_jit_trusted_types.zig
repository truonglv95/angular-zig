/// Output JIT Trusted Types — Trusted types sink policy for JIT
const std = @import("std");

pub const POLICY_NAME = "ngJit";

pub const TrustedTypesPolicy = struct {
    name: []const u8, is_available: bool = false,
    pub fn createScript(self: *const TrustedTypesPolicy, code: []const u8) []const u8 { _ = self; return code; }
    pub fn createHTML(self: *const TrustedTypesPolicy, html: []const u8) []const u8 { _ = self; return html; }
};

pub fn createJitPolicy(allocator: std.mem.Allocator) !TrustedTypesPolicy {
    _ = allocator;
    return .{ .name = POLICY_NAME, .is_available = false };
}

pub fn isTrustedTypesAvailable() bool { return false; }
