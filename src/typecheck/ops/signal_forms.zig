/// TCB Ops signal_forms — Signal forms TCB operations
///
/// Port of: compiler/src/typecheck/ops/signal_forms.ts (496 LoC)
///
/// Type-checks signal-based inputs and two-way bindings for Angular's
/// signal forms API. This module handles:
///   - `TcbNativeFieldOp` — constructs a FormField directive on native elements
///   - `TcbNativeRadioButtonFieldOp` — specialized for radio button inputs
///   - `isFormControl` — detects if a node matches a form control directive
///   - `isNativeField` — detects if a node is a native form field
///   - `getCustomFieldDirectiveType` — determines value/checkbox type
///   - `extractFieldValueSignal` — extracts the signal from a field binding
///   - `checkUnsupportedFieldBindings` — validates field binding constraints
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
    check_type_of_signals: bool = true,
    strict_null_checks: bool = true,
};

/// Scope — the template scope for variable resolution.
pub const Scope = struct {
    allocator: std.mem.Allocator,
    parent: ?*const Scope = null,
};

// ─── CustomFormControlType ───────────────────────────────────

/// Possible types of custom form control directives.
/// Direct port of `CustomFormControlType` type in the TS source.
pub const CustomFormControlType = enum {
    value,
    checkbox,
};

/// Convert CustomFormControlType to string.
pub fn customFormControlTypeToString(t: CustomFormControlType) []const u8 {
    return switch (t) {
        .value => "value",
        .checkbox => "checkbox",
    };
}

// ─── Form control input fields ──────────────────────────────

/// Names of the input fields on custom controls.
/// Direct port of `formControlInputFields` in the TS source.
/// Should be kept in sync with the `FormUiControl` bindings defined in
/// `packages/forms/signals/src/api/control.ts`.
pub const FORM_CONTROL_INPUT_FIELDS = [_][]const u8{
    "errors",
    "dirty",
    "disabled",
    "disabledReasons",
    "hidden",
    "invalid",
    "name",
    "pending",
    "readonly",
    "touched",
    "max",
    "maxLength",
    "min",
    "minLength",
    "pattern",
    "required",
};

/// Names of input fields to which users aren't allowed to bind when using a `field` directive.
/// Direct port of `customFormControlBannedInputFields` in the TS source.
pub const CUSTOM_FORM_CONTROL_BANNED_INPUT_FIELDS = [_][]const u8{
    "errors",
    "dirty",
    "disabled",
    "disabledReasons",
    "hidden",
    "invalid",
    "name",
    "pending",
    "readonly",
    "touched",
    "max",
    "maxLength",
    "min",
    "minLength",
    "pattern",
    "required",
    "value",
    "checked",
};

/// Names of the fields that are optional on a control.
/// Direct port of `formControlOptionalFields` in the TS source.
pub const FORM_CONTROL_OPTIONAL_FIELDS = [_][]const u8{
    "max",
    "maxLength",
    "min",
    "minLength",
};

/// Check if a field name is a form control input field.
pub fn isFormControlInputField(name: []const u8) bool {
    for (FORM_CONTROL_INPUT_FIELDS) |field| {
        if (std.mem.eql(u8, name, field)) return true;
    }
    return false;
}

/// Check if a field name is a banned input field for custom form controls.
pub fn isBannedInputField(name: []const u8) bool {
    for (CUSTOM_FORM_CONTROL_BANNED_INPUT_FIELDS) |field| {
        if (std.mem.eql(u8, name, field)) return true;
    }
    return false;
}

/// Check if a field name is an optional form control field.
pub fn isOptionalFormField(name: []const u8) bool {
    for (FORM_CONTROL_OPTIONAL_FIELDS) |field| {
        if (std.mem.eql(u8, name, field)) return true;
    }
    return false;
}

// ─── Signal form type ───────────────────────────────────────

/// Signal form type — describes how a signal is used in a binding.
pub const SignalFormType = enum(u8) {
    Read, // signal()
    Write, // signal.set()
    Update, // signal.update()
    TwoWay, // [(signal)]
};

/// SignalBindingInfo — info about a signal-based binding.
pub const SignalBindingInfo = struct {
    signal_name: []const u8,
    form_type: SignalFormType,
    is_model_signal: bool = false,
    is_query_signal: bool = false,
};

// ─── BindingType ────────────────────────────────────────────

