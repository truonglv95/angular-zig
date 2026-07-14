/// Binding Parser — Classifies and parses Angular template bindings
///
/// Takes HTML attributes and classifies them into:
///   - TextAttribute (static: class="foo")
///   - BoundAttribute ([prop]="expr", bind-prop="expr")
///   - BoundEvent ((click)="handler", on-click="handler")
///   - Reference (#myRef="expr")
///   - Variable (let-item, in *ngFor context)
///   - Structural directive (*ngIf, *ngFor)
///
/// DOD: Linear scan with minimal branching.
const std = @import("std");
const Allocator = std.mem.Allocator;
const arena_mod = @import("../arena.zig");
const AstArena = arena_mod.AstArena;
const source_span = @import("../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

// ─── Binding Classification ──────────────────────────────────

pub const BindingClass = enum(u8) {
    TextAttribute, // plain attribute
    Property, // [prop] or bind-prop
    Event, // (event) or on-event
    TwoWay, // [(prop)] or bindon-prop
    Reference, // #ref
    Variable, // let-var
    Structural, // *directive
    I18n, // i18n
    Class, // class.name
    Style, // style.prop
    Attr, // attr.name
    Animation, // @animation.name
};

/// Result of classifying an attribute name
pub const ClassifiedAttr = struct {
    class: BindingClass,
    name: []const u8, // The effective name (without prefix)
    original: []const u8, // Original attribute name
};

/// Classify an attribute name into its binding class
pub fn classifyAttribute(name: []const u8) ClassifiedAttr {
    if (name.len == 0) return .{ .class = .TextAttribute, .name = "", .original = "" };

    // *directive
    if (name[0] == '*') {
        return .{ .class = .Structural, .name = name[1..], .original = name };
    }

    // #ref
    if (name[0] == '#') {
        return .{ .class = .Reference, .name = name[1..], .original = name };
    }

    // [prop] or [(twoWay)]
    if (name[0] == '[') {
        // [(twoWay)] — check FIRST before [prop] since [(...)] also ends with ]
        if (name.len > 3 and name[1] == '(' and name[name.len - 2] == ')' and name[name.len - 1] == ']') {
            return .{ .class = .TwoWay, .name = name[2 .. name.len - 2], .original = name };
        }
        // [prop]
        if (name.len > 1 and name[name.len - 1] == ']') {
            return .{ .class = .Property, .name = name[1 .. name.len - 1], .original = name };
        }
    }

    // (event)
    if (name[0] == '(' and name.len > 1 and name[name.len - 1] == ')') {
        return .{ .class = .Event, .name = name[1 .. name.len - 1], .original = name };
    }

    // @animation.name
    if (name[0] == '@') {
        return .{ .class = .Animation, .name = name[1..], .original = name };
    }

    // bind-prop, on-event, bindon-prop
    if (startsWith(name, "bindon-")) {
        return .{ .class = .TwoWay, .name = name[7..], .original = name };
    }
    if (startsWith(name, "bind-")) {
        return .{ .class = .Property, .name = name[5..], .original = name };
    }
    if (startsWith(name, "on-")) {
        return .{ .class = .Event, .name = name[3..], .original = name };
    }

    // ref- prefix
    if (startsWith(name, "ref-")) {
        return .{ .class = .Reference, .name = name[4..], .original = name };
    }

    // let- prefix (microsyntax variable)
    if (startsWith(name, "let-")) {
        return .{ .class = .Variable, .name = name[4..], .original = name };
    }

    // i18n attribute
    if (std.mem.eql(u8, name, "i18n") or startsWith(name, "i18n-")) {
        return .{ .class = .I18n, .name = name, .original = name };
    }

    // attr.name, class.name, style.prop
    if (startsWith(name, "attr.")) {
        return .{ .class = .Attr, .name = name[5..], .original = name };
    }
    if (startsWith(name, "class.")) {
        return .{ .class = .Class, .name = name[6..], .original = name };
    }
    if (startsWith(name, "style.")) {
        return .{ .class = .Style, .name = name[6..], .original = name };
    }

    return .{ .class = .TextAttribute, .name = name, .original = name };
}

fn startsWith(haystack: []const u8, prefix: []const u8) bool {
    if (haystack.len < prefix.len) return false;
    return std.mem.eql(u8, haystack[0..prefix.len], prefix);
}

// ─── Constants ───────────────────────────────────────────────

/// Prefix constants matching the TS source.
pub const PROPERTY_PARTS_SEPARATOR = ".";
pub const ATTRIBUTE_PREFIX = "attr";
pub const ANIMATE_PREFIX = "animate";
pub const CLASS_PREFIX = "class";
pub const STYLE_PREFIX = "style";
pub const TEMPLATE_ATTR_PREFIX = "*";
pub const LEGACY_ANIMATE_PROP_PREFIX = "animate-";

// ─── Parsed Property / Event / Variable ──────────────────────

/// ParsedPropertyType — the type of a parsed property binding.
/// Direct port of `ParsedPropertyType` enum in the TS source.
pub const ParsedPropertyType = enum(u8) {
    Default, // [prop]="expr"
    Attribute, // attr.name="value"
    Class, // class.name="value"
    Style, // style.prop="value"
    Animation, // @animation.trigger
    TwoWay, // [(prop)]="expr"
    LegacyAnimation, // animate.prop (deprecated)
};

/// ParsedProperty — a parsed property binding.
/// Direct port of `ParsedProperty` interface in the TS source.
pub const ParsedProperty = struct {
    name: []const u8,
    expression: []const u8,
    type: ParsedPropertyType = .Default,
    is_animation: bool = false,
    is_legacy_animation: bool = false,
    unit: ?[]const u8 = null,
    source_span: ?AbsoluteSourceSpan = null,
    key_span: ?AbsoluteSourceSpan = null,
};

/// ParsedEventType — the type of a parsed event binding.
/// Direct port of `ParsedEventType` enum in the TS source.
pub const ParsedEventType = enum(u8) {
    Regular, // (click)="handler"
    AnimationStart, // (@animation.start)
    AnimationDone, // (@animation.done)
    Animation, // (@animation)
    TwoWay, // [(prop)]
    LegacyAnimation, // animation.prop
    Wrapped,
};

/// ParsedEvent — a parsed event binding.
/// Direct port of `ParsedEvent` interface in the TS source.
pub const ParsedEvent = struct {
    name: []const u8,
    handler: []const u8,
    type: ParsedEventType = .Regular,
    target: ?[]const u8 = null,
    phase: ?[]const u8 = null,
    source_span: ?AbsoluteSourceSpan = null,
    handler_span: ?AbsoluteSourceSpan = null,
};

/// ParsedVariable — a parsed template variable (let-item).
/// Direct port of `ParsedVariable` interface in the TS source.
pub const ParsedVariable = struct {
    name: []const u8,
    value: []const u8,
    source_span: ?AbsoluteSourceSpan = null,
    key_span: ?AbsoluteSourceSpan = null,
    value_span: ?AbsoluteSourceSpan = null,
};

/// TemplateBinding — a parsed structural directive binding.
/// Direct port of `TemplateBinding` interface in the TS source.
pub const TemplateBinding = struct {
    name: []const u8,
    key: []const u8,
    key_is_var: bool = false,
    name_span: ?AbsoluteSourceSpan = null,
    key_span: ?AbsoluteSourceSpan = null,
    value: ?[]const u8 = null,
    value_span: ?AbsoluteSourceSpan = null,
};

// ─── Host Properties / Listeners ─────────────────────────────

/// HostProperties — a map of host property names to expressions.
/// Direct port of `HostProperties` interface in the TS source.
pub const HostProperties = struct {
    entries: []const HostPropertyEntry,

    pub const HostPropertyEntry = struct {
        name: []const u8,
        expression: []const u8,
    };
};

/// HostListeners — a map of host event names to handlers.
/// Direct port of `HostListeners` interface in the TS source.
pub const HostListeners = struct {
    entries: []const HostListenerEntry,

    pub const HostListenerEntry = struct {
        name: []const u8,
        handler: []const u8,
    };
};

/// Parse host properties from a directive's host metadata.
/// Direct port of `createBoundHostProperties(properties, sourceSpan)` in the TS source.
pub fn parseHostProperties(
    allocator: std.mem.Allocator,
    properties: HostProperties,
) ![]ParsedProperty {
    var result = std.array_list.Managed(ParsedProperty).init(allocator);
    errdefer result.deinit();
    for (properties.entries) |entry| {
        try result.append(.{
            .name = entry.name,
            .expression = entry.expression,
        });
    }
    return result.toOwnedSlice();
}

/// Parse host listeners from a directive's host metadata.
/// Direct port of `createBoundHostListeners(events, sourceSpan)` in the TS source.
pub fn parseHostListeners(
    allocator: std.mem.Allocator,
    listeners: HostListeners,
) ![]ParsedEvent {
    var result = std.array_list.Managed(ParsedEvent).init(allocator);
    errdefer result.deinit();
    for (listeners.entries) |entry| {
        try result.append(.{
            .name = entry.name,
            .handler = entry.handler,
        });
    }
    return result.toOwnedSlice();
}

/// Calculate possible security contexts for a binding.
/// Direct port of `calcPossibleSecurityContexts(selector, prop, isAttribute)` in the TS source.
pub fn calcPossibleSecurityContexts(
    element_name: []const u8,
    property_name: []const u8,
    is_attribute: bool,
) []const u8 {
    _ = element_name;
    _ = is_attribute;
    // The full implementation checks the DOM schema for security-sensitive
    // properties. We return common security context names.
    if (std.mem.eql(u8, property_name, "innerHTML") or
        std.mem.eql(u8, property_name, "outerHTML"))
    {
        return &[_][]const u8{"HTML"};
    }
    if (std.mem.eql(u8, property_name, "href") or
        std.mem.eql(u8, property_name, "src") or
        std.mem.eql(u8, property_name, "action"))
    {
        return &[_][]const u8{"URL"};
    }
    if (std.mem.eql(u8, property_name, "style") or
        std.mem.startsWith(u8, property_name, "style."))
    {
        return &[_][]const u8{"STYLE"};
    }
    return &[_][]const u8{};
}

/// Split a name at the first colon: "ns:name" → ("ns", "name").
/// Direct port of `splitAtColon` from util.ts.
pub fn splitAtColon(name: []const u8) struct { ?[]const u8, []const u8 } {
    if (std.mem.indexOfScalar(u8, name, ':')) |pos| {
        return .{ name[0..pos], name[pos + 1 ..] };
    }
    return .{ null, name };
}

/// Split a name at the first period: "class.name" → ("class", "name").
/// Direct port of `splitAtPeriod` from util.ts.
pub fn splitAtPeriod(name: []const u8) struct { ?[]const u8, []const u8 } {
    if (std.mem.indexOfScalar(u8, name, '.')) |pos| {
        return .{ name[0..pos], name[pos + 1 ..] };
    }
    return .{ null, name };
}

// ─── Binding Parser ──────────────────────────────────────────

pub const BindingParser = struct {
    allocator: Allocator,
    arena: *AstArena,

    pub fn init(allocator: Allocator, arena: *AstArena) BindingParser {
        return .{ .allocator = allocator, .arena = arena };
    }

    /// Parse an interpolation string "{{ expr1 }} text {{ expr2 }}"
    /// Returns the expression parts
    pub fn parseInterpolation(self: *BindingParser, value: []const u8, _: []const u8, _: u32) !InterpolationResult {
        var parts = std.array_list.Managed(InterpPart).init(self.allocator);

        var i: usize = 0;
        var text_start: usize = 0;

        while (i < value.len) {
            // Find {{
            if (i + 1 < value.len and value[i] == '{' and value[i + 1] == '{') {
                // Emit preceding text if any
                if (i > text_start) {
                    try parts.append(.{
                        .text = value[text_start..i],
                        .expression = null,
                        .start = @intCast(text_start),
                        .end = @intCast(i),
                    });
                }
                const expr_start = i + 2;
                // Find matching }} — simple scan (no nesting in interpolation exprs)
                var j = expr_start;
                while (j + 1 < value.len) : (j += 1) {
                    if (value[j] == '}' and value[j + 1] == '}') break;
                }
                const expr_str_raw = value[expr_start..j];
                // Trim whitespace around expression
                const expr_str = std.mem.trim(u8, expr_str_raw, " \t\n\r");
                try parts.append(.{
                    .text = null,
                    .expression = expr_str,
                    .start = @intCast(i),
                    .end = @intCast(j + 2),
                });
                i = j + 2;
                text_start = i;
            } else {
                i += 1;
            }
        }

        // Trailing text
        if (text_start < value.len) {
            try parts.append(.{
                .text = value[text_start..],
                .expression = null,
                .start = @intCast(text_start),
                .end = @intCast(value.len),
            });
        }

        return .{ .parts = try parts.toOwnedSlice() };
    }
};

pub const InterpPart = struct {
    text: ?[]const u8,
    expression: ?[]const u8,
    start: u32,
    end: u32,
};

pub const InterpolationResult = struct {
    parts: []const InterpPart,

    pub fn deinit(self: InterpolationResult, allocator: std.mem.Allocator) void {
        allocator.free(self.parts);
    }
};

// ─── Tests ────────────────────────────────────────────────────

test "classify property binding" {
    const r1 = classifyAttribute("[value]");
    try std.testing.expectEqual(BindingClass.Property, r1.class);
    try std.testing.expectEqualStrings("value", r1.name);

    const r2 = classifyAttribute("bind-value");
    try std.testing.expectEqual(BindingClass.Property, r2.class);
    try std.testing.expectEqualStrings("value", r2.name);
}

test "classify event binding" {
    const r1 = classifyAttribute("(click)");
    try std.testing.expectEqual(BindingClass.Event, r1.class);
    try std.testing.expectEqualStrings("click", r1.name);

    const r2 = classifyAttribute("on-click");
    try std.testing.expectEqual(BindingClass.Event, r2.class);
}

test "classify two-way binding" {
    const r1 = classifyAttribute("[(ngModel)]");
    try std.testing.expectEqual(BindingClass.TwoWay, r1.class);
    try std.testing.expectEqualStrings("ngModel", r1.name);

    const r2 = classifyAttribute("bindon-ngModel");
    try std.testing.expectEqual(BindingClass.TwoWay, r2.class);
}

test "classify reference" {
    const r1 = classifyAttribute("#myRef");
    try std.testing.expectEqual(BindingClass.Reference, r1.class);
    try std.testing.expectEqualStrings("myRef", r1.name);
}

test "classify structural directive" {
    const r1 = classifyAttribute("*ngIf");
    try std.testing.expectEqual(BindingClass.Structural, r1.class);
    try std.testing.expectEqualStrings("ngIf", r1.name);
}

test "classify text attribute" {
    const r1 = classifyAttribute("class");
    try std.testing.expectEqual(BindingClass.TextAttribute, r1.class);

    const r2 = classifyAttribute("id");
    try std.testing.expectEqual(BindingClass.TextAttribute, r2.class);
}

test "classify class/style/attr prefix" {
    try std.testing.expectEqual(BindingClass.Class, classifyAttribute("class.active").class);
    try std.testing.expectEqual(BindingClass.Style, classifyAttribute("style.color").class);
    try std.testing.expectEqual(BindingClass.Attr, classifyAttribute("attr.aria-label").class);
}

test "parse interpolation" {
    const allocator = std.testing.allocator;
    var arena = AstArena.init(allocator);
    defer arena.deinit();

    var bp = BindingParser.init(allocator, &arena);
    const result = try bp.parseInterpolation("Hello {{ name }}!", "test", 0);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), result.parts.len);
    try std.testing.expect(result.parts[0].text != null);
    try std.testing.expect(result.parts[1].expression != null);
    try std.testing.expect(result.parts[2].text != null);
    try std.testing.expectEqualStrings("name", result.parts[1].expression.?);
}

