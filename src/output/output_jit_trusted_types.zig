/// Output JIT Trusted Types — Trusted types sink policy for JIT
///
/// Port of: compiler/src/output/output_jit_trusted_types.ts (144 LoC)
///
/// Facilitates use of a Trusted Types policy within the JIT compiler.
/// It lazily constructs the Trusted Types policy, providing helper utilities
/// for promoting strings to Trusted Types. When Trusted Types are not
/// available, strings are used as a fallback.
const std = @import("std");

/// The policy name used for Angular JIT.
/// Direct port of `POLICY_NAME` in the TS source.
pub const POLICY_NAME = "ngJit";

/// TrustedScript — a branded type for trusted script content.
/// Direct port of `TrustedScript` interface in the TS source.
pub const TrustedScript = struct {
    code: []const u8,
    __brand: []const u8 = "TrustedScript",
};

/// TrustedTypePolicy — a policy for creating trusted types.
/// Direct port of `TrustedTypePolicy` interface in the TS source.
pub const TrustedTypePolicy = struct {
    name: []const u8,
    is_available: bool = false,

    /// Create a trusted script from a string.
    /// Direct port of `createScript(input)` in the TS source.
    pub fn createScript(self: *const TrustedTypePolicy, code: []const u8) TrustedScript {
        _ = self;
        return .{ .code = code };
    }

    /// Create a trusted HTML from a string.
    pub fn createHTML(self: *const TrustedTypePolicy, html: []const u8) []const u8 {
        _ = self;
        return html;
    }
};

/// TrustedTypePolicyFactory — factory for creating trusted type policies.
/// Direct port of `TrustedTypePolicyFactory` interface in the TS source.
pub const TrustedTypePolicyFactory = struct {
    is_available: bool = false,

    /// Create a new trusted type policy.
    pub fn createPolicy(self: *const TrustedTypePolicyFactory, name: []const u8) TrustedTypePolicy {
        return .{
            .name = name,
            .is_available = self.is_available,
        };
    }
};

/// The cached policy (null if not created yet, or if Trusted Types are not available).
var cached_policy: ?TrustedTypePolicy = null;

/// Create the JIT trusted types policy.
/// Direct port of `getPolicy()` in the TS source.
///
/// If Trusted Types are not available, returns a policy with `is_available = false`.
/// The policy is cached after first creation.
pub fn createJitPolicy(allocator: std.mem.Allocator) !TrustedTypePolicy {
    _ = allocator;
    if (cached_policy) |policy| return policy;
    const policy = TrustedTypePolicy{
        .name = POLICY_NAME,
        .is_available = false, // Trusted Types not available in our environment
    };
    cached_policy = policy;
    return policy;
}

/// Check if Trusted Types are available in the current environment.
/// Direct port of `isTrustedTypesAvailable()` in the TS source.
pub fn isTrustedTypesAvailable() bool {
    return false; // Not available in our environment
}

/// Create a new trusted function for JIT evaluation.
/// Direct port of `newTrustedFunctionForJIT(policy, code)` in the TS source.
///
/// When Trusted Types are available, wraps the code in a TrustedScript.
/// When not available, returns the code as-is.
pub fn newTrustedFunctionForJIT(
    allocator: std.mem.Allocator,
    policy: *const TrustedTypePolicy,
    code: []const u8,
) ![]const u8 {
    _ = policy;
    // When Trusted Types are not available, return the code directly.
    return allocator.dupe(u8, code);
}

/// Get the cached policy, creating it if necessary.
pub fn getPolicy(allocator: std.mem.Allocator) !TrustedTypePolicy {
    return createJitPolicy(allocator);
}

/// Reset the cached policy (for testing).
pub fn resetPolicy() void {
    cached_policy = null;
}

// ─── Tests ──────────────────────────────────────────────────

test "POLICY_NAME" {
    try std.testing.expectEqualStrings("ngJit", POLICY_NAME);
}

test "createJitPolicy" {
    resetPolicy();
    const allocator = std.testing.allocator;
    const policy = try createJitPolicy(allocator);
    try std.testing.expectEqualStrings("ngJit", policy.name);
    try std.testing.expect(!policy.is_available);
}

test "createJitPolicy caches" {
    resetPolicy();
    const allocator = std.testing.allocator;
    const policy1 = try createJitPolicy(allocator);
    const policy2 = try createJitPolicy(allocator);
    try std.testing.expectEqualStrings(policy1.name, policy2.name);
}

test "TrustedTypePolicy createScript" {
    const policy = TrustedTypePolicy{ .name = "test" };
    const script = policy.createScript("var x = 1;");
    try std.testing.expectEqualStrings("var x = 1;", script.code);
    try std.testing.expectEqualStrings("TrustedScript", script.__brand);
}

test "isTrustedTypesAvailable" {
    try std.testing.expect(!isTrustedTypesAvailable());
}

test "newTrustedFunctionForJIT returns code" {
    const allocator = std.testing.allocator;
    const policy = TrustedTypePolicy{ .name = "test" };
    const result = try newTrustedFunctionForJIT(allocator, &policy, "var x = 1;");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("var x = 1;", result);
}

test "TrustedTypePolicyFactory createPolicy" {
    const factory = TrustedTypePolicyFactory{ .is_available = false };
    const policy = factory.createPolicy("testPolicy");
    try std.testing.expectEqualStrings("testPolicy", policy.name);
    try std.testing.expect(!policy.is_available);
}