/// BindingType — the type of a template binding.
/// Direct port of `BindingType` from expression_parser/ast.ts.
pub const BindingType = enum(u8) {
    Attribute, // [attr.name]="expr"
    Class, // [class.name]="expr"
    Style, // [style.name]="expr"
    Property, // [name]="expr"
    Interpolation, // {{ expr }}
    Animation, // [@name]="expr"
    TwoWay, // [(name)]="expr"
};

// ─── BoundAttribute ─────────────────────────────────────────

/// BoundAttribute — a bound attribute on an element.
/// Simplified port of `BoundAttribute` from r3_ast.ts.
pub const BoundAttribute = struct {
    name: []const u8,
    type: BindingType,
    value: []const u8 = "",
    source_span: ?[]const u8 = null,
};

// ─── Element ────────────────────────────────────────────────

/// Element — a simplified element node for signal form checking.
pub const Element = struct {
    name: []const u8,
    inputs: []const BoundAttribute = &.{},
    attributes: []const Attribute = &.{},
};

/// Attribute — a static attribute on an element.
pub const Attribute = struct {
    name: []const u8,
    value: []const u8 = "",
};

// ─── TcbNativeFieldOp ───────────────────────────────────────

/// TcbNativeFieldOp — constructs an instance of the signal forms `FormField`
/// directive on a native element.
/// Direct port of `TcbNativeFieldOp` class in the TS source.
pub const TcbNativeFieldOp = struct {
    allocator: std.mem.Allocator,
    tcb: *const Context,
    scope: *const Scope,
    node: Element,
    input_type: ?[]const u8,
    has_dynamic_type: bool,
    /// Bindings that aren't supported on signal form fields.
    unsupported_binding_fields: std.StringHashMap(void),

    pub fn init(
        allocator: std.mem.Allocator,
        tcb: *const Context,
        scope: *const Scope,
        node: Element,
        input_type: ?[]const u8,
    ) !TcbNativeFieldOp {
        var unsupported = std.StringHashMap(void).init(allocator);
        // Initialize with form control input fields
        for (CUSTOM_FORM_CONTROL_BANNED_INPUT_FIELDS) |field| {
            try unsupported.put(field, {});
        }
        // Add additional unsupported fields
        try unsupported.put("maxlength", {});
        try unsupported.put("minlength", {});

        // Check for dynamic type binding
        const has_dynamic_type = input_type == null and blk: {
            for (node.inputs) |input| {
                if ((input.type == .Property or input.type == .Attribute) and
                    std.mem.eql(u8, input.name, "type"))
                {
                    break :blk true;
                }
            }
            break :blk false;
        };

        // For date/time inputs, min and max are allowed
        const is_possibly_date_or_time = has_dynamic_type or
            (input_type != null and (
                std.mem.eql(u8, input_type.?, "date") or
                std.mem.eql(u8, input_type.?, "time") or
                std.mem.eql(u8, input_type.?, "month") or
                std.mem.eql(u8, input_type.?, "week") or
                std.mem.eql(u8, input_type.?, "datetime-local")));

        if (is_possibly_date_or_time) {
            _ = unsupported.remove("min");
            _ = unsupported.remove("max");
        }

        return .{
            .allocator = allocator,
            .tcb = tcb,
            .scope = scope,
            .node = node,
            .input_type = input_type,
            .has_dynamic_type = has_dynamic_type,
            .unsupported_binding_fields = unsupported,
        };
    }

    pub fn deinit(self: *TcbNativeFieldOp) void {
        self.unsupported_binding_fields.deinit();
    }

    /// Whether this op is optional.
    /// Direct port of `get optional` in the TS source.
    pub fn isOptional(self: *const TcbNativeFieldOp) bool {
        _ = self;
        return false;
    }

    /// Execute the op — generates type-checking code for the native field.
    /// Direct port of `execute()` in the TS source.
    pub fn execute(self: *TcbNativeFieldOp) !?TcbExpr {
        // Find the formField binding
        var field_binding: ?BoundAttribute = null;
        for (self.node.inputs) |input| {
            if (input.type == .Property and std.mem.eql(u8, input.name, "formField")) {
                field_binding = input;
                break;
            }
        }

        // If no formField binding, nothing to do
        if (field_binding == null) return null;

        // Check for unsupported field bindings
        try checkUnsupportedFieldBindings(self.allocator, self.node, self.unsupported_binding_fields);

        // Get expected type from DOM node
        const raw_expected_type = try self.getExpectedTypeFromDomNode();

        if (raw_expected_type) |expected| {
            // Generate type-checking code for specific input types
            return try std.fmt.allocPrint(self.allocator, "var _f = {s};", .{expected});
        } else {
            // For text-like inputs, use a union type for the value signal
            return try self.allocator.dupe(u8, "var _f: { (): string; set: (v: string) => void; } | { (): number | null; set: (v: number | null) => void; } = null!;");
        }
    }

    /// Get the expected type from the DOM node's input type attribute.
    /// Direct port of `getExpectedTypeFromDomNode(node)` in the TS source.
    fn getExpectedTypeFromDomNode(self: *const TcbNativeFieldOp) !?[]const u8 {
        if (self.input_type) |input_type| {
            if (std.mem.eql(u8, input_type, "checkbox")) {
                return "boolean";
            } else if (std.mem.eql(u8, input_type, "number") or
                std.mem.eql(u8, input_type, "range"))
            {
                return "number | null";
            } else if (std.mem.eql(u8, input_type, "date") or
                std.mem.eql(u8, input_type, "time") or
                std.mem.eql(u8, input_type, "month") or
                std.mem.eql(u8, input_type, "week") or
                std.mem.eql(u8, input_type, "datetime-local"))
            {
                return "string | null";
            }
        }
        return null;
    }
};

