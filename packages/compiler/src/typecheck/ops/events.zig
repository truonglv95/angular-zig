/// TCB Ops Events — Event binding TCB operations
///
/// Port of: compiler/src/typecheck/ops/events.ts (328 LoC)
///
/// This module generates TypeScript type-checking expressions for event
/// bindings in Angular templates. Each event binding (e.g., `(click)="onClick($event)"`)
/// is converted into a type-checked expression that verifies the handler's
/// parameter type matches the event's output type.
const std = @import("std");

/// The `$event` parameter name used in event handler expressions.
/// Direct port of `EVENT_PARAMETER` in the TS source.
pub const EVENT_PARAMETER = "$event";

/// How the `$event` parameter's type should be determined.
/// Direct port of `EventParamType` enum in the TS source.
pub const EventParamType = enum(u8) {
    /// Generates code to infer the type of `$event` based on how the
    /// listener is registered.
    Infer,

    /// Declares the type of the `$event` parameter as `any`.
    Any,
};

/// TcbExpr — a type-check expression result (string representation of TS code).
pub const TcbExpr = []const u8;

/// Context — the TCB compilation context.
/// In the full implementation, this holds the TypeScript AST builder,
/// environment, and configuration. Here we use a simplified struct.
pub const Context = struct {
    allocator: std.mem.Allocator,
    config: TcbConfig = .{},
};

/// TCB configuration options.
pub const TcbConfig = struct {
    check_type_of_output_events: bool = true,
    check_type_of_dom_events: bool = true,
    check_type_of_animation_events: bool = true,
    strict_null_checks: bool = true,
};

/// Scope — the template scope for variable resolution.
pub const Scope = struct {
    allocator: std.mem.Allocator,
    parent: ?*const Scope = null,
};

/// DirectiveOwner — identifies what owns a directive (element or template).
pub const DirectiveOwner = u32;

/// BoundEvent — mirrors `r3_ast.BoundEvent` for TCB purposes.
pub const BoundEvent = struct {
    name: []const u8,
    type: u8 = 0, // ParsedEventType
    handler: []const u8 = "",
    target: ?[]const u8 = null,
    phase: ?[]const u8 = null,
};

/// BoundAttribute — mirrors `r3_ast.BoundAttribute` for TCB purposes.
pub const BoundAttribute = struct {
    name: []const u8,
    type: u8 = 0,
    value: []const u8 = "",
};

/// TcbDirectiveMetadata — metadata about a directive being type-checked.
pub const TcbDirectiveMetadata = struct {
    name: []const u8,
    inputs: []const []const u8 = &.{},
    outputs: []const []const u8 = &.{},
    is_generic: bool = false,
};

/// Convert an event handler AST expression into a TCB expression.
/// Direct port of `tcbEventHandlerExpression(ast, tcb, scope)` in the TS source.
///
/// The handler expression is translated with special handling of `$event`:
///   - If `param_type` is `Infer`, `$event` is typed based on the directive's
///     output type.
///   - If `param_type` is `Any`, `$event` is typed as `any`.
pub fn tcbEventHandlerExpression(
    allocator: std.mem.Allocator,
    ast: []const u8,
    tcb: *const Context,
    scope: *const Scope,
    param_type: EventParamType,
) !TcbExpr {
    _ = scope;
    _ = tcb;
    // The full implementation creates a TcbEventHandlerTranslator and calls
    // translator.translate(ast). Here we return the expression with the
    // $event parameter declaration prepended.
    const param_decl: []const u8 = switch (param_type) {
        .Infer => EVENT_PARAMETER,
        .Any => "$event: any",
    };
    return std.fmt.allocPrint(allocator, "({s}) => {s}", .{ param_decl, ast });
}

/// Check event bindings on a directive.
/// Direct port of `TcbDirectiveOutputsOp.execute()` in the TS source.
///
/// For each output event binding that matches a directive output:
///   1. Resolve the directive instance ID
///   2. Translate the handler expression
///   3. Generate a type-check expression: `dirInstance.outputName.subscribe(handler)`
pub fn checkDirectiveOutputs(
    allocator: std.mem.Allocator,
    tcb: *const Context,
    scope: *const Scope,
    node: DirectiveOwner,
    inputs: ?[]const BoundAttribute,
    outputs: []const BoundEvent,
    dir: TcbDirectiveMetadata,
) ![]TcbExpr {
    _ = node;
    var results = std.array_list.Managed(TcbExpr).init(allocator);
    errdefer results.deinit();

    for (outputs) |output| {
        // Skip legacy animation events and events that don't match directive outputs.
        if (output.type == 5) continue; // ParsedEventType.LegacyAnimation
        if (!hasBindingPropertyName(dir.outputs, output.name)) continue;

        // Check if this is a two-way binding output (ends with 'Change').
        const is_two_way = inputs != null and std.mem.endsWith(u8, output.name, "Change");

        if (tcb.config.check_type_of_output_events and is_two_way) {
            // Generate two-way binding check.
            const handler_expr = try tcbEventHandlerExpression(
                allocator, output.handler, tcb, scope, .Infer,
            );
            const check = try std.fmt.allocPrint(
                allocator,
                "{s}.{s} && {s}",
                .{ dir.name, output.name, handler_expr },
            );
            try results.append(check);
        } else if (tcb.config.check_type_of_output_events) {
            // Generate output subscribe check.
            const handler_expr = try tcbEventHandlerExpression(
                allocator, output.handler, tcb, scope, .Infer,
            );
            const check = try std.fmt.allocPrint(
                allocator,
                "{s}.{s}.subscribe({s})",
                .{ dir.name, output.name, handler_expr },
            );
            try results.append(check);
        } else {
            // Just check the handler expression with `any` $event.
            const handler_expr = try tcbEventHandlerExpression(
                allocator, output.handler, tcb, scope, .Any,
            );
            try results.append(handler_expr);
        }
    }

    return results.toOwnedSlice();
}