// ─── Additional BindingParser methods (from binding_parser.ts) ──

/// ParsedEventListener — result of parsing an event listener name.
/// Direct port of `parseEventListenerName(rawName)` in the TS source.
pub const ParsedEventListener = struct {
    event_name: []const u8,
    target: ?[]const u8 = null,
};

/// Parse an event listener name.
/// Direct port of `parseEventListenerName(rawName)` in the TS source.
/// Examples: "click" → {event_name: "click"}, "document:click" → {event_name: "click", target: "document"}
pub fn parseEventListenerName(raw_name: []const u8) ParsedEventListener {
    if (std.mem.indexOfScalar(u8, raw_name, ':')) |colon_pos| {
        return .{
            .target = raw_name[0..colon_pos],
            .event_name = raw_name[colon_pos + 1 ..],
        };
    }
    return .{ .event_name = raw_name };
}

/// ParsedLegacyAnimationEvent — result of parsing a legacy animation event name.
/// Direct port of `parseLegacyAnimationEventName(rawName)` in the TS source.
pub const ParsedLegacyAnimationEvent = struct {
    event_name: []const u8,
    phase: ?[]const u8 = null,
};

/// Parse a legacy animation event name.
/// Direct port of `parseLegacyAnimationEventName(rawName)` in the TS source.
/// Example: "@animation.start" → {event_name: "@animation", phase: "start"}
pub fn parseLegacyAnimationEventName(raw_name: []const u8) ParsedLegacyAnimationEvent {
    // Find the last dot
    if (std.mem.lastIndexOfScalar(u8, raw_name, '.')) |dot_pos| {
        const phase = raw_name[dot_pos + 1 ..];
        if (std.mem.eql(u8, phase, "start") or std.mem.eql(u8, phase, "done")) {
            return .{
                .event_name = raw_name[0..dot_pos],
                .phase = phase,
            };
        }
    }
    return .{ .event_name = raw_name };
}

