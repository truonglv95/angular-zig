/// TCB Ops Intersection Observer — IntersectionObserver TCB operation
///
/// Port of: compiler/src/typecheck/ops/intersection_observer.ts (35 LoC)
///
/// A TcbOp which type-checks the options of an IntersectionObserver.
/// This is used for @defer viewport triggers.
const std = @import("std");

/// TcbExpr — a type-check expression result.
pub const TcbExpr = []const u8;

/// TcbIntersectionObserverOp — type-checks IntersectionObserver options.
/// Direct port of `TcbIntersectionObserverOp` class in the TS source.
pub const TcbIntersectionObserverOp = struct {
    allocator: std.mem.Allocator,
    /// The options expression for the IntersectionObserver.
    options_expr: []const u8,
    /// Whether this op is optional.
    optional: bool = false,

    /// Execute the IntersectionObserver op.
    /// Direct port of `TcbIntersectionObserverOp.execute()` in the TS source.
    ///
    /// Generates: `new IntersectionObserver(null!, optionsExpression)`
    pub fn execute(self: *const TcbIntersectionObserverOp) !TcbExpr {
        return std.fmt.allocPrint(
            self.allocator,
            "new IntersectionObserver(null!, {s})",
            .{self.options_expr},
        );
    }
};

// ─── Tests ──────────────────────────────────────────────────

test "TcbIntersectionObserverOp execute" {
    const allocator = std.testing.allocator;
    const op = TcbIntersectionObserverOp{
        .allocator = allocator,
        .options_expr = "{ root: null }",
    };
    const result = try op.execute();
    defer allocator.free(result);
    try std.testing.expectEqualStrings("new IntersectionObserver(null!, { root: null })", result);
}

test "TcbIntersectionObserverOp is mandatory" {
    const allocator = std.testing.allocator;
    const op = TcbIntersectionObserverOp{
        .allocator = allocator,
        .options_expr = "{}",
    };
    try std.testing.expect(!op.optional);
}
