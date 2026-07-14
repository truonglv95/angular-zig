/// TCB API — Type checking configuration interfaces and metadata types
///
/// Port of: compiler/src/typecheck/api.ts (291 LoC)
///
/// Defines the core interfaces and types used by the type check block (TCB)
/// system for type-checking Angular templates. These types describe:
///   - Configuration options for type checking strictness
///   - Metadata for directives, components, pipes, and references
///   - The environment needed for TCB generation
///   - Type constructor metadata
const std = @import("std");

// ─── TypeCheckingConfig ─────────────────────────────────────

/// TypeCheckingConfig — configuration for template type checking.
/// Direct port of `TypeCheckingConfig` interface in the TS source.
///
/// Controls various aspects of how Angular templates are type-checked,
/// including strictness levels, which bindings to check, and how
/// control flow is handled.
pub const TypeCheckingConfig = struct {
    /// Whether to check the left-hand side type of binding operations.
    check_type_of_input_bindings: bool = true,

    /// Whether to honor access modifiers on input bindings.
    honor_access_modifiers_for_input_bindings: bool = false,

    /// Whether to use strict null types for input bindings.
    strict_null_input_bindings: bool = true,

    /// Whether to check text attributes consumed by directives.
    check_type_of_attributes: bool = true,

    /// Whether to check the left-hand side type of DOM property bindings.
    check_type_of_dom_bindings: bool = true,

    /// Whether to infer the type of `$event` in directive output event bindings.
    check_type_of_output_events: bool = true,

    /// Whether to infer the type of `$event` in animation event bindings.
    check_type_of_animation_events: bool = true,

    /// Whether to infer the type of `$event` in DOM event bindings.
    check_type_of_dom_events: bool = true,

    /// Whether to infer the type of local references to DOM elements.
    check_type_of_dom_references: bool = true,

    /// Whether to infer the type of local references to non-DOM elements.
    check_type_of_non_dom_references: bool = true,

    /// Whether to adjust TCB output for TemplateTypeChecker compatibility.
    enable_template_type_checker: bool = false,

    /// Whether to include type information from pipes.
    check_type_of_pipes: bool = true,

    /// Whether to narrow types of template contexts.
    apply_template_context_guards: bool = true,

    /// Whether to use strict types for null-safe navigation.
    strict_safe_navigation_types: bool = false,

    /// Whether to descend into template bodies and check bindings.
    check_template_bodies: bool = true,

    /// Whether to always apply DOM schema checks in template bodies.
    always_check_schema_in_template_bodies: bool = false,

    /// Whether to check resolvable queries.
    check_queries: bool = false,

    /// How to handle control flow preventing content projection.
    control_flow_preventing_content_projection: ControlFlowContentProjection = .suppress,

    /// How to handle unused standalone imports.
    unused_standalone_imports: UnusedStandaloneImports = .suppress,

    /// Whether to use any generic types of the context component.
    use_context_generic_type: bool = false,

    /// Whether to infer types for object and array literals.
    strict_literal_types: bool = false,

    /// Whether to use inline type constructors.
    use_inline_type_constructors: bool = false,

    /// Whether to allow WritableSignal in two-way bindings.
    allow_signals_in_two_way_bindings: bool = false,

    /// Whether to assert DOM event types with ɵassertType.
    allow_dom_event_assertion: bool = false,

    /// Whether to descend into control flow block bodies (@if, @switch, @for).
    check_control_flow_bodies: bool = true,

    // ─── Legacy fields (backwards compat) ────────────────────
    strict_templates: bool = false,
    full_template_type_check: bool = true,
    strict_injection_parameters: bool = false,
    strict_null_checks: bool = false,
    strict_dom_event_types: bool = false,
    strict_input_types: bool = true,
    strict_output_event_types: bool = true,
    strict_attribute_types: bool = false,
    strict_function_types: bool = false,
};

/// Control flow content projection checking mode.
pub const ControlFlowContentProjection = enum {
    err,
    warning,
    suppress,
};

/// Unused standalone imports checking mode.
pub const UnusedStandaloneImports = enum {
    err,
    warning,
    suppress,
};

// ─── TypeCtorMetadata ───────────────────────────────────────

/// TypeCtorMetadata — metadata for a type constructor function.
/// Direct port of `TypeCtorMetadata` interface in the TS source.
pub const TypeCtorMetadata = struct {
    /// The name of the requested type constructor function.
    fn_name: []const u8,
    /// Whether to generate a body for the function or not.
    body: bool,
    /// Input, output, and query field names included as constructor input.
    fields: TypeCtorFields = .{},
    /// Set of field names which have type coercion enabled.
    coerced_input_fields: []const []const u8 = &.{},
};