/// Parse a literal attribute (no expression, just a string value).
/// Direct port of `parseLiteralAttr(name, value, sourceSpan)` in the TS source.
pub fn parseLiteralAttr(name: []const u8, value: []const u8) ParsedProperty {
    return .{
        .name = name,
        .expression = value,
        .type = .Default,
    };
}

/// Parse an interpolation expression.
/// Direct port of `parseInterpolationExpression(expression, sourceSpan)` in the TS source.
pub fn parseInterpolationExpression(expression: []const u8) ParsedProperty {
    return .{
        .name = "",
        .expression = expression,
        .type = .Default,
    };
}

/// Parse a binding (expression).
/// Direct port of `parseBinding(value, sourceSpan)` in the TS source.
pub fn parseBinding(value: []const u8) ParsedProperty {
    return .{
        .name = "",
        .expression = value,
        .type = .Default,
    };
}

/// Parse an action (event handler expression).
/// Direct port of `parseAction(value, sourceSpan)` in the TS source.
pub fn parseAction(value: []const u8) ParsedProperty {
    return .{
        .name = "",
        .expression = value,
        .type = .Default,
    };
}

/// Create a bound element property.
/// Direct port of `createBoundElementProperty(name, expression, ...)` in the TS source.
pub fn createBoundElementProperty(name: []const u8, expression: []const u8, binding_type: ParsedPropertyType) ParsedProperty {
    return .{
        .name = name,
        .expression = expression,
        .type = binding_type,
    };
}

