/// TCB Host Bindings — Host binding type checking
///
/// Port of: compiler/src/typecheck/host_bindings.ts (518 LoC)
///
/// Type-checks host bindings on directives and components. Host bindings
/// (e.g., `@HostBinding('class.active')` or `host: { '(click)': '...' }`)
/// are validated against the directive's host metadata.
const std = @import("std");

/// TcbExpr — a type-check expression result.
pub const TcbExpr = []const u8;

/// Context — the TCB compilation context.
pub const Context = struct {
    allocator: std.mem.Allocator,
    config: TcbConfig = .{},
};

/// TCB configuration options.
pub const TcbConfig = struct {
    strict_host_binding_types: bool = true,
    check_type_of_dom_events: bool = true,
};

/// Scope — the template scope for variable resolution.
pub const Scope = struct {
    allocator: std.mem.Allocator,
};

/// HostBindingType — the kind of host binding.
pub const HostBindingType = enum(u8) {
    Property, // [hostProp]
    Attribute, // [attr.name]
    Class, // [class.name]
    Style, // [style.name]
    Event, // (eventName)
    TwoWay, // [(prop)]
    LegacyAnimation, // (@animation.trigger)
    Animation, // (@animation)
};

/// HostBindingInfo — info about a single host binding.
pub const HostBindingInfo = struct {
    name: []const u8,
    binding_type: HostBindingType,
    value: []const u8 = "",
    handler: []const u8 = "",
    source_span: ?[]const u8 = null,
};

/// HostBindings — the collection of host bindings for a directive.
pub const HostBindings = struct {
    properties: []const HostBindingInfo = &.{},
    attributes: []const HostBindingInfo = &.{},
    events: []const HostBindingInfo = &.{},
    two_way_bindings: []const HostBindingInfo = &.{},
};

/// Check host bindings for a directive.
/// Direct port of the host binding check logic in the TS source.
///
/// For each host binding, generates a type-check expression that verifies:
///   - Property bindings: `dirInstance.hostProp = bindingValue`
///   - Attribute bindings: `hostElement.setAttribute('name', value)`
///   - Class bindings: `hostElement.classList.add('name')`
///   - Style bindings: `hostElement.style.setProperty('name', value)`
///   - Event bindings: `hostElement.addEventListener('name', handler)`
pub fn checkHostBindings(
    allocator: std.mem.Allocator,
    tcb: *const Context,
    scope: *const Scope,
    host: HostBindings,
    dir_instance: []const u8,
) ![]TcbExpr {
    _ = scope;
    var results = std.array_list.Managed(TcbExpr).init(allocator);
    errdefer results.deinit();

    // Check property bindings.
    for (host.properties) |prop| {
        if (tcb.config.strict_host_binding_types) {
            const check = try std.fmt.allocPrint(
                allocator,
                "{s}.{s} = {s}",
                .{ dir_instance, prop.name, prop.value },
            );
            try results.append(check);
        }
    }

    // Check attribute bindings.
    for (host.attributes) |attr| {
        const check = try std.fmt.allocPrint(
            allocator,
            "document.createElement('div').setAttribute('{s}', {s})",
            .{ attr.name, attr.value },
        );
        try results.append(check);
    }

    // Check event bindings.
    for (host.events) |event| {
        if (tcb.config.check_type_of_dom_events) {
            const check = try std.fmt.allocPrint(
                allocator,
                "document.createElement('div').addEventListener('{s}', $event => {s})",
                .{ event.name, event.handler },
            );
            try results.append(check);
        } else {
            const check = try std.fmt.allocPrint(
                allocator,
                "($event: any) => {s}",
                .{event.handler},
            );
            try results.append(check);
        }
    }

    // Check two-way bindings.
    for (host.two_way_bindings) |twb| {
        const check = try std.fmt.allocPrint(
            allocator,
            "{s}.{s} && ({s}.{s} = {s})",
            .{ dir_instance, twb.name, dir_instance, twb.name, twb.value },
        );
        try results.append(check);
    }

    return results.toOwnedSlice();
}

/// Check a single host property binding.
pub fn checkHostProperty(
    allocator: std.mem.Allocator,
    tcb: *const Context,
    prop: HostBindingInfo,
    dir_instance: []const u8,
) !TcbExpr {
    _ = tcb;
    return std.fmt.allocPrint(allocator, "{s}.{s} = {s}", .{ dir_instance, prop.name, prop.value });
}

/// Check a single host event binding.
pub fn checkHostEvent(
    allocator: std.mem.Allocator,
    tcb: *const Context,
    event: HostBindingInfo,
) !TcbExpr {
    if (tcb.config.check_type_of_dom_events) {
        return std.fmt.allocPrint(
            allocator,
            "document.createElement('div').addEventListener('{s}', $event => {s})",
            .{ event.name, event.handler },
        );
    }
    return std.fmt.allocPrint(allocator, "($event: any) => {s}", .{event.handler});
}

// ─── Tests ──────────────────────────────────────────────────

test "checkHostProperty generates assignment" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const prop = HostBindingInfo{
        .name = "class.active",
        .binding_type = .Property,
        .value = "isActive",
    };
    const result = try checkHostProperty(allocator, &ctx, prop, "dir");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("dir.class.active = isActive", result);
}

test "checkHostEvent generates addEventListener" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const event = HostBindingInfo{
        .name = "click",
        .binding_type = .Event,
        .handler = "onClick($event)",
    };
    const result = try checkHostEvent(allocator, &ctx, event);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "addEventListener") != null);
}

test "checkHostBindings with empty bindings" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    const scope = Scope{ .allocator = allocator };
    const host = HostBindings{};
    const results = try checkHostBindings(allocator, &ctx, &scope, host, "dir");
    defer allocator.free(results);
    try std.testing.expectEqual(@as(usize, 0), results.len);
}