/// Fields included in a type constructor.
pub const TypeCtorFields = struct {
    inputs: []const TcbInputMapping = &.{},
};

// ─── TcbReferenceMetadata ───────────────────────────────────

/// TcbReferenceMetadata — metadata about a referenced class/symbol.
/// Direct port of `TcbReferenceMetadata` interface in the TS source.
pub const TcbReferenceMetadata = struct {
    /// The name of the class.
    name: []const u8,
    /// The module path where the symbol is located, or null if local/ambient.
    module_name: ?[]const u8 = null,
    /// True if the symbol successfully emitted locally (no external import required).
    is_local: bool = false,
    /// If the reference could not be externally emitted, this holds the diagnostic reason.
    unexported_diagnostic: ?[]const u8 = null,
    /// Key used to uniquely identify the target of this reference.
    key: TcbReferenceKey = "",
    /// Defines the AbsoluteSourceSpan of the target's node name, if available.
    node_name_span: ?AbsoluteSourceSpan = null,
    /// The absolute path to the file containing the reference node, if available.
    node_file_path: ?[]const u8 = null,
};

/// TcbReferenceKey — branded string type for unique reference identification.
pub const TcbReferenceKey = []const u8;

/// AbsoluteSourceSpan — byte offset pair for source spans.
pub const AbsoluteSourceSpan = struct {
    start: u32,
    end: u32,
};

// ─── TcbTypeParameter ───────────────────────────────────────

/// TcbTypeParameter — a type parameter for generic directives.
/// Direct port of `TcbTypeParameter` interface in the TS source.
pub const TcbTypeParameter = struct {
    name: []const u8,
    representation: []const u8,
    representation_with_default: []const u8,
};

// ─── TcbInputMapping ────────────────────────────────────────

/// TcbInputMapping — maps a template input name to a class property.
/// Direct port of `TcbInputMapping` type in the TS source.
pub const TcbInputMapping = struct {
    class_property_name: []const u8,
    binding_property_name: []const u8,
    is_signal: bool = false,
    required: bool = false,
    /// AST-free string representation of the transform type, if available.
    transform_type: ?[]const u8 = null,
};

// ─── TcbPipeMetadata ────────────────────────────────────────

/// TcbPipeMetadata — metadata for a pipe used in the TCB.
/// Direct port of `TcbPipeMetadata` interface in the TS source.
pub const TcbPipeMetadata = struct {
    name: []const u8,
    ref: TcbReferenceMetadata,
    is_explicitly_deferred: bool = false,
};

// ─── TemplateGuardMeta ──────────────────────────────────────

/// TemplateGuardMeta — describes a template guard for a directive input.
/// Direct port of `TemplateGuardMeta` interface in the TS source.
pub const TemplateGuardMeta = struct {
    /// The input name that this guard should be applied to.
    input_name: []const u8,
    /// The type of the template guard.
    type: GuardType,

    pub const GuardType = enum {
        /// A call to the template guard function is emitted for type narrowing.
        invocation,
        /// The input binding expression itself is used as the template guard.
        binding,
    };
};

// ─── MatchSource ────────────────────────────────────────────

/// MatchSource — how a directive was matched to a node.
pub const MatchSource = enum {
    /// Matched by selector.
    selector,
    /// Matched as a host directive.
    host_directive,
    /// Matched by selectorless syntax.
    selectorless,
};

// ─── TcbDirectiveMetadata ───────────────────────────────────

/// TcbDirectiveMetadata — metadata for a directive in the TCB.
/// Direct port of `TcbDirectiveMetadata` interface in the TS source.
pub const TcbDirectiveMetadata = struct {
    ref: TcbReferenceMetadata = .{ .name = "" },
    name: []const u8,
    selector: ?[]const u8 = null,
    is_component: bool = false,
    is_generic: bool = false,
    is_structural: bool = false,
    is_standalone: bool = false,
    is_explicitly_deferred: bool = false,
    preserve_whitespaces: bool = false,
    export_as: ?[]const []const u8 = null,
    match_source: MatchSource = .selector,

    /// Type parameters of the directive, if available.
    type_parameters: ?[]const TcbTypeParameter = null,
    inputs: []const TcbInputMapping = &.{},
    outputs: []const []const u8 = &.{},
    requires_inline_type_ctor: bool = false,
    ng_template_guards: []const TemplateGuardMeta = &.{},
    has_ng_template_context_guard: bool = false,
    has_ng_field_directive: bool = false,
    coerced_input_fields: []const []const u8 = &.{},
    restricted_input_fields: []const []const u8 = &.{},
    string_literal_input_fields: []const []const u8 = &.{},
    undeclared_input_fields: []const []const u8 = &.{},
    public_methods: []const []const u8 = &.{},
    ng_content_selectors: ?[]const []const u8 = null,
    animation_trigger_names: ?AnimationTriggerNames = null,
    is_host_directive: bool = false,
    template_guard: ?TemplateGuardMeta = null,
};

