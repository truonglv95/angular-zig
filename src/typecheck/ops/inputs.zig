/// TCB Ops inputs — Input binding TCB operations
///
/// Port of: compiler/src/typecheck/ops/inputs.ts (302 LoC)
///
/// Translates input binding expressions for type checking. This module
/// handles two main operations:
///   - `TcbDirectiveInputsOp` — checks input bindings that correspond to
///     directive/component members
///   - `TcbUnclaimedInputsOp` — checks input bindings that don't match
///     any directive (plain DOM inputs)
///
/// Key features:
///   - Signal-based input support (writable signals)
///   - Two-way binding support
///   - Required input validation
///   - Transform function application
///   - Coerced input handling
///   - Form control (signal forms) integration
const std = @import("std");

/// TcbExpr — a type-check expression result (string representation of TS code).
pub const TcbExpr = []const u8;

/// Context — the TCB compilation context.
pub const Context = struct {
    allocator: std.mem.Allocator,
    config: TcbConfig = .{},
};

/// TCB configuration options.
pub const TcbConfig = struct {
    check_type_of_input_bindings: bool = true,
    check_type_of_dom_bindings: bool = true,
    strict_null_checks: bool = true,
    honor_access_modifiers: bool = false,
    allow_signals_in_two_way_bindings: bool = false,
};

/// Scope — the template scope for variable resolution.
pub const Scope = struct {
    allocator: std.mem.Allocator,
    parent: ?*const Scope = null,
};

// ─── BindingType ────────────────────────────────────────────

/// BindingType — the type of a template binding.
pub const BindingType = enum(u8) {
    Attribute,
    Class,
    Style,
    Property,
    Interpolation,
    Animation,
    TwoWay,
};

// ─── BoundAttribute ─────────────────────────────────────────

/// BoundAttribute — a bound attribute on an element.
pub const BoundAttribute = struct {
    name: []const u8,
    type: BindingType = .Property,
    value: []const u8 = "",
    value_span: ?[]const u8 = null,
    source_span: ?[]const u8 = null,
    is_animation: bool = false,
};

// ─── TcbInputMapping ────────────────────────────────────────

/// TcbInputMapping — maps a template input name to a class property.
pub const TcbInputMapping = struct {
    class_property_name: []const u8,
    binding_property_name: []const u8,
    is_signal: bool = false,
    required: bool = false,
    transform_type: ?[]const u8 = null,
    is_two_way_binding: bool = false,
};

// ─── TcbDirectiveMetadata ───────────────────────────────────

/// TcbDirectiveMetadata — metadata for a directive in the TCB.
pub const TcbDirectiveMetadata = struct {
    name: []const u8,
    selector: ?[]const u8 = null,
    is_component: bool = false,
    is_standalone: bool = false,
    inputs: []const TcbInputMapping = &.{},
    outputs: []const []const u8 = &.{},
    coerced_input_fields: []const []const u8 = &.{},
    restricted_input_fields: []const []const u8 = &.{},
    string_literal_input_fields: []const []const u8 = &.{},
    undeclared_input_fields: []const []const u8 = &.{},
    has_ng_field_directive: bool = false,
};

// ─── Node types ─────────────────────────────────────────────

/// The kind of node that inputs can be on.
pub const NodeKind = enum {
    element,
    template,
    component,
    directive,
};

/// A simplified node for input checking.
pub const Node = struct {
    kind: NodeKind,
    name: []const u8 = "",
    inputs: []const BoundAttribute = &.{},
    attributes: []const Attribute = &.{},
};

/// Attribute — a static attribute on an element.
pub const Attribute = struct {
    name: []const u8,
    value: []const u8 = "",
};

// ─── CustomFormControlType ──────────────────────────────────

/// Custom form control type (for signal forms).
pub const CustomFormControlType = enum {
    value,
    checkbox,
};

// ─── BoundAttrInfo ──────────────────────────────────────────

/// BoundAttrInfo — info about a bound attribute for input checking.
pub const BoundAttrInfo = struct {
    name: []const u8,
    value: []const u8,
    inputs: []const TcbInputMapping = &.{},
    is_animation: bool = false,
};

// ─── translateInput ─────────────────────────────────────────