/// Check if a directive outputs list contains a binding property name.
/// Direct port of `outputs.hasBindingPropertyName(name)` in the TS source.
fn hasBindingPropertyName(outputs: []const []const u8, name: []const u8) bool {
    for (outputs) |output| {
        if (std.mem.eql(u8, output, name)) return true;
    }
    return false;
}

/// Check a DOM event binding (non-directive event on an element).
/// Generates a type-check expression for DOM events like `(click)`, `(input)`.
pub fn checkDomEvent(
    allocator: std.mem.Allocator,
    tcb: *const Context,
    scope: *const Scope,
    event: BoundEvent,
) !TcbExpr {
    _ = scope;
    if (!tcb.config.check_type_of_dom_events) {
        // Just return the handler with `any` $event.
        return std.fmt.allocPrint(allocator, "($event: any) => {s}", .{event.name});
    }
    // Generate: `((el: HTMLElement) => el.addEventListener("name", $event => handler))`
    return std.fmt.allocPrint(
        allocator,
        "((el: HTMLElement) => (el.addEventListener(\"{s}\", $event => {s})))",
        .{ event.name, event.handler },
    );
}

/// Check an animation event binding.
/// Generates a type-check expression for animation events like `(@animation.start)`.
pub fn checkAnimationEvent(
    allocator: std.mem.Allocator,
    tcb: *const Context,
    scope: *const Scope,
    event: BoundEvent,
) !TcbExpr {
    _ = scope;
    if (!tcb.config.check_type_of_animation_events) {
        return std.fmt.allocPrint(allocator, "($event: any) => {s}", .{event.name});
    }
    // Animation events have a specific event type.
    return std.fmt.allocPrint(
        allocator,
        "((el: HTMLElement) => (el.addEventListener(\"{s}\", $event: AnimationEvent => {s})))",
        .{ event.name, event.handler },
    );
}

/// Check a two-way binding event.
/// Direct port of the two-way binding check logic in `TcbDirectiveOutputsOp`.
///
/// Two-way bindings (`[(ngModel)]`) generate both:
///   1. An input check on the property
///   2. An output check on the `nameChange` event
pub fn checkTwoWayBinding(
    allocator: std.mem.Allocator,
    tcb: *const Context,
    scope: *const Scope,
    event: BoundEvent,
    dir: TcbDirectiveMetadata,
) !?TcbExpr {
    _ = scope;
    if (!tcb.config.check_type_of_output_events) return null;

    // The output name for a two-way binding is `propNameChange`.
    // Check if this matches a directive output.
    if (!hasBindingPropertyName(dir.outputs, event.name)) return null;

    return std.fmt.allocPrint(
        allocator,
        "{s}.{s}.subscribe($event => {s})",
        .{ dir.name, event.name, event.handler },
    );
}

// ─── Tests ──────────────────────────────────────────────────

test "tcbEventHandlerExpression with Infer param type" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    const result = try tcbEventHandlerExpression(allocator, "onClick($event)", &ctx, &scope, .Infer);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("($event) => onClick($event)", result);
}

test "tcbEventHandlerExpression with Any param type" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    const result = try tcbEventHandlerExpression(allocator, "onClick($event)", &ctx, &scope, .Any);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("($event: any) => onClick($event)", result);
}

test "hasBindingPropertyName" {
    const outputs = [_][]const u8{ "click", "change", "ngModelChange" };
    try std.testing.expect(hasBindingPropertyName(&outputs, "click"));
    try std.testing.expect(hasBindingPropertyName(&outputs, "ngModelChange"));
    try std.testing.expect(!hasBindingPropertyName(&outputs, "submit"));
}

test "checkDomEvent generates addEventListener" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    const event = BoundEvent{ .name = "click", .handler = "onClick($event)" };
    const result = try checkDomEvent(allocator, &ctx, &scope, event);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "addEventListener") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "click") != null);
}
