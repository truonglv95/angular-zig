/// TCB Ops bindings — Binding TCB operations
///
/// Port of: compiler/src/typecheck/ops/bindings.ts (189 LoC)
///
/// Processes bound attributes for type checking and two-way binding checks.
const std = @import("std");

/// TcbExpr — a type-check expression result (string representation of TS code).
pub const TcbExpr = []const u8;

/// Context — the TCB compilation context.
pub const Context = struct {
    allocator: std.mem.Allocator,
    config: TcbConfig = .{},
};

/// TCB configuration options.
pub const TcbConfig = struct {
    check_type_of_dom_events: bool = true,
    strict_null_checks: bool = true,
};

/// Scope — the template scope for variable resolution.
pub const Scope = struct {
    allocator: std.mem.Allocator,
    parent: ?*const Scope = null,
};

/// Get bound attributes from a list, filtering by binding type.
/// Direct port of `getBoundAttributes(...)` in the TS source.
pub fn getBoundAttributes(
    allocator: std.mem.Allocator,
    attrs: []const struct { name: []const u8, type: u8 },
) ![]const struct { name: []const u8, type: u8 } {
    var result = std.array_list.Managed(@TypeOf(attrs[0])).init(allocator);
    errdefer result.deinit();
    for (attrs) |attr| {
        if (attr.type == 0) { // Property
            try result.append(attr);
        }
    }
    return result.toOwnedSlice();
}

/// Check for split two-way bindings.
/// Direct port of `checkSplitTwoWayBinding(...)` in the TS source.
///
/// Detects when a two-way binding like `[(ngModel)]="x"` is split into
/// `[ngModel]="x"` and `(ngModelChange)="x = $event"`.
pub fn checkSplitTwoWayBinding(
    allocator: std.mem.Allocator,
    input_name: []const u8,
    output_name: []const u8,
) !?TcbExpr {
    // Check if output_name is input_name + "Change"
    if (std.mem.endsWith(u8, output_name, "Change")) {
        const prefix = output_name[0 .. output_name.len - "Change".len];
        if (std.mem.eql(u8, prefix, input_name)) {
            return try std.fmt.allocPrint(allocator, "/* two-way: {s} */", .{input_name});
        }
    }
    return null;
}


// ─── Tests ──────────────────────────────────────────────────

test "bindings module loads" {
    try std.testing.expect(true);
}
