/// IR Shared Ops — ListEndOp, StatementOp, VariableOp, NEW_OP
///
/// Port of: compiler/src/template/pipeline/ir/src/ops/shared.ts (104 LoC)
const std = @import("std");
const ir_enums = @import("../enums.zig");
const OpKind = ir_enums.OpKind;
const operations = @import("../operations.zig");
const XrefId = operations.XrefId;

/// ListEndOp — special marker for head/tail of OpList.
pub const ListEndOp = struct {
    kind: OpKind = .ListEnd,
};

/// StatementOp — wraps an output AST statement.
pub fn StatementOp(comptime OpT: type) type {
    return struct {
        kind: OpKind = .Statement,
        xref: XrefId = 0,
        statement: []const u8 = "",
        source_span: ?@import("../../../../source_span.zig").AbsoluteSourceSpan = null,
        _phantom: ?*const OpT = null,
    };
}

/// Create a StatementOp.
pub fn createStatementOp(comptime OpT: type, statement: []const u8) StatementOp(OpT) {
    return .{ .statement = statement };
}

/// VariableOp — declares and initializes a SemanticVariable.
pub fn VariableOp(comptime OpT: type) type {
    return struct {
        kind: OpKind = .Variable,
        xref: XrefId = 0,
        variable: SemanticVariable = .{},
        initializer: []const u8 = "",
        flags: u8 = 0,
        source_span: ?@import("../../../../source_span.zig").AbsoluteSourceSpan = null,
        _phantom: ?*const OpT = null,
    };
}

/// SemanticVariable — describes the meaning behind a variable.
pub const SemanticVariable = struct {
    kind: u8 = 0, // SemanticVariableKind
    name: []const u8 = "",
    identifier: []const u8 = "",
    local: bool = false,
};

/// Create a VariableOp.
pub fn createVariableOp(comptime OpT: type, xref: XrefId, variable: SemanticVariable, initializer: []const u8, flags: u8) VariableOp(OpT) {
    return .{ .xref = xref, .variable = variable, .initializer = initializer, .flags = flags };
}

/// NEW_OP — default values for new ops (DOD: no-op in Zig, defaults are in struct).
pub const NEW_OP = struct {};
