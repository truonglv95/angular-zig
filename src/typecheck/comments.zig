/// TCB Comments — Comment trivia types for TCB
///
/// Port of: compiler/src/typecheck/comments.ts (22 LoC)
///
/// Identifies what type a TCB comment is, and what a TCB expression
/// represents. These are used to mark expressions in the generated TCB
/// code so that diagnostics and completions can be attributed correctly.
const std = @import("std");

/// CommentTriviaType — identifies what type the comment is.
/// Direct port of `CommentTriviaType` enum in the TS source.
pub const CommentTriviaType = enum(u8) {
    /// Diagnostic comment — used to attribute errors to specific template locations.
    Diagnostic = 0,
    /// Expression type identifier — marks an expression with a specific type.
    ExpressionTypeIdentifier = 1,
};

/// Get the string representation of a CommentTriviaType.
pub fn commentTriviaTypeString(t: CommentTriviaType) []const u8 {
    return switch (t) {
        .Diagnostic => "D",
        .ExpressionTypeIdentifier => "T",
    };
}

/// ExpressionIdentifier — identifies what the TCB expression is for.
/// Direct port of `ExpressionIdentifier` enum in the TS source.
pub const ExpressionIdentifier = enum(u8) {
    /// Directive declaration.
    Directive = 0,
    /// Host directive declaration.
    HostDirective = 1,
    /// Component completion point.
    ComponentCompletion = 2,
    /// Event parameter ($event).
    EventParameter = 3,
    /// Variable used as an expression.
    VariableAsExpression = 4,
};

/// Get the string representation of an ExpressionIdentifier.
pub fn expressionIdentifierString(id: ExpressionIdentifier) []const u8 {
    return switch (id) {
        .Directive => "DIR",
        .HostDirective => "HOSTDIR",
        .ComponentCompletion => "COMPCOMP",
        .EventParameter => "EP",
        .VariableAsExpression => "VAE",
    };
}

/// Parse a string into an ExpressionIdentifier.
pub fn parseExpressionIdentifier(s: []const u8) ?ExpressionIdentifier {
    if (std.mem.eql(u8, s, "DIR")) return .Directive;
    if (std.mem.eql(u8, s, "HOSTDIR")) return .HostDirective;
    if (std.mem.eql(u8, s, "COMPCOMP")) return .ComponentCompletion;
    if (std.mem.eql(u8, s, "EP")) return .EventParameter;
    if (std.mem.eql(u8, s, "VAE")) return .VariableAsExpression;
    return null;
}

// ─── Tests ──────────────────────────────────────────────────

test "CommentTriviaType string" {
    try std.testing.expectEqualStrings("D", commentTriviaTypeString(.Diagnostic));
    try std.testing.expectEqualStrings("T", commentTriviaTypeString(.ExpressionTypeIdentifier));
}

test "ExpressionIdentifier string" {
    try std.testing.expectEqualStrings("DIR", expressionIdentifierString(.Directive));
    try std.testing.expectEqualStrings("HOSTDIR", expressionIdentifierString(.HostDirective));
    try std.testing.expectEqualStrings("COMPCOMP", expressionIdentifierString(.ComponentCompletion));
    try std.testing.expectEqualStrings("EP", expressionIdentifierString(.EventParameter));
    try std.testing.expectEqualStrings("VAE", expressionIdentifierString(.VariableAsExpression));
}

test "parseExpressionIdentifier" {
    try std.testing.expectEqual(ExpressionIdentifier.Directive, parseExpressionIdentifier("DIR").?);
    try std.testing.expectEqual(ExpressionIdentifier.HostDirective, parseExpressionIdentifier("HOSTDIR").?);
    try std.testing.expectEqual(ExpressionIdentifier.ComponentCompletion, parseExpressionIdentifier("COMPCOMP").?);
    try std.testing.expectEqual(ExpressionIdentifier.EventParameter, parseExpressionIdentifier("EP").?);
    try std.testing.expectEqual(ExpressionIdentifier.VariableAsExpression, parseExpressionIdentifier("VAE").?);
    try std.testing.expect(parseExpressionIdentifier("UNKNOWN") == null);
}