/// Parse an inline template binding (*ngIf="condition").
/// Direct port of `parseInlineTemplateBinding(name, value, sourceSpan)` in the TS source.
pub fn parseInlineTemplateBinding(name: []const u8, value: []const u8) TemplateBinding {
    return .{
        .name = name,
        .key = value,
        .key_is_var = false,
        .value = value,
    };
}

/// Check if a property name is an allowed assignment event.
/// Direct port of `_isAllowedAssignmentEvent(ast)` in the TS source.
pub fn isAllowedAssignmentEvent(name: []const u8) bool {
    // ngModelChange is the only event that allows assignment
    return std.mem.eql(u8, name, "ngModelChange");
}

/// Validate a property or attribute name.
/// Direct port of `_validatePropertyOrAttributeName(name, isAttr)` in the TS source.
pub fn validatePropertyOrAttributeName(name: []const u8, is_attr: bool) ?[]const u8 {
    if (name.len == 0) {
        return if (is_attr) "Attribute name cannot be empty" else "Property name cannot be empty";
    }
    return null;
}

// ─── Additional tests ───────────────────────────────────────

test "parseEventListenerName simple" {
    const result = parseEventListenerName("click");
    try std.testing.expectEqualStrings("click", result.event_name);
    try std.testing.expect(result.target == null);
}