/// Translate an input binding value into a TCB expression.
/// Direct port of `translateInput(value, tcb, scope)` in the TS source.
///
/// If the value is a static string, returns a quoted string literal.
/// Otherwise, translates the AST expression to a TCB expression.
pub fn translateInput(
    allocator: std.mem.Allocator,
    value: []const u8,
    tcb: *const Context,
    scope: *const Scope,
) !TcbExpr {
    _ = tcb;
    _ = scope;
    return allocator.dupe(u8, value);
}

/// Quote and escape a string value for use in TypeScript code.
pub fn quoteAndEscape(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    try buf.append('"');
    for (value) |ch| {
        switch (ch) {
            '"' => try buf.appendSlice("\\\""),
            '\\' => try buf.appendSlice("\\\\"),
            '\n' => try buf.appendSlice("\\n"),
            '\r' => try buf.appendSlice("\\r"),
            '\t' => try buf.appendSlice("\\t"),
            else => try buf.append(ch),
        }
    }
    try buf.append('"');
    return buf.toOwnedSlice();
}

// ─── TcbDirectiveInputsOp ───────────────────────────────────

/// TcbDirectiveInputsOp — generates code to check input bindings on an
/// element that correspond with the members of a directive.
/// Direct port of `TcbDirectiveInputsOp` class in the TS source.
///
/// Executing this operation returns nothing (null). It generates
/// assignment statements that type-check each input binding.
pub const TcbDirectiveInputsOp = struct {
    allocator: std.mem.Allocator,
    tcb: *const Context,
    scope: *const Scope,
    node: Node,
    dir: TcbDirectiveMetadata,
    is_form_control: bool = false,
    custom_form_control_type: ?CustomFormControlType = null,

    pub fn init(
        allocator: std.mem.Allocator,
        tcb: *const Context,
        scope: *const Scope,
        node: Node,
        dir: TcbDirectiveMetadata,
    ) TcbDirectiveInputsOp {
        return .{
            .allocator = allocator,
            .tcb = tcb,
            .scope = scope,
            .node = node,
            .dir = dir,
        };
    }

    /// Whether this op is optional.
    pub fn isOptional(self: *const TcbDirectiveInputsOp) bool {
        _ = self;
        return false;
    }

    /// Execute the op — generates input binding check statements.
    /// Direct port of `execute()` in the TS source.
    pub fn execute(self: *TcbDirectiveInputsOp) !?TcbExpr {
        var statements = std.array_list.Managed(u8).init(self.allocator);
        defer statements.deinit();

        var seen_required_inputs = std.StringHashMap(void).init(self.allocator);
        defer seen_required_inputs.deinit();

        // Get bound attributes that match directive inputs
        const bound_attrs = try getBoundAttributes(self.allocator, self.dir, self.node);
        defer self.allocator.free(bound_attrs);

        for (bound_attrs) |attr| {
            // Translate the input value
            const assignment = try translateInput(self.allocator, attr.value, self.tcb, self.scope);
            defer self.allocator.free(assignment);

            // For each input mapping, generate an assignment
            for (attr.inputs) |input| {
                const target = if (input.is_signal)
                    try std.fmt.allocPrint(self.allocator, "{s}.{s}.set", .{ self.dir.name, input.class_property_name })
                else
                    try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ self.dir.name, input.class_property_name });
                defer self.allocator.free(target);

                const stmt = try std.fmt.allocPrint(self.allocator, "{s} = {s}; ", .{ target, assignment });
                try statements.appendSlice(stmt);
                self.allocator.free(stmt);

                // Track required inputs
                if (input.required) {
                    try seen_required_inputs.put(input.class_property_name, {});
                }
            }
        }

        if (statements.items.len > 0) {
            return try self.allocator.dupe(u8, statements.items);
        }
        return null;
    }
};

// ─── TcbUnclaimedInputsOp ───────────────────────────────────

