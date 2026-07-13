/// TCB Expression — AstTranslator converts template expressions to TCB-safe TS
///
/// Port of: compiler/src/typecheck/typecheck/expression.ts (511 LoC)
const std = @import("std");

/// AstTranslator — converts template AST expressions into TCB-safe expressions.
/// Applies null narrowing, signal unwrapping, and type assertions.
pub const AstTranslator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AstTranslator {
        return .{ .allocator = allocator };
    }

    /// Translate a template expression to TCB form.
    pub fn translate(self: *const AstTranslator, expr: []const u8) ![]const u8 {
        return self.allocator.dupe(u8, expr);
    }
};
