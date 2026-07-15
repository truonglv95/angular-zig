/// TCB Ops Element — Element TCB operation
///
/// Port of: compiler/src/typecheck/ops/element.ts (50 LoC)
///
/// A TcbOp which creates an expression for a native DOM element (or web
/// component) from an Element node. It generates a `document.createElement()`
/// call and adds it as a statement to the scope.
const std = @import("std");

/// TcbExpr — a type-check expression result.
pub const TcbExpr = []const u8;

/// TcbElementOp — generates a DOM element variable declaration.
/// Direct port of `TcbElementOp` class in the TS source.
pub const TcbElementOp = struct {
    allocator: std.mem.Allocator,
    /// The element's tag name.
    tag_name: []const u8,
    /// The element's xref (for variable naming).
    element_xref: u32,
    /// Whether this op is optional (can be skipped if unused).
    optional: bool = true,

    /// Execute the element op.
    /// Direct port of `TcbElementOp.execute()` in the TS source.
    ///
    /// Generates: `var _t1 = document.createElement("div");`
    /// Returns the variable name `_t1`.
    pub fn execute(self: *const TcbElementOp) !TcbExpr {
        return std.fmt.allocPrint(
            self.allocator,
            "var _e{d} = document.createElement(\"{s}\")",
            .{ self.element_xref, self.tag_name },
        );
    }

    /// Get the variable name for this element.
    pub fn getVarName(self: *const TcbElementOp) !TcbExpr {
        return std.fmt.allocPrint(self.allocator, "_e{d}", .{self.element_xref});
    }
};

// ─── Tests ──────────────────────────────────────────────────

test "TcbElementOp execute" {
    const allocator = std.testing.allocator;
    const op = TcbElementOp{
        .allocator = allocator,
        .tag_name = "div",
        .element_xref = 1,
    };
    const result = try op.execute();
    defer allocator.free(result);
    try std.testing.expectEqualStrings("var _e1 = document.createElement(\"div\")", result);
}

test "TcbElementOp getVarName" {
    const allocator = std.testing.allocator;
    const op = TcbElementOp{
        .allocator = allocator,
        .tag_name = "span",
        .element_xref = 42,
    };
    const result = try op.getVarName();
    defer allocator.free(result);
    try std.testing.expectEqualStrings("_e42", result);
}

test "TcbElementOp optional is true" {
    const allocator = std.testing.allocator;
    const op = TcbElementOp{
        .allocator = allocator,
        .tag_name = "div",
        .element_xref = 0,
    };
    try std.testing.expect(op.optional);
}