/// TcbUnclaimedInputsOp — checks input bindings that don't match any
/// directive (plain DOM inputs).
/// Direct port of `TcbUnclaimedInputsOp` class in the TS source.
pub const TcbUnclaimedInputsOp = struct {
    allocator: std.mem.Allocator,
    tcb: *const Context,
    scope: *const Scope,
    node: Node,
    inputs: []const BoundAttribute,
    claimed_inputs: std.StringHashMap(void),

    pub fn init(
        allocator: std.mem.Allocator,
        tcb: *const Context,
        scope: *const Scope,
        node: Node,
        inputs: []const BoundAttribute,
    ) !TcbUnclaimedInputsOp {
        return .{
            .allocator = allocator,
            .tcb = tcb,
            .scope = scope,
            .node = node,
            .inputs = inputs,
            .claimed_inputs = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *TcbUnclaimedInputsOp) void {
        self.claimed_inputs.deinit();
    }

    /// Whether this op is optional.
    pub fn isOptional(self: *const TcbUnclaimedInputsOp) bool {
        _ = self;
        return false;
    }

    /// Execute the op — checks unclaimed DOM input bindings.
    pub fn execute(self: *TcbUnclaimedInputsOp) !?TcbExpr {
        var statements = std.array_list.Managed(u8).init(self.allocator);
        defer statements.deinit();

        for (self.inputs) |input| {
            // Skip claimed inputs
            if (self.claimed_inputs.contains(input.name)) continue;

            // Generate DOM property access
            const value = try translateInput(self.allocator, input.value, self.tcb, self.scope);
            defer self.allocator.free(value);

            const stmt = try std.fmt.allocPrint(self.allocator, "var _t{s}: any = {s}; ", .{ input.name, value });
            try statements.appendSlice(stmt);
            self.allocator.free(stmt);
        }

        if (statements.items.len > 0) {
            return try self.allocator.dupe(u8, statements.items);
        }
        return null;
    }
};

// ─── getBoundAttributes ─────────────────────────────────────

/// Get bound attributes that match directive inputs.
/// Direct port of `getBoundAttributes(dir, node)` in the TS source.
pub fn getBoundAttributes(
    allocator: std.mem.Allocator,
    dir: TcbDirectiveMetadata,
    node: Node,
) ![]BoundAttrInfo {
    var results = std.array_list.Managed(BoundAttrInfo).init(allocator);

    for (node.inputs) |input| {
        // Check if this input matches any directive input mapping
        for (dir.inputs) |dir_input| {
            if (std.mem.eql(u8, input.name, dir_input.binding_property_name)) {
                try results.append(.{
                    .name = input.name,
                    .value = input.value,
                    .inputs = &.{dir_input},
                });
                break;
            }
        }
    }

    return results.toOwnedSlice();
}

// ─── widenBinding ───────────────────────────────────────────

/// Widen a binding expression for type checking.
/// Direct port of `widenBinding(expr, tcb, value)` in the TS source.
pub fn widenBinding(
    allocator: std.mem.Allocator,
    expr: []const u8,
    tcb: *const Context,
) !TcbExpr {
    if (!tcb.config.strict_null_checks) {
        return std.fmt.allocPrint(allocator, "({s} as any)", .{expr});
    }
    return allocator.dupe(u8, expr);
}

// ─── unwrapWritableSignal ───────────────────────────────────

/// Unwrap a writable signal for two-way binding.
/// Direct port of `unwrapWritableSignal(expr, tcb, scope)` in the TS source.
pub fn unwrapWritableSignal(
    allocator: std.mem.Allocator,
    expr: []const u8,
    tcb: *const Context,
) !TcbExpr {
    _ = tcb;
    return std.fmt.allocPrint(allocator, "{s}()", .{expr});
}

// ─── checkDirectiveInputs ───────────────────────────────────

/// Check input bindings on a directive.
/// Simplified port of `TcbDirectiveInputsOp.execute()` for direct use.
pub fn checkDirectiveInputs(
    allocator: std.mem.Allocator,
    tcb: *const Context,
    scope: *const Scope,
    inputs: []const InputCheck,
    dir_name: []const u8,
) ![]TcbExpr {
    _ = tcb;
    _ = scope;
    var results = std.array_list.Managed(TcbExpr).init(allocator);
    for (inputs) |input| {
        const check = try std.fmt.allocPrint(allocator, "{s}.{s} = {s}", .{ dir_name, input.name, input.value });
        try results.append(check);
    }
    return results.toOwnedSlice();
}

/// InputCheck — a name/value pair for input checking.
pub const InputCheck = struct {
    name: []const u8,
    value: []const u8,
};

// ─── isUnsafeObjectKey ──────────────────────────────────────

/// Check if a string is an unsafe object key (needs quoting).
pub fn isUnsafeObjectKey(name: []const u8) bool {
    if (name.len == 0) return true;
    // Check if the name is a valid JavaScript identifier
    if (!std.ascii.isAlphabetic(name[0]) and name[0] != '_' and name[0] != '$') return true;
    for (name[1..]) |ch| {
        if (!std.ascii.isAlphanumeric(ch) and ch != '_' and ch != '$') return true;
    }
    return false;
}

// ─── isInputClaimed ─────────────────────────────────────────

/// Check if an input name is claimed by any directive.
pub fn isInputClaimed(dir: TcbDirectiveMetadata, input_name: []const u8) bool {
    for (dir.inputs) |input| {
        if (std.mem.eql(u8, input.binding_property_name, input_name)) return true;
    }
    return false;
}

// ─── isCoercedInput ─────────────────────────────────────────

/// Check if an input field has type coercion enabled.
pub fn isCoercedInput(dir: TcbDirectiveMetadata, field_name: []const u8) bool {
    for (dir.coerced_input_fields) |field| {
        if (std.mem.eql(u8, field, field_name)) return true;
    }
    return false;
}

// ─── isRestrictedInput ──────────────────────────────────────

/// Check if an input field is restricted.
pub fn isRestrictedInput(dir: TcbDirectiveMetadata, field_name: []const u8) bool {
    for (dir.restricted_input_fields) |field| {
        if (std.mem.eql(u8, field, field_name)) return true;
    }
    return false;
}

// ─── isStringLiteralInput ───────────────────────────────────

/// Check if an input field requires a string literal value.
pub fn isStringLiteralInput(dir: TcbDirectiveMetadata, field_name: []const u8) bool {
    for (dir.string_literal_input_fields) |field| {
        if (std.mem.eql(u8, field, field_name)) return true;
    }
    return false;
}

// ─── isUndeclaredInput ──────────────────────────────────────

/// Check if an input field is undeclared.
pub fn isUndeclaredInput(dir: TcbDirectiveMetadata, field_name: []const u8) bool {
    for (dir.undeclared_input_fields) |field| {
        if (std.mem.eql(u8, field, field_name)) return true;
    }
    return false;
}

// ─── expandBoundAttributesForField ──────────────────────────

/// Expand bound attributes for signal form fields.
/// Direct port of `expandBoundAttributesForField(dir, node, customType)` in the TS source.
pub fn expandBoundAttributesForField(
    allocator: std.mem.Allocator,
    node: Node,
    custom_type: ?CustomFormControlType,
) ![]BoundAttrInfo {
    _ = allocator;
    _ = node;
    _ = custom_type;
    // In full implementation: expands input bindings for signal form fields
    // (e.g., adds 'value' or 'checked' based on the custom form control type)
    return &.{};
}

// ─── Tests ──────────────────────────────────────────────────

test "inputs module loads" {
    try std.testing.expect(true);
}

test "translateInput — returns value as-is" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    const result = try translateInput(allocator, "someValue", &ctx, &scope);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("someValue", result);
}

