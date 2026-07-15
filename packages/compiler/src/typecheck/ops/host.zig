/// TCB Ops Host — Host element TCB operation
///
/// Port of: compiler/src/typecheck/ops/host.ts (46 LoC)
///
/// A TcbOp which creates an expression for the host element of a directive.
/// Similar to TcbElementOp but for host elements, which can have multiple
/// possible tag names.
const std = @import("std");

/// TcbExpr — a type-check expression result.
pub const TcbExpr = []const u8;

/// TcbHostElementOp — generates a host element variable declaration.
/// Direct port of `TcbHostElementOp` class in the TS source.
pub const TcbHostElementOp = struct {
    allocator: std.mem.Allocator,
    /// Possible tag names for the host element.
    tag_names: []const []const u8,
    /// The host element's xref.
    element_xref: u32,
    /// Whether this op is optional.
    optional: bool = true,

    /// Execute the host element op.
    /// Direct port of `TcbHostElementOp.execute()` in the TS source.
    pub fn execute(self: *const TcbHostElementOp) !TcbExpr {
        if (self.tag_names.len == 1) {
            // Single tag: var _h1 = document.createElement("div")
            return std.fmt.allocPrint(
                self.allocator,
                "var _h{d} = document.createElement(\"{s}\")",
                .{ self.element_xref, self.tag_names[0] },
            );
        } else {
            // Multiple tags: var _h1 = document.createElement(null! as "div" | "span")
            var buf = std.array_list.Managed(u8).init(self.allocator);
            errdefer buf.deinit();
            const prefix = try std.fmt.allocPrint(self.allocator, "var _h{d} = document.createElement(null! as ", .{self.element_xref});
            defer self.allocator.free(prefix);
            try buf.appendSlice(prefix);
            for (self.tag_names, 0..) |tag, i| {
                if (i > 0) try buf.appendSlice(" | ");
                try buf.append('"');
                try buf.appendSlice(tag);
                try buf.append('"');
            }
            try buf.append(')');
            return buf.toOwnedSlice();
        }
    }

    /// Get the variable name for this host element.
    pub fn getVarName(self: *const TcbHostElementOp) !TcbExpr {
        return std.fmt.allocPrint(self.allocator, "_h{d}", .{self.element_xref});
    }
};

// ─── Tests ──────────────────────────────────────────────────

test "TcbHostElementOp execute single tag" {
    const allocator = std.testing.allocator;
    const tags = [_][]const u8{"div"};
    const op = TcbHostElementOp{
        .allocator = allocator,
        .tag_names = &tags,
        .element_xref = 1,
    };
    const result = try op.execute();
    defer allocator.free(result);
    try std.testing.expectEqualStrings("var _h1 = document.createElement(\"div\")", result);
}

test "TcbHostElementOp execute multiple tags" {
    const allocator = std.testing.allocator;
    const tags = [_][]const u8{ "div", "span" };
    const op = TcbHostElementOp{
        .allocator = allocator,
        .tag_names = &tags,
        .element_xref = 2,
    };
    const result = try op.execute();
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"div\" | \"span\"") != null);
}

test "TcbHostElementOp getVarName" {
    const allocator = std.testing.allocator;
    const tags = [_][]const u8{"div"};
    const op = TcbHostElementOp{
        .allocator = allocator,
        .tag_names = &tags,
        .element_xref = 5,
    };
    const result = try op.getVarName();
    defer allocator.free(result);
    try std.testing.expectEqualStrings("_h5", result);
}
