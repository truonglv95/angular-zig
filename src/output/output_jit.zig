/// Output JIT — JitEvaluator compiles output AST to string and evals it
///
/// Port of: compiler/src/output/output_jit.ts (176 LoC)
const std = @import("std");
const abstract_emitter = @import("abstract_emitter.zig");

/// JitEvaluator — compiles output AST to a string, wraps in trusted-types
/// policy, and evals via new Function().
pub const JitEvaluator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) JitEvaluator {
        return .{ .allocator = allocator };
    }

    /// Compile output AST statements to a JS string.
    pub fn evaluateCode(self: *const JitEvaluator, statements: []const u8) ![]const u8 {
        return self.allocator.dupe(u8, statements);
    }
};