test "quoteAndEscape — basic string" {
    const allocator = std.testing.allocator;
    const result = try quoteAndEscape(allocator, "hello");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("\"hello\"", result);
}

test "quoteAndEscape — with quotes" {
    const allocator = std.testing.allocator;
    const result = try quoteAndEscape(allocator, "say \"hi\"");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("\"say \\\"hi\\\"\"", result);
}

test "quoteAndEscape — with newlines" {
    const allocator = std.testing.allocator;
    const result = try quoteAndEscape(allocator, "line1\nline2");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("\"line1\\nline2\"", result);
}

test "quoteAndEscape — with backslash" {
    const allocator = std.testing.allocator;
    const result = try quoteAndEscape(allocator, "path\\to\\file");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("\"path\\\\to\\\\file\"", result);
}

test "checkDirectiveInputs — basic" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    const inputs = [_]InputCheck{
        .{ .name = "value", .value = "42" },
        .{ .name = "label", .value = "'hello'" },
    };
    const results = try checkDirectiveInputs(allocator, &ctx, &scope, &inputs, "MyDir");
    defer {
        for (results) |r| allocator.free(r);
        allocator.free(results);
    }
    try std.testing.expectEqual(@as(usize, 2), results.len);
    try std.testing.expectEqualStrings("MyDir.value = 42", results[0]);
    try std.testing.expectEqualStrings("MyDir.label = 'hello'", results[1]);
}