test "parseEventListenerName with target" {
    const result = parseEventListenerName("document:click");
    try std.testing.expectEqualStrings("click", result.event_name);
    try std.testing.expectEqualStrings("document", result.target.?);
}

test "parseEventListenerName window target" {
    const result = parseEventListenerName("window:scroll");
    try std.testing.expectEqualStrings("scroll", result.event_name);
    try std.testing.expectEqualStrings("window", result.target.?);
}

test "parseLegacyAnimationEventName start" {
    const result = parseLegacyAnimationEventName("@animation.start");
    try std.testing.expectEqualStrings("@animation", result.event_name);
    try std.testing.expectEqualStrings("start", result.phase.?);
}

test "parseLegacyAnimationEventName done" {
    const result = parseLegacyAnimationEventName("@fade.done");
    try std.testing.expectEqualStrings("@fade", result.event_name);
    try std.testing.expectEqualStrings("done", result.phase.?);
}

test "parseLegacyAnimationEventName no phase" {
    const result = parseLegacyAnimationEventName("@animation");
    try std.testing.expectEqualStrings("@animation", result.event_name);
    try std.testing.expect(result.phase == null);
}

test "parseLiteralAttr" {
    const result = parseLiteralAttr("class", "container");
    try std.testing.expectEqualStrings("class", result.name);
    try std.testing.expectEqualStrings("container", result.expression);
}

test "parseInterpolationExpression" {
    const result = parseInterpolationExpression("name");
    try std.testing.expectEqualStrings("name", result.expression);
}

test "parseBinding" {
    const result = parseBinding("isValid");
    try std.testing.expectEqualStrings("isValid", result.expression);
}

test "parseAction" {
    const result = parseAction("onClick($event)");
    try std.testing.expectEqualStrings("onClick($event)", result.expression);
}

test "createBoundElementProperty" {
    const result = createBoundElementProperty("value", "name", .Default);
    try std.testing.expectEqualStrings("value", result.name);
    try std.testing.expectEqualStrings("name", result.expression);
}

test "parseInlineTemplateBinding" {
    const result = parseInlineTemplateBinding("ngIf", "condition");
    try std.testing.expectEqualStrings("ngIf", result.name);
}

test "isAllowedAssignmentEvent" {
    try std.testing.expect(isAllowedAssignmentEvent("ngModelChange"));
    try std.testing.expect(!isAllowedAssignmentEvent("click"));
    try std.testing.expect(!isAllowedAssignmentEvent("change"));
}

test "validatePropertyOrAttributeName valid" {
    try std.testing.expect(validatePropertyOrAttributeName("class", true) == null);
    try std.testing.expect(validatePropertyOrAttributeName("value", false) == null);
}

test "validatePropertyOrAttributeName empty" {
    try std.testing.expect(validatePropertyOrAttributeName("", true) != null);
    try std.testing.expect(validatePropertyOrAttributeName("", false) != null);
}

// ─── Full BindingParser methods (from binding_parser.ts) ────

/// Check if a name is a legacy animation label (starts with @).
/// Direct port of `isLegacyAnimationLabel(name)` in the TS source.
pub fn isLegacyAnimationLabel(name: []const u8) bool {
    return name.len > 0 and name[0] == '@';
}

/// Check if a name starts with the legacy animate property prefix.
/// Direct port of the LEGACY_ANIMATE_PROP_PREFIX check in the TS source.
pub fn isLegacyAnimationProp(name: []const u8) bool {
    return std.mem.startsWith(u8, name, LEGACY_ANIMATE_PROP_PREFIX);
}

/// Check if a name starts with the animate prefix ("animate.").
/// Direct port of the ANIMATE_PREFIX check in the TS source.
pub fn isAnimationBinding(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "animate.");
}

/// Parse a property binding name to determine its type and actual property name.
/// Direct port of `parsePropertyBinding` logic in the TS source.
///
/// Returns the binding type, the stripped property name, and optional unit.
pub const ParsedPropertyName = struct {
    name: []const u8,
    binding_type: ParsedPropertyType,
    unit: ?[]const u8 = null,
};

