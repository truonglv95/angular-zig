/// TCB Ops Base — Base interface for TCB operations
///
/// Port of: compiler/src/typecheck/typecheck/ops/base.ts (55 LoC)
const std = @import("std");

/// TcbOp — base interface for type check block operations.
pub const TcbOp = struct {
    kind: TcbOpKind,
};

pub const TcbOpKind = enum(u8) {
    Scope,
    Expression,
    Inputs,
    Events,
    SignalForms,
    DirectiveConstructor,
    Template,
    Bindings,
    References,
    IfBlock,
    SwitchBlock,
    ForBlock,
    Variables,
    DirectiveType,
    ContentProjection,
    Let,
    Host,
    Element,
    Selectorless,
    IntersectionObserver,
    Schema,
    Context,
    Codegen,
    Completions,
};