/// AnimationTriggerNames — legacy animation trigger names.
pub const AnimationTriggerNames = struct {
    triggers: []const []const u8,
    includes_dynamicAnimations: bool,
};

// ─── TcbComponentMetadata ───────────────────────────────────

/// TcbComponentMetadata — metadata for a component in the TCB.
/// Direct port of `TcbComponentMetadata` interface in the TS source.
pub const TcbComponentMetadata = struct {
    ref: TcbReferenceMetadata,
    type_parameters: ?[]const TcbTypeParameter = null,
    type_arguments: ?[]const []const u8 = null,
};

// ─── TcbTypeCheckBlockMetadata ──────────────────────────────

/// TcbTypeCheckBlockMetadata — metadata for a type check block.
/// Direct port of `TcbTypeCheckBlockMetadata` interface in the TS source.
pub const TcbTypeCheckBlockMetadata = struct {
    id: TypeCheckId,
    bound_target: BoundTarget,
    pipes: ?std.StringHashMap(TcbPipeMetadata) = null,
    schemas: []const SchemaMetadata = &.{},
    is_standalone: bool = false,
    preserve_whitespaces: bool = false,
};

/// TypeCheckId — branded string type for type check block IDs.
pub const TypeCheckId = []const u8;

/// BoundTarget — a resolved template binding target.
pub const BoundTarget = struct {
    /// Placeholder for the full BoundTarget implementation.
    _placeholder: u32 = 0,
};

/// SchemaMetadata — DOM schema metadata.
pub const SchemaMetadata = struct {
    uri: ?[]const u8 = null,
    name: ?[]const u8 = null,
};

// ─── TcbEnvironment ─────────────────────────────────────────

/// TcbEnvironment — shared environment for type check blocks.
/// Direct port of `TcbEnvironment` interface in the TS source.
///
/// This allows the TCB system to avoid depending on the full `Environment`
/// class from `compiler-cli` which depends on TypeScript APIs.
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

    /// Check if strict mode is enabled.
    pub fn isStrictMode(self: *const TcbEnvironment) bool {
        return self.is_strict;
    }

    /// Reference a TCB value. Returns a TcbExpr string.
    pub fn referenceTcbValue(self: *const TcbEnvironment, ref: TcbReferenceMetadata) []const u8 {
        _ = self;
        return ref.name;
    }

    /// Reference an external symbol from a module.
    pub fn referenceExternalSymbol(
        self: *const TcbEnvironment,
        module_name: []const u8,
        name: []const u8,
    ) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "import({s}).{s}", .{ module_name, name });
    }

    /// Get the pipe instance expression for a pipe.
    pub fn pipeInst(self: *const TcbEnvironment, pipe_meta: TcbPipeMetadata) []const u8 {
        _ = self;
        return pipe_meta.name;
    }

    /// Get the type constructor for a directive.
    pub fn typeCtorFor(self: *const TcbEnvironment, dir: TcbDirectiveMetadata) []const u8 {
        _ = self;
        return dir.name;
    }

    /// Get prelude statements for the TCB.
    pub fn getPreludeStatements(self: *const TcbEnvironment) []const []const u8 {
        _ = self;
        return &.{};
    }
};

// ─── TypeCtorPending ────────────────────────────────────────

/// TypeCtorPending — a pending type constructor call.
pub const TypeCtorPending = struct {
    metadata: TypeCtorMetadata,
    type_args: []const []const u8 = &.{},
};

// ─── Tests ──────────────────────────────────────────────────

test "TypeCheckingConfig defaults" {
    const config = TypeCheckingConfig{};
    try std.testing.expect(config.check_type_of_input_bindings);
    try std.testing.expect(config.check_type_of_dom_events);
    try std.testing.expect(!config.strict_templates);
    try std.testing.expect(config.full_template_type_check);
    try std.testing.expect(!config.strict_null_checks);
    try std.testing.expect(config.check_template_bodies);
    try std.testing.expect(config.check_control_flow_bodies);
    try std.testing.expect(!config.enable_template_type_checker);
}

