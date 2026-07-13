/// TCB API — Type checking configuration interfaces
///
/// Port of: compiler/src/typecheck/typecheck/api.ts (291 LoC)
const std = @import("std");

/// TypeCheckingConfig — configuration for template type checking.
pub const TypeCheckingConfig = struct {
    strict_templates: bool = false,
    full_template_type_check: bool = true,
    strict_injection_parameters: bool = false,
    strict_literal_types: bool = false,
    strict_null_checks: bool = false,
    strict_dom_event_types: bool = false,
};

/// TcbEnvironment — shared environment for type check blocks.
pub const TcbEnvironment = struct {
    allocator: std.mem.Allocator,
    is_strict: bool = false,

    pub fn init(allocator: std.mem.Allocator, config: TypeCheckingConfig) TcbEnvironment {
        return .{ .allocator = allocator, .is_strict = config.strictTemplates };
    }
};

/// TcbDirectiveMetadata — metadata for a directive in the TCB.
pub const TcbDirectiveMetadata = struct {
    name: []const u8,
    selector: []const u8 = "",
    inputs: []const []const u8 = &.{},
    outputs: []const []const u8 = &.{},
    is_generic: bool = false,
};

/// TcbPipeMetadata — metadata for a pipe in the TCB.
pub const TcbPipeMetadata = struct {
    name: []const u8,
    pipe_name: []const u8,
};
