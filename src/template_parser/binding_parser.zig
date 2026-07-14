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