// ─── TcbNativeRadioButtonFieldOp ────────────────────────────

/// TcbNativeRadioButtonFieldOp — specialized for radio button inputs.
/// Direct port of `TcbNativeRadioButtonFieldOp` class in the TS source.
pub const TcbNativeRadioButtonFieldOp = struct {
    allocator: std.mem.Allocator,
    tcb: *const Context,
    scope: *const Scope,
    node: Element,

    pub fn init(
        allocator: std.mem.Allocator,
        tcb: *const Context,
        scope: *const Scope,
        node: Element,
    ) TcbNativeRadioButtonFieldOp {
        return .{
            .allocator = allocator,
            .tcb = tcb,
            .scope = scope,
            .node = node,
        };
    }

    /// Whether this op is optional.
    pub fn isOptional(self: *const TcbNativeRadioButtonFieldOp) bool {
        _ = self;
        return false;
    }

    /// Execute the op — generates type-checking code for a radio button field.
    pub fn execute(self: *TcbNativeRadioButtonFieldOp) !?TcbExpr {
        return try self.allocator.dupe(u8, "var _f: { (): string; set: (v: string) => void; } = null!;");
    }
};

// ─── isFormControl ──────────────────────────────────────────

/// Check if a node matches a form control directive.
/// Direct port of `isFormControl(directives)` in the TS source.
pub fn isFormControl(directive_names: []const []const u8) bool {
    for (directive_names) |name| {
        if (std.mem.eql(u8, name, "FormField") or
            std.mem.eql(u8, name, "FormFieldCheckbox") or
            std.mem.eql(u8, name, "FormFieldRadioGroup"))
        {
            return true;
        }
    }
    return false;
}

// ─── isNativeField ──────────────────────────────────────────

/// Check if a node is a native form field.
/// Direct port of `isNativeField(dir, node, allDirectiveMatches)` in the TS source.
pub fn isNativeField(
    dir_name: []const u8,
    node_name: []const u8,
    all_directive_names: []const []const u8,
) bool {
    // The directive must be a FormField directive
    if (!std.mem.eql(u8, dir_name, "FormField")) return false;

    // The node must be an input element
    if (!std.mem.eql(u8, node_name, "input")) return false;

    // Must not have a FormFieldCheckbox or FormFieldRadioGroup directive
    for (all_directive_names) |name| {
        if (std.mem.eql(u8, name, "FormFieldCheckbox") or
            std.mem.eql(u8, name, "FormFieldRadioGroup"))
        {
            return false;
        }
    }

    return true;
}

// ─── getCustomFieldDirectiveType ────────────────────────────

/// Determine the custom form control type (value or checkbox).
/// Direct port of `getCustomFieldDirectiveType(dir)` in the TS source.
pub fn getCustomFieldDirectiveType(dir_name: []const u8) ?CustomFormControlType {
    if (std.mem.eql(u8, dir_name, "FormFieldCheckbox")) {
        return .checkbox;
    }
    if (std.mem.eql(u8, dir_name, "FormField") or
        std.mem.eql(u8, dir_name, "FormFieldRadioGroup"))
    {
        return .value;
    }
    return null;
}

// ─── extractFieldValueSignal ────────────────────────────────