test "TypeCheckingConfig strict mode" {
    const config = TypeCheckingConfig{
        .strict_templates = true,
        .strict_null_checks = true,
        .strict_safe_navigation_types = true,
        .strict_literal_types = true,
    };
    try std.testing.expect(config.strict_templates);
    try std.testing.expect(config.strict_null_checks);
    try std.testing.expect(config.strict_safe_navigation_types);
    try std.testing.expect(config.strict_literal_types);
}

test "ControlFlowContentProjection enum" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(ControlFlowContentProjection.err));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(ControlFlowContentProjection.warning));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(ControlFlowContentProjection.suppress));
}

test "UnusedStandaloneImports enum" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(UnusedStandaloneImports.err));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(UnusedStandaloneImports.warning));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(UnusedStandaloneImports.suppress));
}

test "TcbEnvironment init" {
    const allocator = std.testing.allocator;
    const config = TypeCheckingConfig{ .strict_templates = true };
    const env = TcbEnvironment.init(allocator, config);
    try std.testing.expect(env.is_strict);
    try std.testing.expect(env.isStrictMode());
}

test "TcbEnvironment referenceExternalSymbol" {
    const allocator = std.testing.allocator;
    const env = TcbEnvironment.init(allocator, .{});
    const result = try env.referenceExternalSymbol("@angular/common", "NgIf");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("import(@angular/common).NgIf", result);
}

test "TcbReferenceMetadata defaults" {
    const ref = TcbReferenceMetadata{ .name = "MyComponent" };
    try std.testing.expectEqualStrings("MyComponent", ref.name);
    try std.testing.expect(ref.module_name == null);
    try std.testing.expect(!ref.is_local);
    try std.testing.expect(ref.unexported_diagnostic == null);
}

test "TcbReferenceMetadata with all fields" {
    const ref = TcbReferenceMetadata{
        .name = "MyComponent",
        .module_name = "@angular/core",
        .is_local = true,
        .key = "my-key",
        .node_name_span = .{ .start = 10, .end = 20 },
        .node_file_path = "/path/to/file.ts",
    };
    try std.testing.expectEqualStrings("@angular/core", ref.module_name.?);
    try std.testing.expect(ref.is_local);
    try std.testing.expectEqualStrings("my-key", ref.key);
    try std.testing.expectEqual(@as(u32, 10), ref.node_name_span.?.start);
}

test "TcbTypeParameter" {
    const tp = TcbTypeParameter{
        .name = "T",
        .representation = "T",
        .representation_with_default = "T = any",
    };
    try std.testing.expectEqualStrings("T", tp.name);
    try std.testing.expectEqualStrings("T = any", tp.representation_with_default);
}

test "TcbInputMapping defaults" {
    const im = TcbInputMapping{
        .class_property_name = "myProp",
        .binding_property_name = "myProp",
    };
    try std.testing.expect(!im.is_signal);
    try std.testing.expect(!im.required);
    try std.testing.expect(im.transform_type == null);
}

test "TcbInputMapping with transform" {
    const im = TcbInputMapping{
        .class_property_name = "value",
        .binding_property_name = "value",
        .is_signal = true,
        .required = true,
        .transform_type = "number",
    };
    try std.testing.expect(im.is_signal);
    try std.testing.expect(im.required);
    try std.testing.expectEqualStrings("number", im.transform_type.?);
}

test "TcbPipeMetadata" {
    const pipe = TcbPipeMetadata{
        .name = "date",
        .ref = .{ .name = "DatePipe" },
    };
    try std.testing.expectEqualStrings("date", pipe.name);
    try std.testing.expectEqualStrings("DatePipe", pipe.ref.name);
    try std.testing.expect(!pipe.is_explicitly_deferred);
}

test "TemplateGuardMeta invocation" {
    const guard = TemplateGuardMeta{
        .input_name = "ngIf",
        .type = .invocation,
    };
    try std.testing.expectEqualStrings("ngIf", guard.input_name);
    try std.testing.expectEqual(TemplateGuardMeta.GuardType.invocation, guard.type);
}

test "TemplateGuardMeta binding" {
    const guard = TemplateGuardMeta{
        .input_name = "ngForOf",
        .type = .binding,
    };
    try std.testing.expectEqual(TemplateGuardMeta.GuardType.binding, guard.type);
}

test "MatchSource enum" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(MatchSource.selector));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(MatchSource.host_directive));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(MatchSource.selectorless));
}

