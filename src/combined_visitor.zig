/// Combined Visitor — Walks both HTML AST and Expression AST
///
/// Port of: compiler/src/combined_visitor.ts
const std = @import("std");

/// A visitor that can visit both HTML AST nodes and expression AST nodes.
/// Used for combined traversals.
pub const CombinedVisitor = struct {};
