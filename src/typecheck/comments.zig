/// TCB Comments — Comment trivia types for TCB
///
/// Port of: compiler/src/typecheck/typecheck/comments.ts (22 LoC)
const std = @import("std");

/// Comment trivia type for TCB comments.
pub const CommentTriviaType = enum { D, T };

/// Expression identifier for TCB comments.
pub const ExpressionIdentifier = enum { DIR, HOSTDIR, COMPCOMP, EP };
