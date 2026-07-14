/// TCB Ops Selectorless — Component node TCB operation (selectorless mode)
///
/// Port of: compiler/src/typecheck/ops/selectorless.ts (47 LoC)
///
/// In selectorless mode, components are matched by their class name rather
/// than a CSS selector. This module generates element variables for component
/// nodes.
const std = @import("std");

/// TcbExpr — a type-check expression result.
pub const TcbExpr = []const u8;

/// Get the tag name for a component node.
/// Direct port of `getComponentTagName(node)` in the TS source.
///
/// Falls back to `ng-component` if the component doesn't have a tag name.
pub fn getComponentTagName(tag_name: ?[]const u8) []const u8 {
    if (tag_name) |name| {
        if (name.len > 0) return name;
    }
    return "ng-component";
}

/// TcbComponentNodeOp — generates a DOM element for a component node.
/// Direct port of `TcbComponentNodeOp` class in the TS source.
pub const TcbComponentNodeOp = struct {
    allocator: std.mem.Allocator,
    /// The component's tag name (or null for ng-component).
    tag_name: ?[]const u8,
    /// The component's xref.
    component_xref: u32,
    /// Whether this op is optional.
    optional: bool = true,

    /// Execute the component node op.
    /// Direct port of `TcbComponentNodeOp.execute()` in the TS source.
    pub fn execute(self: *const TcbComponentNodeOp) !TcbExpr {
        const tag = getComponentTagName(self.tag_name);
        return std.fmt.allocPrint(
            self.allocator,
            "var _c{d} = document.createElement(\"{s}\")",
            .{ self.component_xref, tag },
        );
    }

    /// Get the variable name for this component node.
    pub fn getVarName(self: *const TcbComponentNodeOp) !TcbExpr {
        return std.fmt.allocPrint(self.allocator, "_c{d}", .{self.component_xref});
    }
};

// ─── Tests ──────────────────────────────────────────────────

test "getComponentTagName with name" {
    try std.testing.expectEqualStrings("app-root", getComponentTagName("app-root"));
    try std.testing.expectEqualStrings("my-comp", getComponentTagName("my-comp"));
}

test "getComponentTagName fallback" {
    try std.testing.expectEqualStrings("ng-component", getComponentTagName(null));
    try std.testing.expectEqualStrings("ng-component", getComponentTagName(""));
}

test "TcbComponentNodeOp execute with tag name" {
    const allocator = std.testing.allocator;
    const op = TcbComponentNodeOp{
        .allocator = allocator,
        .tag_name = "app-root",
        .component_xref = 1,
    };
    const result = try op.execute();
    defer allocator.free(result);
    try std.testing.expectEqualStrings("var _c1 = document.createElement(\"app-root\")", result);
}

test "TcbComponentNodeOp execute without tag name" {
    const allocator = std.testing.allocator;
    const op = TcbComponentNodeOp{
        .allocator = allocator,
        .tag_name = null,
        .component_xref = 2,
    };
    const result = try op.execute();
    defer allocator.free(result);
    try std.testing.expectEqualStrings("var _c2 = document.createElement(\"ng-component\")", result);
}

test "TcbComponentNodeOp getVarName" {
    const allocator = std.testing.allocator;
    const op = TcbComponentNodeOp{
        .allocator = allocator,
        .tag_name = null,
        .component_xref = 7,
    };
    const result = try op.getVarName();
    defer allocator.free(result);
    try std.testing.expectEqualStrings("_c7", result);
}
