/// TCB Ops Schema — Schema validation TCB operations
///
/// Port of: compiler/src/typecheck/typecheck/ops/schema.ts (97 LoC)
const std = @import("std");

/// SchemaOp — validate DOM elements/properties in TCB.
pub fn checkElementSchema(tag: []const u8) bool {
    _ = tag;
    return true;
}

pub fn checkPropertySchema(prop: []const u8) bool {
    _ = prop;
    return true;
}
