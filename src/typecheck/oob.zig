/// TCB OOB — Out-of-band diagnostics
///
/// Port of: compiler/src/typecheck/oob.ts (236 LoC)
///
/// Generates "out-of-band" diagnostics — TypeScript errors that are reported
/// outside the normal TCB expression flow. These are used for template errors
/// that can't be expressed as regular type errors.
const std = @import("std");

/// OobDiagnostic — an out-of-band diagnostic message.
pub const OobDiagnostic = struct {
    category: DiagnosticCategory,
    code: u32,
    message: []const u8,
    file_path: ?[]const u8 = null,
    line: ?u32 = null,
    column: ?u32 = null,
};

/// DiagnosticCategory — mirrors TypeScript's DiagnosticCategory.
pub const DiagnosticCategory = enum(u8) {
    Warning,
    Error,
    Suggestion,
    Message,
};

/// OobError — common out-of-band error types.
pub const OobError = enum(u32) {
    /// A reference to a directive that is not exported.
    UnexportedDirective = 1001,
    /// A reference to a component that is not exported.
    UnexportedComponent = 1002,
    /// A pipe that is not exported.
    UnexportedPipe = 1003,
    /// A generic directive that requires type parameters.
    MissingTypeParameters = 1004,
    /// An illegal reference (e.g., referencing a template variable outside its scope).
    IllegalReference = 1005,
    /// A missing directive or component.
    MissingDirective = 1006,
    /// A sub-template that references an unknown variable.
    UnknownTemplateVariable = 1007,
};

/// Generate an out-of-band diagnostic for an unexported directive.
/// Direct port of the unexported directive check in the TS source.
pub fn unexportedDirectiveDiagnostic(
    allocator: std.mem.Allocator,
    dir_name: []const u8,
) !OobDiagnostic {
    _ = allocator;
    return .{
        .category = .Error,
        .code = @intFromEnum(OobError.UnexportedDirective),
        .message = dir_name,
    };
}

/// Generate an out-of-band diagnostic for a missing type parameter.
pub fn missingTypeParametersDiagnostic(
    allocator: std.mem.Allocator,
    dir_name: []const u8,
) !OobDiagnostic {
    _ = allocator;
    return .{
        .category = .Error,
        .code = @intFromEnum(OobError.MissingTypeParameters),
        .message = dir_name,
    };
}

/// Generate an out-of-band diagnostic for an illegal reference.
pub fn illegalReferenceDiagnostic(
    allocator: std.mem.Allocator,
    ref_name: []const u8,
    reason: []const u8,
) !OobDiagnostic {
    const msg = try std.fmt.allocPrint(allocator, "Illegal reference to '{s}': {s}", .{ ref_name, reason });
    return .{
        .category = .Error,
        .code = @intFromEnum(OobError.IllegalReference),
        .message = msg,
    };
}

/// Generate an out-of-band diagnostic for an unknown template variable.
pub fn unknownTemplateVariableDiagnostic(
    allocator: std.mem.Allocator,
    var_name: []const u8,
) !OobDiagnostic {
    const msg = try std.fmt.allocPrint(allocator, "Unknown template variable '{s}'", .{var_name});
    return .{
        .category = .Error,
        .code = @intFromEnum(OobError.UnknownTemplateVariable),
        .message = msg,
    };
}

/// Format a diagnostic as a string for display.
pub fn formatDiagnostic(
    allocator: std.mem.Allocator,
    diag: OobDiagnostic,
) ![]const u8 {
    const category_str: []const u8 = switch (diag.category) {
        .Warning => "warning",
        .Error => "error",
        .Suggestion => "suggestion",
        .Message => "message",
    };
    return std.fmt.allocPrint(allocator, "{s} TS{d}: {s}", .{
        category_str,
        diag.code,
        diag.message,
    });
}

// ─── Tests ──────────────────────────────────────────────────

test "unexportedDirectiveDiagnostic" {
    const allocator = std.testing.allocator;
    const diag = try unexportedDirectiveDiagnostic(allocator, "MyDirective");
    try std.testing.expectEqual(DiagnosticCategory.Error, diag.category);
    try std.testing.expectEqual(@intFromEnum(OobError.UnexportedDirective), diag.code);
}

test "illegalReferenceDiagnostic" {
    const allocator = std.testing.allocator;
    const diag = try illegalReferenceDiagnostic(allocator, "item", "out of scope");
    defer allocator.free(diag.message);
    try std.testing.expectEqual(DiagnosticCategory.Error, diag.category);
    try std.testing.expect(std.mem.indexOf(u8, diag.message, "item") != null);
}

test "formatDiagnostic" {
    const allocator = std.testing.allocator;
    const diag = OobDiagnostic{
        .category = .Error,
        .code = 1001,
        .message = "test error",
    };
    const formatted = try formatDiagnostic(allocator, diag);
    defer allocator.free(formatted);
    try std.testing.expectEqualStrings("error TS1001: test error", formatted);
}
