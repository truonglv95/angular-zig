/// TCB Ops Completions — IDE completion support TCB ops
///
/// Port of: compiler/src/typecheck/typecheck/ops/completions.ts (35 LoC)
const std = @import("std");

/// CompletionOp — provide IDE completion data from TCB.
pub const CompletionKind = enum { Property, Method, Event, Directive };

pub const Completion = struct {
    kind: CompletionKind,
    name: []const u8,
    type_name: []const u8 = "",
};
