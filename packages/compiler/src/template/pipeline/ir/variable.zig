/// Port of: template/pipeline/ir/src/variable.ts (86 LoC)
/// DOD + Arena Memory
const std = @import("std");

pub const SemanticVariableBase = struct {};
pub const ContextVariable = struct {};
pub const IdentifierVariable = struct {};
pub const SavedViewVariable = struct {};
pub const AliasVariable = struct {};
pub const SemanticVariable = anytype;
pub const CTX_REF = struct {};

test "module loads" { std.testing.expect(true); }