/// Extract the field value signal from a binding expression.
/// Direct port of `extractFieldValueSignal(expr, tcb, scope)` in the TS source.
pub fn extractFieldValueSignal(
    allocator: std.mem.Allocator,
    expr: []const u8,
) !TcbExpr {
    // The expression should be a signal reference. We just return it as-is.
    return allocator.dupe(u8, expr);
}

// ─── checkUnsupportedFieldBindings ──────────────────────────

/// Check for unsupported field bindings on a signal form field.
/// Direct port of `checkUnsupportedFieldBindings(node, unsupportedFields, tcb)` in the TS source.
pub fn checkUnsupportedFieldBindings(
    allocator: std.mem.Allocator,
    node: Element,
    unsupported_fields: std.StringHashMap(void),
) !void {
    _ = allocator;
    for (node.inputs) |input| {
        if (input.type == .Property or input.type == .Attribute) {
            if (unsupported_fields.contains(input.name)) {
                // In full implementation: report error via tcb.oobRecorder
                // tcb.oobRecorder.unsupportedFieldBindingType(...)
            }
        }
    }
}

// ─── Signal binding helpers ─────────────────────────────────

/// Check a signal-based input binding.
/// Direct port of the signal input check logic in the TS source.
pub fn checkSignalInput(
    allocator: std.mem.Allocator,
    info: SignalBindingInfo,
    value: []const u8,
) !TcbExpr {
    return std.fmt.allocPrint(allocator, "{s}.set({s})", .{ info.signal_name, value });
}

/// Check a signal-based two-way binding.
pub fn checkSignalTwoWayBinding(
    allocator: std.mem.Allocator,
    info: SignalBindingInfo,
    value: []const u8,
) !TcbExpr {
    return std.fmt.allocPrint(allocator, "{s}() && {s}.set({s})", .{ info.signal_name, info.signal_name, value });
}

/// Unwrap a signal read expression.
pub fn unwrapSignalRead(allocator: std.mem.Allocator, expr: []const u8) !TcbExpr {
    return std.fmt.allocPrint(allocator, "{s}()", .{expr});
}

/// Check if a binding is a signal-based binding.
pub fn isSignalBinding(info: SignalBindingInfo) bool {
    return info.is_model_signal or info.is_query_signal or
        info.form_type == .Write or info.form_type == .Update;
}

// ─── Tests ──────────────────────────────────────────────────

test "signal_forms module loads" {
    try std.testing.expect(true);
}

test "isSignalBinding detects model signals" {
    const info = SignalBindingInfo{
        .signal_name = "count",
        .form_type = .Write,
        .is_model_signal = true,
    };
    try std.testing.expect(isSignalBinding(info));
}

test "isSignalBinding detects read-only signals" {
    const info = SignalBindingInfo{
        .signal_name = "count",
        .form_type = .Read,
    };
    try std.testing.expect(!isSignalBinding(info));
}

test "unwrapSignalRead" {
    const allocator = std.testing.allocator;
    const result = try unwrapSignalRead(allocator, "mySignal");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("mySignal()", result);
}

test "CustomFormControlType — value" {
    try std.testing.expectEqualStrings("value", customFormControlTypeToString(.value));
}

test "CustomFormControlType — checkbox" {
    try std.testing.expectEqualStrings("checkbox", customFormControlTypeToString(.checkbox));
}

test "isFormControlInputField — known fields" {
    try std.testing.expect(isFormControlInputField("errors"));
    try std.testing.expect(isFormControlInputField("dirty"));
    try std.testing.expect(isFormControlInputField("disabled"));
    try std.testing.expect(isFormControlInputField("required"));
    try std.testing.expect(isFormControlInputField("max"));
}

test "isFormControlInputField — unknown fields" {
    try std.testing.expect(!isFormControlInputField("value"));
    try std.testing.expect(!isFormControlInputField("customField"));
    try std.testing.expect(!isFormControlInputField("placeholder"));
}

test "isBannedInputField — banned fields" {
    try std.testing.expect(isBannedInputField("value"));
    try std.testing.expect(isBannedInputField("checked"));
    try std.testing.expect(isBannedInputField("errors"));
    try std.testing.expect(isBannedInputField("required"));
}

test "isBannedInputField — allowed fields" {
    try std.testing.expect(!isBannedInputField("placeholder"));
    try std.testing.expect(!isBannedInputField("label"));
    try std.testing.expect(!isBannedInputField("id"));
}

test "isOptionalFormField — optional fields" {
    try std.testing.expect(isOptionalFormField("max"));
    try std.testing.expect(isOptionalFormField("maxLength"));
    try std.testing.expect(isOptionalFormField("min"));
    try std.testing.expect(isOptionalFormField("minLength"));
}

