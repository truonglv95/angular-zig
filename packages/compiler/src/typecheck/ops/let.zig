/// TCB Ops Let — @let declaration TCB operation
///
/// Port of: compiler/src/typecheck/ops/let.ts (44 LoC)
///
/// A TcbOp which generates a constant declaration for a @let declaration.
/// @let declarations are mandatory — their expressions should be checked
/// even if they aren't referenced anywhere.
const std = @import("std");

/// TcbExpr — a type-check expression result.
pub const TcbExpr = []const u8;

/// TcbLetDeclarationOp — generates a constant for a @let declaration.
/// Direct port of `TcbLetDeclarationOp` class in the TS source.
pub const TcbLetDeclarationOp = struct {
    allocator: std.mem.Allocator,
    /// The name of the @let variable.
    name: []const u8,
    /// The value expression of the @let declaration.
    value: []const u8,
    /// The xref for variable naming.
    let_xref: u32,
    /// Whether this op is optional. @let declarations are mandatory.
    optional: bool = false,

    /// Execute the @let declaration op.
    /// Direct port of `TcbLetDeclarationOp.execute()` in the TS source.
    ///
    /// Generates: `const _l1 = valueExpression`
    pub fn execute(self: *const TcbLetDeclarationOp) !TcbExpr {
        return std.fmt.allocPrint(
            self.allocator,
            "const _l{d} = {s}",
            .{ self.let_xref, self.value },
        );
    }

    /// Get the variable name for this @let declaration.
    pub fn getVarName(self: *const TcbLetDeclarationOp) !TcbExpr {
        return std.fmt.allocPrint(self.allocator, "_l{d}", .{self.let_xref});
    }
};

// ─── Tests ──────────────────────────────────────────────────

test "TcbLetDeclarationOp execute" {
    const allocator = std.testing.allocator;
    const op = TcbLetDeclarationOp{
        .allocator = allocator,
        .name = "myLet",
        .value = "1 + 2",
        .let_xref = 1,
    };
    const result = try op.execute();
    defer allocator.free(result);
    try std.testing.expectEqualStrings("const _l1 = 1 + 2", result);
}

test "TcbLetDeclarationOp getVarName" {
    const allocator = std.testing.allocator;
    const op = TcbLetDeclarationOp{
        .allocator = allocator,
        .name = "myLet",
        .value = "expr",
        .let_xref = 3,
    };
    const result = try op.getVarName();
    defer allocator.free(result);
    try std.testing.expectEqualStrings("_l3", result);
}

test "TcbLetDeclarationOp is mandatory" {
    const allocator = std.testing.allocator;
    const op = TcbLetDeclarationOp{
        .allocator = allocator,
        .name = "myLet",
        .value = "expr",
        .let_xref = 0,
    };
    try std.testing.expect(!op.optional);
}