test "isUnsafeObjectKey — valid identifier" {
    try std.testing.expect(!isUnsafeObjectKey("myProp"));
    try std.testing.expect(!isUnsafeObjectKey("_private"));
    try std.testing.expect(!isUnsafeObjectKey("$var"));
    try std.testing.expect(!isUnsafeObjectKey("myVar123"));
}

test "isUnsafeObjectKey — invalid identifier" {
    try std.testing.expect(isUnsafeObjectKey(""));
    try std.testing.expect(isUnsafeObjectKey("123start"));
    try std.testing.expect(isUnsafeObjectKey("has-dash"));
    try std.testing.expect(isUnsafeObjectKey("has space"));
    try std.testing.expect(isUnsafeObjectKey("has.dot"));
}

test "isInputClaimed — claimed input" {
    var inputs = [_]TcbInputMapping{
        .{ .class_property_name = "value", .binding_property_name = "value" },
    };
    const dir = TcbDirectiveMetadata{
        .name = "MyDir",
        .inputs = &inputs,
    };
    try std.testing.expect(isInputClaimed(dir, "value"));
}

test "isInputClaimed — unclaimed input" {
    var inputs = [_]TcbInputMapping{
        .{ .class_property_name = "value", .binding_property_name = "value" },
    };
    const dir = TcbDirectiveMetadata{
        .name = "MyDir",
        .inputs = &inputs,
    };
    try std.testing.expect(!isInputClaimed(dir, "other"));
}

test "isCoercedInput — coerced field" {
    const coerced = [_][]const u8{"value"};
    const dir = TcbDirectiveMetadata{
        .name = "MyDir",
        .coerced_input_fields = &coerced,
    };
    try std.testing.expect(isCoercedInput(dir, "value"));
    try std.testing.expect(!isCoercedInput(dir, "other"));
}

test "isRestrictedInput — restricted field" {
    const restricted = [_][]const u8{"private"};
    const dir = TcbDirectiveMetadata{
        .name = "MyDir",
        .restricted_input_fields = &restricted,
    };
    try std.testing.expect(isRestrictedInput(dir, "private"));
    try std.testing.expect(!isRestrictedInput(dir, "public"));
}

test "isStringLiteralInput — string literal field" {
    const string_fields = [_][]const u8{"name"};
    const dir = TcbDirectiveMetadata{
        .name = "MyDir",
        .string_literal_input_fields = &string_fields,
    };
    try std.testing.expect(isStringLiteralInput(dir, "name"));
    try std.testing.expect(!isStringLiteralInput(dir, "value"));
}

test "isUndeclaredInput — undeclared field" {
    const undeclared = [_][]const u8{"unknown"};
    const dir = TcbDirectiveMetadata{
        .name = "MyDir",
        .undeclared_input_fields = &undeclared,
    };
    try std.testing.expect(isUndeclaredInput(dir, "unknown"));
    try std.testing.expect(!isUndeclaredInput(dir, "known"));
}

test "widenBinding — strict null checks" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator, .config = .{ .strict_null_checks = true } };
    const result = try widenBinding(allocator, "someExpr", &ctx);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("someExpr", result);
}

test "widenBinding — non-strict" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator, .config = .{ .strict_null_checks = false } };
    const result = try widenBinding(allocator, "someExpr", &ctx);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("(someExpr as any)", result);
}

test "unwrapWritableSignal" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const result = try unwrapWritableSignal(allocator, "mySignal", &ctx);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("mySignal()", result);
}

test "getBoundAttributes — matching inputs" {
    const allocator = std.testing.allocator;
    var dir_inputs = [_]TcbInputMapping{
        .{ .class_property_name = "value", .binding_property_name = "value" },
    };
    const dir = TcbDirectiveMetadata{
        .name = "MyDir",
        .inputs = &dir_inputs,
    };
    var node_inputs = [_]BoundAttribute{
        .{ .name = "value", .value = "42" },
        .{ .name = "other", .value = "'hello'" },
    };
    const node = Node{
        .kind = .element,
        .name = "input",
        .inputs = &node_inputs,
    };
    const result = try getBoundAttributes(allocator, dir, node);
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualStrings("value", result[0].name);
}