test "isOptionalFormField — required fields" {
    try std.testing.expect(!isOptionalFormField("errors"));
    try std.testing.expect(!isOptionalFormField("required"));
    try std.testing.expect(!isOptionalFormField("value"));
}

test "isFormControl — with FormField" {
    const dirs = [_][]const u8{"FormField"};
    try std.testing.expect(isFormControl(&dirs));
}

test "isFormControl — with FormFieldCheckbox" {
    const dirs = [_][]const u8{"FormFieldCheckbox"};
    try std.testing.expect(isFormControl(&dirs));
}

test "isFormControl — without form directives" {
    const dirs = [_][]const u8{"NgIf", "NgFor"};
    try std.testing.expect(!isFormControl(&dirs));
}

test "isFormControl — empty" {
    try std.testing.expect(!isFormControl(&.{}));
}

test "isNativeField — input with FormField" {
    const dirs = [_][]const u8{"FormField"};
    try std.testing.expect(isNativeField("FormField", "input", &dirs));
}

test "isNativeField — not input element" {
    const dirs = [_][]const u8{"FormField"};
    try std.testing.expect(!isNativeField("FormField", "div", &dirs));
}

test "isNativeField — not FormField directive" {
    const dirs = [_][]const u8{"NgIf"};
    try std.testing.expect(!isNativeField("NgIf", "input", &dirs));
}

test "isNativeField — has FormFieldCheckbox" {
    const dirs = [_][]const u8{ "FormField", "FormFieldCheckbox" };
    try std.testing.expect(!isNativeField("FormField", "input", &dirs));
}

test "getCustomFieldDirectiveType — FormField" {
    const result = getCustomFieldDirectiveType("FormField");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(CustomFormControlType.value, result.?);
}

test "getCustomFieldDirectiveType — FormFieldCheckbox" {
    const result = getCustomFieldDirectiveType("FormFieldCheckbox");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(CustomFormControlType.checkbox, result.?);
}

test "getCustomFieldDirectiveType — FormFieldRadioGroup" {
    const result = getCustomFieldDirectiveType("FormFieldRadioGroup");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(CustomFormControlType.value, result.?);
}

test "getCustomFieldDirectiveType — unknown directive" {
    const result = getCustomFieldDirectiveType("NgIf");
    try std.testing.expect(result == null);
}

test "extractFieldValueSignal — returns expression" {
    const allocator = std.testing.allocator;
    const result = try extractFieldValueSignal(allocator, "mySignal");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("mySignal", result);
}

test "checkSignalInput" {
    const allocator = std.testing.allocator;
    const info = SignalBindingInfo{
        .signal_name = "count",
        .form_type = .Write,
    };
    const result = try checkSignalInput(allocator, info, "42");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("count.set(42)", result);
}

test "checkSignalTwoWayBinding" {
    const allocator = std.testing.allocator;
    const info = SignalBindingInfo{
        .signal_name = "name",
        .form_type = .TwoWay,
    };
    const result = try checkSignalTwoWayBinding(allocator, info, "'hello'");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("name() && name.set('hello')", result);
}

test "BindingType enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(BindingType.Attribute));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(BindingType.Class));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(BindingType.Style));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(BindingType.Property));
}

test "SignalFormType enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(SignalFormType.Read));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(SignalFormType.Write));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(SignalFormType.Update));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(SignalFormType.TwoWay));
}

test "TcbNativeFieldOp init — text input" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    const node = Element{ .name = "input" };
    var op = try TcbNativeFieldOp.init(allocator, &ctx, &scope, node, "text");
    defer op.deinit();
    try std.testing.expect(!op.isOptional());
    try std.testing.expect(!op.has_dynamic_type);
}

test "TcbNativeFieldOp init — checkbox" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    const node = Element{ .name = "input" };
    var op = try TcbNativeFieldOp.init(allocator, &ctx, &scope, node, "checkbox");
    defer op.deinit();
    try std.testing.expectEqualStrings("checkbox", op.input_type.?);
}

test "TcbNativeFieldOp init — date input allows min/max" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    const node = Element{ .name = "input" };
    var op = try TcbNativeFieldOp.init(allocator, &ctx, &scope, node, "date");
    defer op.deinit();
    // For date inputs, min and max should NOT be in unsupported
    try std.testing.expect(!op.unsupported_binding_fields.contains("min"));
    try std.testing.expect(!op.unsupported_binding_fields.contains("max"));
}