test "TcbDirectiveMetadata defaults" {
    const meta = TcbDirectiveMetadata{ .name = "MyDirective" };
    try std.testing.expectEqualStrings("MyDirective", meta.name);
    try std.testing.expectEqual(@as(usize, 0), meta.inputs.len);
    try std.testing.expect(!meta.is_generic);
    try std.testing.expect(!meta.is_component);
    try std.testing.expect(!meta.is_standalone);
    try std.testing.expect(meta.selector == null);
    try std.testing.expect(meta.type_parameters == null);
}

test "TcbDirectiveMetadata component" {
    const meta = TcbDirectiveMetadata{
        .name = "MyComponent",
        .is_component = true,
        .is_standalone = true,
        .selector = "app-my",
    };
    try std.testing.expect(meta.is_component);
    try std.testing.expect(meta.is_standalone);
    try std.testing.expectEqualStrings("app-my", meta.selector.?);
}

test "TypeCtorMetadata defaults" {
    const meta = TypeCtorMetadata{
        .fn_name = "MyTypeCtor",
        .body = true,
    };
    try std.testing.expectEqualStrings("MyTypeCtor", meta.fn_name);
    try std.testing.expect(meta.body);
    try std.testing.expectEqual(@as(usize, 0), meta.coerced_input_fields.len);
}

test "TcbComponentMetadata" {
    const meta = TcbComponentMetadata{
        .ref = .{ .name = "MyComponent" },
    };
    try std.testing.expectEqualStrings("MyComponent", meta.ref.name);
    try std.testing.expect(meta.type_parameters == null);
    try std.testing.expect(meta.type_arguments == null);
}

test "TcbTypeCheckBlockMetadata" {
    const meta = TcbTypeCheckBlockMetadata{
        .id = "tcb-1",
        .bound_target = .{},
    };
    try std.testing.expectEqualStrings("tcb-1", meta.id);
    try std.testing.expect(!meta.is_standalone);
}

test "AbsoluteSourceSpan" {
    const span = AbsoluteSourceSpan{ .start = 5, .end = 10 };
    try std.testing.expectEqual(@as(u32, 5), span.start);
    try std.testing.expectEqual(@as(u32, 10), span.end);
}

test "AnimationTriggerNames" {
    const anim = AnimationTriggerNames{
        .triggers = &.{ "fadeIn", "fadeOut" },
        .includes_dynamicAnimations = true,
    };
    try std.testing.expectEqual(@as(usize, 2), anim.triggers.len);
    try std.testing.expect(anim.includes_dynamicAnimations);
}

test "SchemaMetadata defaults" {
    const schema = SchemaMetadata{};
    try std.testing.expect(schema.uri == null);
    try std.testing.expect(schema.name == null);
}

test "SchemaMetadata with uri" {
    const schema = SchemaMetadata{
        .uri = "https://example.com/schema",
        .name = "custom",
    };
    try std.testing.expectEqualStrings("https://example.com/schema", schema.uri.?);
    try std.testing.expectEqualStrings("custom", schema.name.?);
}

test "TypeCtorPending" {
    const pending = TypeCtorPending{
        .metadata = .{ .fn_name = "ctor", .body = false },
    };
    try std.testing.expectEqualStrings("ctor", pending.metadata.fn_name);
    try std.testing.expectEqual(@as(usize, 0), pending.type_args.len);
}

test "TcbEnvironment pipeInst" {
    const allocator = std.testing.allocator;
    const env = TcbEnvironment.init(allocator, .{});
    const pipe = TcbPipeMetadata{ .name = "date", .ref = .{ .name = "DatePipe" } };
    const result = env.pipeInst(pipe);
    try std.testing.expectEqualStrings("date", result);
}

test "TcbEnvironment typeCtorFor" {
    const allocator = std.testing.allocator;
    const env = TcbEnvironment.init(allocator, .{});
    const dir = TcbDirectiveMetadata{ .name = "NgIf" };
    const result = env.typeCtorFor(dir);
    try std.testing.expectEqualStrings("NgIf", result);
}

test "TcbEnvironment getPreludeStatements" {
    const allocator = std.testing.allocator;
    const env = TcbEnvironment.init(allocator, .{});
    const prelude = env.getPreludeStatements();
    try std.testing.expectEqual(@as(usize, 0), prelude.len);
}

test "TcbEnvironment referenceTcbValue" {
    const allocator = std.testing.allocator;
    const env = TcbEnvironment.init(allocator, .{});
    const ref = TcbReferenceMetadata{ .name = "MyComp" };
    const result = env.referenceTcbValue(ref);
    try std.testing.expectEqualStrings("MyComp", result);
}
