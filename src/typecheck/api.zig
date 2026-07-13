/// TCB API — Type checking configuration interfaces and metadata types
///
/// Port of: compiler/src/typecheck/api.ts (291 LoC)
///
/// Defines the core interfaces and types used by the type check block (TCB)
/// system for type-checking Angular templates.
const std = @import("std");

/// TypeCheckingConfig — configuration for template type checking.
/// Direct port of the config interfaces in the TS source.
pub const TypeCheckingConfig = struct {
    strict_templates: bool = false,
    full_template_type_check: bool = true,
    strict_injection_parameters: bool = false,
    strict_literal_types: bool = false,
    strict_null_checks: bool = false,
    strict_dom_event_types: bool = false,
    strict_input_types: bool = true,
    strict_output_event_types: bool = true,
    strict_attribute_types: bool = false,
    strict_safe_navigation_types: bool = false,
    strict_function_types: bool = false,
};

/// TypeCtorMetadata — metadata for a type constructor function.
/// Direct port of `TypeCtorMetadata` interface in the TS source.
pub const TypeCtorMetadata = struct {
    fn_name: []const u8,
    body: bool,
    coerced_input_fields: []const []const u8 = &.{},
};

/// TcbReferenceMetadata — metadata about a referenced class/symbol.
/// Direct port of `TcbReferenceMetadata` interface in the TS source.
pub const TcbReferenceMetadata = struct {
    name: []const u8,
    module_name: ?[]const u8 = null,
    is_local: bool = false,
    unexported_diagnostic: ?[]const u8 = null,
    key: []const u8 = "",
};

/// TcbReferenceKey — branded string type for unique reference identification.
pub const TcbReferenceKey = []const u8;

/// TcbTypeParameter — a type parameter for generic directives.
/// Direct port of `TcbTypeParameter` interface in the TS source.
pub const TcbTypeParameter = struct {
    name: []const u8,
    representation: []const u8,
    representation_with_default: []const u8,
};

/// TcbInputMapping — maps a template input name to a class property.
/// Direct port of `TcbInputMapping` type in the TS source.
pub const TcbInputMapping = struct {
    class_property_name: []const u8,
    binding_property_name: []const u8,
    is_signal: bool = false,
    required: bool = false,
    transform_type: ?[]const u8 = null,
};

/// TcbPipeMetadata — metadata for a pipe used in the TCB.
/// Direct port of `TcbPipeMetadata` interface in the TS source.
pub const TcbPipeMetadata = struct {
    name: []const u8,
    ref: TcbReferenceMetadata,
    is_explicitly_deferred: bool = false,
};

/// TemplateGuardMeta — describes a template guard for a directive input.
/// Direct port of `TemplateGuardMeta` interface in the TS source.
pub const TemplateGuardMeta = struct {
    input_name: []const u8,
    type: GuardType,
    ng_template_guard: ?[]const u8 = null,

    pub const GuardType = enum { invocation, binding };
};

/// TcbDirectiveMetadata — metadata for a directive in the TCB.
/// Direct port of `TcbDirectiveMetadata` interface in the TS source.
pub const TcbDirectiveMetadata = struct {
    name: []const u8,
    selector: []const u8 = "",
    is_generic: bool = false,
    inputs: []const TcbInputMapping = &.{},
    outputs: []const []const u8 = &.{},
    type_parameters: []const TcbTypeParameter = &.{},
    template_guard: ?TemplateGuardMeta = null,
    coerced_input_fields: []const []const u8 = &.{},
    is_host_directive: bool = false,
};

/// TcbEnvironment — shared environment for type check blocks.
/// Direct port of `TcbEnvironment` in the TS source.
pub const TcbEnvironment = struct {
    allocator: std.mem.Allocator,
    config: TypeCheckingConfig,
    is_strict: bool = false,

    pub fn init(allocator: std.mem.Allocator, config: TypeCheckingConfig) TcbEnvironment {
        return .{
            .allocator = allocator,
            .config = config,
            .is_strict = config.strict_templates,
        };
    }

    /// Check if a specific strictness mode is enabled.
    pub fn isStrictMode(self: *const TcbEnvironment) bool {
        return self.is_strict;
    }
};

/// TypeCtorPending — a pending type constructor call.
pub const TypeCtorPending = struct {
    metadata: TypeCtorMetadata,
    type_args: []const []const u8 = &.{},
};

// ─── Tests ──────────────────────────────────────────────────

test "TypeCheckingConfig defaults" {
    const config = TypeCheckingConfig{};
    try std.testing.expect(!config.strict_templates);
    try std.testing.expect(config.full_template_type_check);
    try std.testing.expect(!config.strict_null_checks);
}

test "TcbEnvironment init" {
    const allocator = std.testing.allocator;
    const config = TypeCheckingConfig{ .strict_templates = true };
    const env = TcbEnvironment.init(allocator, config);
    try std.testing.expect(env.is_strict);
    try std.testing.expect(env.isStrictMode());
}

test "TcbDirectiveMetadata defaults" {
    const meta = TcbDirectiveMetadata{ .name = "MyDirective" };
    try std.testing.expectEqualStrings("MyDirective", meta.name);
    try std.testing.expectEqual(@as(usize, 0), meta.inputs.len);
    try std.testing.expect(!meta.is_generic);
}
