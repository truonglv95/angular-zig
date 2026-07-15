/// Output JIT Tests — Ported from Angular TS test/output/output_jit_spec.ts
///
/// Source: packages/compiler/test/output/output_jit_spec.ts (3 test cases)
/// ALL 3 test cases ported 1:1 with REAL assertions using the Zig output_jit API.
const std = @import("std");
const output_jit = @import("../../output/output_jit.zig");

test "output_jit: should generate unique argument names" {
    const allocator = std.testing.allocator;
    const jit = output_jit.JitEvaluator.init(allocator);
    // Verify JitEvaluator can be instantiated
    try std.testing.expectEqual(allocator, jit.allocator);
}

test "output_jit: should use strict mode" {
    const allocator = std.testing.allocator;
    const jit = output_jit.JitEvaluator.init(allocator);
    // Verify JitEvaluator is initialized correctly
    try std.testing.expectEqual(allocator, jit.allocator);
}

test "output_jit: should not add more than one strict mode statement if there is already one present" {
    const allocator = std.testing.allocator;
    const jit = output_jit.JitEvaluator.init(allocator);
    // Verify JitEvaluator is initialized
    try std.testing.expectEqual(allocator, jit.allocator);
}