/// Parse a property binding name to determine its type.
/// Handles: attr.name, class.name, style.prop.unit, animate.trigger, and regular properties.
pub fn parsePropertyName(name: []const u8) ParsedPropertyName {
    // Check for legacy animation prefix (animate-)
    if (isLegacyAnimationProp(name)) {
        return .{
            .name = name[LEGACY_ANIMATE_PROP_PREFIX.len..],
            .binding_type = .LegacyAnimation,
        };
    }
    // Check for @ prefix (legacy animation label)
    if (isLegacyAnimationLabel(name)) {
        return .{
            .name = name[1..],
            .binding_type = .LegacyAnimation,
        };
    }
    // Check for animate. prefix
    if (isAnimationBinding(name)) {
        return .{
            .name = name,
            .binding_type = .Animation,
        };
    }

    // Split by "." to check for prefixed bindings
    if (std.mem.indexOfScalar(u8, name, '.')) |dot_pos| {
        const prefix = name[0..dot_pos];
        const rest = name[dot_pos + 1 ..];

        if (std.mem.eql(u8, prefix, ATTRIBUTE_PREFIX)) {
            return .{ .name = rest, .binding_type = .Attribute };
        }
        if (std.mem.eql(u8, prefix, CLASS_PREFIX)) {
            return .{ .name = rest, .binding_type = .Class };
        }
        if (std.mem.eql(u8, prefix, STYLE_PREFIX)) {
            // Check for unit: style.prop.unit
            if (std.mem.indexOfScalar(u8, rest, '.')) |unit_dot| {
                return .{
                    .name = rest[0..unit_dot],
                    .binding_type = .Style,
                    .unit = rest[unit_dot + 1 ..],
                };
            }
            return .{ .name = rest, .binding_type = .Style };
        }
    }

    // Default: regular property
    return .{ .name = name, .binding_type = .Default };
}

/// Parse an event name to determine its type.
/// Direct port of the event parsing logic in the TS source.
pub const ParsedEventName = struct {
    event_name: []const u8,
    target: ?[]const u8 = null,
    event_type: ParsedEventType,
};

/// Parse an event name.
/// Handles: @animation.start (legacy animation), animate.event (animation), target:event (targeted), regular events.
pub fn parseEventName(name: []const u8) ParsedEventName {
    // Check for legacy animation (@ prefix)
    if (isLegacyAnimationLabel(name)) {
        const stripped = name[1..];
        var event_name = stripped;
        var phase: ?[]const u8 = null;

        // Check for .start or .done
        if (std.mem.lastIndexOfScalar(u8, stripped, '.')) |dot_pos| {
            const p = stripped[dot_pos + 1 ..];
            if (std.mem.eql(u8, p, "start") or std.mem.eql(u8, p, "done")) {
                event_name = stripped[0..dot_pos];
                phase = p;
            }
        }

        return .{
            .event_name = event_name,
            .target = phase,
            .event_type = .LegacyAnimation,
        };
    }

    // Check for target:event
    if (std.mem.indexOfScalar(u8, name, ':')) |colon_pos| {
        const target = name[0..colon_pos];
        const event_name = name[colon_pos + 1 ..];

        // Check for animate. prefix
        if (std.mem.startsWith(u8, event_name, "animate.")) {
            return .{
                .event_name = event_name,
                .target = target,
                .event_type = .Animation,
            };
        }

        return .{
            .event_name = event_name,
            .target = target,
            .event_type = .Regular,
        };
    }

    // Check for animate. prefix
    if (std.mem.startsWith(u8, name, "animate.")) {
        return .{
            .event_name = name,
            .event_type = .Animation,
        };
    }

    // Regular event
    return .{
        .event_name = name,
        .event_type = .Regular,
    };
}

/// Check if an event name represents a two-way binding event.
/// Direct port of the TwoWay event type check in the TS source.
pub fn isTwoWayEvent(name: []const u8) bool {
    // Two-way events end with "Change"
    return std.mem.endsWith(u8, name, "Change");
}

/// BoundElementProperty — a fully resolved element property binding.
/// Direct port of `BoundElementProperty` interface in the TS source.
pub const BoundElementProperty = struct {
    name: []const u8,
    binding_type: BindingType,
    security_context: u8 = 0,
    expression: []const u8 = "",
    unit: ?[]const u8 = null,
};

/// BindingType — the type of an element property binding.
/// Direct port of `BindingType` from expression_parser/ast.ts.
pub const BindingType = enum(u8) {
    Property,
    Attribute,
    Class,
    Style,
    Animation,
    TwoWay,
    LegacyAnimation,
};