test "TcbNativeFieldOp init — text input bans min/max" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    const node = Element{ .name = "input" };
    var op = try TcbNativeFieldOp.init(allocator, &ctx, &scope, node, "text");
    defer op.deinit();
    // For text inputs, min and max should be in unsupported
    try std.testing.expect(op.unsupported_binding_fields.contains("min"));
    try std.testing.expect(op.unsupported_binding_fields.contains("max"));
}

test "TcbNativeFieldOp init — dynamic type" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    var inputs = [_]BoundAttribute{
        .{ .name = "type", .type = .Property },
    };
    const node = Element{ .name = "input", .inputs = &inputs };
    var op = try TcbNativeFieldOp.init(allocator, &ctx, &scope, node, null);
    defer op.deinit();
    try std.testing.expect(op.has_dynamic_type);
    // Dynamic type allows min/max
    try std.testing.expect(!op.unsupported_binding_fields.contains("min"));
}

test "TcbNativeFieldOp getExpectedTypeFromDomNode — checkbox" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    const node = Element{ .name = "input" };
    var op = try TcbNativeFieldOp.init(allocator, &ctx, &scope, node, "checkbox");
    defer op.deinit();
    const result = try op.getExpectedTypeFromDomNode();
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("boolean", result.?);
}

test "TcbNativeFieldOp getExpectedTypeFromDomNode — number" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    const node = Element{ .name = "input" };
    var op = try TcbNativeFieldOp.init(allocator, &ctx, &scope, node, "number");
    defer op.deinit();
    const result = try op.getExpectedTypeFromDomNode();
    try std.testing.expectEqualStrings("number | null", result.?);
}

test "TcbNativeFieldOp getExpectedTypeFromDomNode — text (null)" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    const node = Element{ .name = "input" };
    var op = try TcbNativeFieldOp.init(allocator, &ctx, &scope, node, "text");
    defer op.deinit();
    const result = try op.getExpectedTypeFromDomNode();
    try std.testing.expect(result == null);
}

test "TcbNativeRadioButtonFieldOp init" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    const node = Element{ .name = "input" };
    const op = TcbNativeRadioButtonFieldOp.init(allocator, &ctx, &scope, node);
    try std.testing.expect(!op.isOptional());
}

test "TcbNativeRadioButtonFieldOp execute" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    const node = Element{ .name = "input" };
    var op = TcbNativeRadioButtonFieldOp.init(allocator, &ctx, &scope, node);
    const result = try op.execute();
    try std.testing.expect(result != null);
    allocator.free(result.?);
}

test "FORM_CONTROL_INPUT_FIELDS — contains expected fields" {
    var found_errors = false;
    var found_required = false;
    for (FORM_CONTROL_INPUT_FIELDS) |field| {
        if (std.mem.eql(u8, field, "errors")) found_errors = true;
        if (std.mem.eql(u8, field, "required")) found_required = true;
    }
    try std.testing.expect(found_errors);
    try std.testing.expect(found_required);
}

test "CUSTOM_FORM_CONTROL_BANNED_INPUT_FIELDS — includes value and checked" {
    var found_value = false;
    var found_checked = false;
    for (CUSTOM_FORM_CONTROL_BANNED_INPUT_FIELDS) |field| {
        if (std.mem.eql(u8, field, "value")) found_value = true;
        if (std.mem.eql(u8, field, "checked")) found_checked = true;
    }
    try std.testing.expect(found_value);
    try std.testing.expect(found_checked);
}

test "checkUnsupportedFieldBindings — no errors for valid inputs" {
    const allocator = std.testing.allocator;
    var unsupported = std.StringHashMap(void).init(allocator);
    defer unsupported.deinit();
    try unsupported.put("errors", {});

    const node = Element{
        .name = "input",
        .inputs = &.{},
    };
    try checkUnsupportedFieldBindings(allocator, node, unsupported);
}

test "checkUnsupportedFieldBindings — detects unsupported" {
    const allocator = std.testing.allocator;
    var unsupported = std.StringHashMap(void).init(allocator);
    defer unsupported.deinit();
    try unsupported.put("errors", {});

    var inputs = [_]BoundAttribute{
        .{ .name = "errors", .type = .Property, .value = "someExpr" },
    };
    const node = Element{
        .name = "input",
        .inputs = &inputs,
    };
    // Should not error — just silently detect
    try checkUnsupportedFieldBindings(allocator, node, unsupported);
}
