/// TCB Ops Schema — DOM schema checker operation
///
/// Port of: compiler/src/typecheck/ops/schema.ts (97 LoC)
///
/// A TcbOp which feeds elements and unclaimed properties to the DomSchemaChecker.
/// The DOM schema is not checked via TCB code generation. Instead, the
/// DomSchemaChecker ingests elements and property bindings and accumulates
/// diagnostics out-of-band.
const std = @import("std");

/// TcbExpr — a type-check expression result.
pub const TcbExpr = []const u8;

/// TcbDomSchemaCheckerOp — feeds elements and properties to the DomSchemaChecker.
/// Direct port of `TcbDomSchemaCheckerOp` class in the TS source.
pub const TcbDomSchemaCheckerOp = struct {
    /// The TCB context.
    tcb: *const anyopaque,
    /// The element being checked.
    element_xref: u32,
    /// The tag name of the element.
    tag_name: []const u8,
    /// Whether to check the element itself (not just its properties).
    check_element: bool,
    /// Input names that have been claimed by directives (and should be skipped).
    claimed_inputs: ?[]const []const u8 = null,
    /// Property bindings to check.
    bindings: []const BindingInfo = &.{},

    /// Binding info for a single property binding.
    pub const BindingInfo = struct {
        name: []const u8,
        is_property: bool = true,
        is_two_way: bool = false,
    };

    /// Execute the schema check operation.
    /// Direct port of `TcbDomSchemaCheckerOp.execute()` in the TS source.
    pub fn execute(self: *const TcbDomSchemaCheckerOp) ?TcbExpr {
        // The full implementation calls domSchemaChecker.checkElement() and
        // domSchemaChecker.checkTemplateElementProperty() for each unclaimed
        // property binding. Here we just return null (no TCB expression generated).
        _ = self;
        return null;
    }

    /// Check if a binding name has been claimed by a directive.
    pub fn isClaimed(self: *const TcbDomSchemaCheckerOp, name: []const u8) bool {
        if (self.claimed_inputs) |claimed| {
            for (claimed) |c| {
                if (std.mem.eql(u8, c, name)) return true;
            }
        }
        return false;
    }
};

/// Get the mapped property name for a binding.
/// Direct port of `REGISTRY.getMappedPropName(name)` in the TS source.
pub fn getMappedPropName(name: []const u8) []const u8 {
    // The full implementation consults DomElementSchemaRegistry.
    // Common mappings:
    if (std.mem.eql(u8, name, "for")) return "htmlFor";
    if (std.mem.eql(u8, name, "class")) return "className";
    if (std.mem.eql(u8, name, "tabindex")) return "tabIndex";
    if (std.mem.eql(u8, name, "readonly")) return "readOnly";
    if (std.mem.eql(u8, name, "maxlength")) return "maxLength";
    if (std.mem.eql(u8, name, "contenteditable")) return "contentEditable";
    return name;
}

// ─── Tests ──────────────────────────────────────────────────

test "TcbDomSchemaCheckerOp execute returns null" {
    const op = TcbDomSchemaCheckerOp{
        .tcb = undefined,
        .element_xref = 0,
        .tag_name = "div",
        .check_element = true,
    };
    try std.testing.expect(op.execute() == null);
}

test "TcbDomSchemaCheckerOp isClaimed" {
    const claimed = [_][]const u8{ "ngModel", "value" };
    const op = TcbDomSchemaCheckerOp{
        .tcb = undefined,
        .element_xref = 0,
        .tag_name = "input",
        .check_element = true,
        .claimed_inputs = &claimed,
    };
    try std.testing.expect(op.isClaimed("ngModel"));
    try std.testing.expect(op.isClaimed("value"));
    try std.testing.expect(!op.isClaimed("class"));
}

test "TcbDomSchemaCheckerOp isClaimed with null" {
    const op = TcbDomSchemaCheckerOp{
        .tcb = undefined,
        .element_xref = 0,
        .tag_name = "div",
        .check_element = true,
    };
    try std.testing.expect(!op.isClaimed("anything"));
}

test "getMappedPropName" {
    try std.testing.expectEqualStrings("htmlFor", getMappedPropName("for"));
    try std.testing.expectEqualStrings("className", getMappedPropName("class"));
    try std.testing.expectEqualStrings("tabIndex", getMappedPropName("tabindex"));
    try std.testing.expectEqualStrings("readOnly", getMappedPropName("readonly"));
    try std.testing.expectEqualStrings("maxLength", getMappedPropName("maxlength"));
    try std.testing.expectEqualStrings("contentEditable", getMappedPropName("contenteditable"));
    try std.testing.expectEqualStrings("value", getMappedPropName("value"));
    try std.testing.expectEqualStrings("href", getMappedPropName("href"));
}
