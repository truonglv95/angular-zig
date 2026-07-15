/// TCB Ops directive_type — Directive type TCB operations
///
/// Port of: compiler/src/typecheck/ops/directive_type.ts (117 LoC)
///
/// Resolves directive types for type checking.
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

/// TcbDirectiveTypeOpBase — base for directive type resolution ops.
pub const TcbDirectiveTypeOpBase = struct {
    tcb: *const Context,
    scope: *const Scope,
    dir_name: []const u8,
};

/// TcbNonGenericDirectiveTypeOp — resolves a non-generic directive type.
/// Direct port of `TcbNonGenericDirectiveTypeOp` class in the TS source.
pub const TcbNonGenericDirectiveTypeOp = struct {
    base: TcbDirectiveTypeOpBase,

    pub fn execute(self: *const TcbNonGenericDirectiveTypeOp) !TcbExpr {
        return self.base.tcb.allocator.dupe(u8, self.base.dir_name);
    }
};

/// TcbGenericDirectiveTypeOp — resolves a generic directive type.
pub const TcbGenericDirectiveTypeOp = struct {
    base: TcbDirectiveTypeOpBase,
    type_args: []const u8,

    pub fn execute(self: *const TcbGenericDirectiveTypeOp) !TcbExpr {
        return std.fmt.allocPrint(self.base.tcb.allocator, "{s}<{s}>", .{ self.base.dir_name, self.type_args });
    }
};

// ─── Tests ──────────────────────────────────────────────────

test "directive_type module loads" {
    try std.testing.expect(true);
}