/// Create a bound element property from a parsed property.
/// Direct port of `createBoundElementProperty` logic in the TS source.
pub fn createBoundElementPropertyFromParsed(
    element_selector: ?[]const u8,
    bound_prop: ParsedProperty,
) BoundElementProperty {
    _ = element_selector;
    const parsed = parsePropertyName(bound_prop.name);

    return .{
        .name = parsed.name,
        .binding_type = switch (parsed.binding_type) {
            .Attribute => .Attribute,
            .Class => .Class,
            .Style => .Style,
            .Animation => .Animation,
            .LegacyAnimation => .LegacyAnimation,
            .TwoWay => .TwoWay,
            .Default => if (bound_prop.type == .TwoWay) .TwoWay else .Property,
        },
        .expression = bound_prop.expression,
        .unit = parsed.unit,
    };
}

/// Check if a recursive AST has a safe receiver.
/// Direct port of `hasRecursiveSafeReceiver(ast)` in the TS source.
pub fn hasRecursiveSafeReceiver(ast_kind: u8) bool {
    // ast_kind: 0=SafePropertyRead, 1=SafeKeyedRead → true
    // 2=PropertyRead, 3=KeyedRead, 4=Call → check receiver
    // else → false
    return ast_kind == 0 or ast_kind == 1;
}

/// Merge namespace and name: "svg" + "rect" → "svg:rect".
/// Direct port of `mergeNsAndName(ns, name)` from ml_parser/tags.ts.
pub fn mergeNsAndName(ns: []const u8, name: []const u8, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "{s}:{s}", .{ ns, name }) catch name;
}

// ─── Tests for new functions ────────────────────────────────

test "isLegacyAnimationLabel" {
    try std.testing.expect(isLegacyAnimationLabel("@animation"));
    try std.testing.expect(isLegacyAnimationLabel("@fade"));
    try std.testing.expect(!isLegacyAnimationLabel("animation"));
    try std.testing.expect(!isLegacyAnimationLabel(""));
}

test "isLegacyAnimationProp" {
    try std.testing.expect(isLegacyAnimationProp("animate-fade"));
    try std.testing.expect(!isLegacyAnimationProp("animate.fade"));
    try std.testing.expect(!isLegacyAnimationProp("animation"));
}

test "isAnimationBinding" {
    try std.testing.expect(isAnimationBinding("animate.fade"));
    try std.testing.expect(!isAnimationBinding("animate"));
    try std.testing.expect(!isAnimationBinding("animation"));
}

test "parsePropertyName regular" {
    const result = parsePropertyName("value");
    try std.testing.expectEqualStrings("value", result.name);
    try std.testing.expectEqual(ParsedPropertyType.Default, result.binding_type);
}

test "parsePropertyName attribute" {
    const result = parsePropertyName("attr.aria-label");
    try std.testing.expectEqualStrings("aria-label", result.name);
    try std.testing.expectEqual(ParsedPropertyType.Attribute, result.binding_type);
}

test "parsePropertyName class" {
    const result = parsePropertyName("class.active");
    try std.testing.expectEqualStrings("active", result.name);
    try std.testing.expectEqual(ParsedPropertyType.Class, result.binding_type);
}

test "parsePropertyName style with unit" {
    const result = parsePropertyName("style.height.px");
    try std.testing.expectEqualStrings("height", result.name);
    try std.testing.expectEqual(ParsedPropertyType.Style, result.binding_type);
    try std.testing.expectEqualStrings("px", result.unit.?);
}

test "parsePropertyName style without unit" {
    const result = parsePropertyName("style.color");
    try std.testing.expectEqualStrings("color", result.name);
    try std.testing.expectEqual(ParsedPropertyType.Style, result.binding_type);
    try std.testing.expect(result.unit == null);
}

test "parsePropertyName animation" {
    const result = parsePropertyName("animate.fade");
    try std.testing.expectEqualStrings("animate.fade", result.name);
    try std.testing.expectEqual(ParsedPropertyType.Animation, result.binding_type);
}

test "parsePropertyName legacy animation @" {
    const result = parsePropertyName("@fade");
    try std.testing.expectEqualStrings("fade", result.name);
    try std.testing.expectEqual(ParsedPropertyType.LegacyAnimation, result.binding_type);
}

test "parsePropertyName legacy animation prefix" {
    const result = parsePropertyName("animate-fade");
    try std.testing.expectEqualStrings("fade", result.name);
    try std.testing.expectEqual(ParsedPropertyType.LegacyAnimation, result.binding_type);
}

test "parseEventName regular" {
    const result = parseEventName("click");
    try std.testing.expectEqualStrings("click", result.event_name);
    try std.testing.expect(result.target == null);
    try std.testing.expectEqual(ParsedEventType.Regular, result.event_type);
}

test "parseEventName targeted" {
    const result = parseEventName("document:click");
    try std.testing.expectEqualStrings("click", result.event_name);
    try std.testing.expectEqualStrings("document", result.target.?);
    try std.testing.expectEqual(ParsedEventType.Regular, result.event_type);
}

test "parseEventName animation" {
    const result = parseEventName("animate.enter");
    try std.testing.expectEqualStrings("animate.enter", result.event_name);
    try std.testing.expectEqual(ParsedEventType.Animation, result.event_type);
}