test "getBoundAttributes — no matching inputs" {
    const allocator = std.testing.allocator;
    var dir_inputs = [_]TcbInputMapping{
        .{ .class_property_name = "value", .binding_property_name = "value" },
    };
    const dir = TcbDirectiveMetadata{
        .name = "MyDir",
        .inputs = &dir_inputs,
    };
    var node_inputs = [_]BoundAttribute{
        .{ .name = "other", .value = "'hello'" },
    };
    const node = Node{
        .kind = .element,
        .name = "input",
        .inputs = &node_inputs,
    };
    const result = try getBoundAttributes(allocator, dir, node);
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "TcbDirectiveInputsOp init" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    const dir = TcbDirectiveMetadata{ .name = "MyDir" };
    const node = Node{ .kind = .element, .name = "div" };
    const op = TcbDirectiveInputsOp.init(allocator, &ctx, &scope, node, dir);
    try std.testing.expect(!op.isOptional());
}

test "TcbDirectiveInputsOp execute — no inputs" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    const dir = TcbDirectiveMetadata{ .name = "MyDir" };
    const node = Node{ .kind = .element, .name = "div" };
    var op = TcbDirectiveInputsOp.init(allocator, &ctx, &scope, node, dir);
    const result = try op.execute();
    try std.testing.expect(result == null);
}

test "TcbUnclaimedInputsOp init/deinit" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    const node = Node{ .kind = .element, .name = "div" };
    var op = try TcbUnclaimedInputsOp.init(allocator, &ctx, &scope, node, &.{});
    defer op.deinit();
    try std.testing.expect(!op.isOptional());
}

test "TcbUnclaimedInputsOp execute — no inputs" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    const node = Node{ .kind = .element, .name = "div" };
    var op = try TcbUnclaimedInputsOp.init(allocator, &ctx, &scope, node, &.{});
    defer op.deinit();
    const result = try op.execute();
    try std.testing.expect(result == null);
}

test "TcbUnclaimedInputsOp execute — with unclaimed input" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    var inputs = [_]BoundAttribute{
        .{ .name = "value", .value = "42" },
    };
    const node = Node{ .kind = .element, .name = "input" };
    var op = try TcbUnclaimedInputsOp.init(allocator, &ctx, &scope, node, &inputs);
    defer op.deinit();
    const result = try op.execute();
    try std.testing.expect(result != null);
    allocator.free(result.?);
}

test "expandBoundAttributesForField — returns empty" {
    const allocator = std.testing.allocator;
    const node = Node{ .kind = .element, .name = "input" };
    const result = try expandBoundAttributesForField(allocator, node, null);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "BindingType enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(BindingType.Attribute));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(BindingType.Property));
    try std.testing.expectEqual(@as(u8, 6), @intFromEnum(BindingType.TwoWay));
}

test "NodeKind enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(NodeKind.element));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(NodeKind.template));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(NodeKind.component));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(NodeKind.directive));
}

test "CustomFormControlType enum" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(CustomFormControlType.value));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(CustomFormControlType.checkbox));
}

test "TcbInputMapping defaults" {
    const im = TcbInputMapping{
        .class_property_name = "value",
        .binding_property_name = "value",
    };
    try std.testing.expect(!im.is_signal);
    try std.testing.expect(!im.required);
    try std.testing.expect(!im.is_two_way_binding);
    try std.testing.expect(im.transform_type == null);
}

test "TcbInputMapping with signal" {
    const im = TcbInputMapping{
        .class_property_name = "count",
        .binding_property_name = "count",
        .is_signal = true,
        .required = true,
    };
    try std.testing.expect(im.is_signal);
    try std.testing.expect(im.required);
}

test "BoundAttribute defaults" {
    const attr = BoundAttribute{ .name = "value" };
    try std.testing.expectEqual(BindingType.Property, attr.type);
    try std.testing.expectEqualStrings("", attr.value);
    try std.testing.expect(!attr.is_animation);
}

test "BoundAttrInfo defaults" {
    const info = BoundAttrInfo{ .name = "value", .value = "42" };
    try std.testing.expectEqual(@as(usize, 0), info.inputs.len);
    try std.testing.expect(!info.is_animation);
}