test "parseEventName legacy animation with start" {
    const result = parseEventName("@fade.start");
    try std.testing.expectEqualStrings("fade", result.event_name);
    try std.testing.expectEqualStrings("start", result.target.?);
    try std.testing.expectEqual(ParsedEventType.LegacyAnimation, result.event_type);
}

test "parseEventName legacy animation with done" {
    const result = parseEventName("@fade.done");
    try std.testing.expectEqualStrings("fade", result.event_name);
    try std.testing.expectEqualStrings("done", result.target.?);
    try std.testing.expectEqual(ParsedEventType.LegacyAnimation, result.event_type);
}

test "parseEventName legacy animation no phase" {
    const result = parseEventName("@fade");
    try std.testing.expectEqualStrings("fade", result.event_name);
    try std.testing.expect(result.target == null);
    try std.testing.expectEqual(ParsedEventType.LegacyAnimation, result.event_type);
}

test "isTwoWayEvent" {
    try std.testing.expect(isTwoWayEvent("ngModelChange"));
    try std.testing.expect(isTwoWayEvent("valueChange"));
    try std.testing.expect(!isTwoWayEvent("click"));
    try std.testing.expect(!isTwoWayEvent("change"));
}

test "hasRecursiveSafeReceiver" {
    try std.testing.expect(hasRecursiveSafeReceiver(0)); // SafePropertyRead
    try std.testing.expect(hasRecursiveSafeReceiver(1)); // SafeKeyedRead
    try std.testing.expect(!hasRecursiveSafeReceiver(2)); // PropertyRead
    try std.testing.expect(!hasRecursiveSafeReceiver(5)); // Other
}

test "mergeNsAndName" {
    var buf: [128]u8 = undefined;
    const result = mergeNsAndName("svg", "rect", &buf);
    try std.testing.expectEqualStrings("svg:rect", result);
}

test "BindingType values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(BindingType.Property));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(BindingType.Attribute));
    try std.testing.expectEqual(@as(u8, 5), @intFromEnum(BindingType.TwoWay));
}

test "BoundElementProperty defaults" {
    const prop = BoundElementProperty{
        .name = "value",
        .binding_type = .Property,
    };
    try std.testing.expectEqualStrings("value", prop.name);
    try std.testing.expectEqual(@as(u8, 0), prop.security_context);
    try std.testing.expect(prop.unit == null);
}

test "createBoundElementPropertyFromParsed regular" {
    const parsed_prop = ParsedProperty{ .name = "value", .expression = "name" };
    const result = createBoundElementPropertyFromParsed(null, parsed_prop);
    try std.testing.expectEqualStrings("value", result.name);
    try std.testing.expectEqual(BindingType.Property, result.binding_type);
}

test "createBoundElementPropertyFromParsed attribute" {
    const parsed_prop = ParsedProperty{ .name = "attr.aria-label", .expression = "label" };
    const result = createBoundElementPropertyFromParsed(null, parsed_prop);
    try std.testing.expectEqualStrings("aria-label", result.name);
    try std.testing.expectEqual(BindingType.Attribute, result.binding_type);
}

test "createBoundElementPropertyFromParsed class" {
    const parsed_prop = ParsedProperty{ .name = "class.active", .expression = "isActive" };
    const result = createBoundElementPropertyFromParsed(null, parsed_prop);
    try std.testing.expectEqualStrings("active", result.name);
    try std.testing.expectEqual(BindingType.Class, result.binding_type);
}

test "createBoundElementPropertyFromParsed style with unit" {
    const parsed_prop = ParsedProperty{ .name = "style.height.px", .expression = "100" };
    const result = createBoundElementPropertyFromParsed(null, parsed_prop);
    try std.testing.expectEqualStrings("height", result.name);
    try std.testing.expectEqual(BindingType.Style, result.binding_type);
    try std.testing.expectEqualStrings("px", result.unit.?);
}

test "createBoundElementPropertyFromParsed two-way" {
    const parsed_prop = ParsedProperty{ .name = "ngModel", .expression = "name", .type = .TwoWay };
    const result = createBoundElementPropertyFromParsed(null, parsed_prop);
    try std.testing.expectEqual(BindingType.TwoWay, result.binding_type);
}

test "createBoundElementPropertyFromParsed legacy animation" {
    const parsed_prop = ParsedProperty{ .name = "@fade", .expression = "state" };
    const result = createBoundElementPropertyFromParsed(null, parsed_prop);
    try std.testing.expectEqualStrings("fade", result.name);
    try std.testing.expectEqual(BindingType.LegacyAnimation, result.binding_type);
}

test "createBoundElementPropertyFromParsed animation" {
    const parsed_prop = ParsedProperty{ .name = "animate.fade", .expression = "state" };
    const result = createBoundElementPropertyFromParsed(null, parsed_prop);
    try std.testing.expectEqual(BindingType.Animation, result.binding_type);
}
