/// DOM Security Schema — Maps elements/attributes to SecurityContext
///
/// Port of: compiler/src/schema/dom_security_schema.ts (214 LoC)
///
/// A SecurityContext marks a location that has dangerous security implications,
/// e.g. a DOM property like `innerHTML` that could cause Cross Site Scripting
/// (XSS) security bugs when improperly handled.
const std = @import("std");

/// SecurityContext — marks a location with dangerous security implications.
/// Direct port of `SecurityContext` enum in the TS source.
pub const SecurityContext = enum(u8) {
    NONE = 0,
    HTML = 1,
    STYLE = 2,
    SCRIPT = 3,
    URL = 4,
    RESOURCE_URL = 5,
    ATTRIBUTE_NO_BINDING = 6,
};

/// Namespace constants.
const SVG_NAMESPACE = "svg";
const MATH_ML_NAMESPACE = "math";
const NO_NAMESPACE = "";
const MATCH_ALL_ELEMENTS = "*";

/// SecuritySchemaEntry — maps a property name + namespace + tag name to a SecurityContext.
const SecuritySchemaEntry = struct {
    prop: []const u8,
    namespace: []const u8,
    tag: []const u8,
    context: SecurityContext,
};

/// The security schema — a flat array of entries.
/// Direct port of the SECURITY_SCHEMA entries in the TS source.
const SECURITY_SCHEMA_ENTRIES = [_]SecuritySchemaEntry{
    // HTML context
    .{ .prop = "srcdoc", .namespace = "", .tag = "iframe", .context = .HTML },
    .{ .prop = "innerhtml", .namespace = "", .tag = "*", .context = .HTML },
    .{ .prop = "outerhtml", .namespace = "", .tag = "*", .context = .HTML },

    // Style context
    .{ .prop = "style", .namespace = "", .tag = "*", .context = .STYLE },

    // URL context (HTML namespace)
    .{ .prop = "formaction", .namespace = "", .tag = "*", .context = .URL },
    .{ .prop = "href", .namespace = "", .tag = "area", .context = .URL },
    .{ .prop = "href", .namespace = "", .tag = "a", .context = .URL },
    .{ .prop = "xlink:href", .namespace = "", .tag = "a", .context = .URL },
    .{ .prop = "action", .namespace = "", .tag = "form", .context = .URL },
    .{ .prop = "src", .namespace = "", .tag = "img", .context = .URL },
    .{ .prop = "src", .namespace = "", .tag = "video", .context = .URL },

    // URL context (MathML namespace)
    .{ .prop = "href", .namespace = "math", .tag = "*", .context = .URL },
    .{ .prop = "xlink:href", .namespace = "math", .tag = "*", .context = .URL },

    // URL context (SVG namespace)
    .{ .prop = "href", .namespace = "svg", .tag = "a", .context = .URL },
    .{ .prop = "xlink:href", .namespace = "svg", .tag = "a", .context = .URL },

    // Resource URL context
    .{ .prop = "href", .namespace = "", .tag = "base", .context = .RESOURCE_URL },
    .{ .prop = "src", .namespace = "", .tag = "embed", .context = .RESOURCE_URL },
    .{ .prop = "src", .namespace = "", .tag = "frame", .context = .RESOURCE_URL },
    .{ .prop = "src", .namespace = "", .tag = "iframe", .context = .RESOURCE_URL },
    .{ .prop = "href", .namespace = "", .tag = "link", .context = .RESOURCE_URL },
    .{ .prop = "codebase", .namespace = "", .tag = "object", .context = .RESOURCE_URL },
    .{ .prop = "data", .namespace = "", .tag = "object", .context = .RESOURCE_URL },

    // ATTRIBUTE_NO_BINDING (SVG namespace)
    .{ .prop = "attributename", .namespace = "svg", .tag = "animate", .context = .ATTRIBUTE_NO_BINDING },
    .{ .prop = "values", .namespace = "svg", .tag = "animate", .context = .ATTRIBUTE_NO_BINDING },
    .{ .prop = "to", .namespace = "svg", .tag = "animate", .context = .ATTRIBUTE_NO_BINDING },
    .{ .prop = "from", .namespace = "svg", .tag = "animate", .context = .ATTRIBUTE_NO_BINDING },
    .{ .prop = "to", .namespace = "svg", .tag = "set", .context = .ATTRIBUTE_NO_BINDING },
    .{ .prop = "attributename", .namespace = "svg", .tag = "set", .context = .ATTRIBUTE_NO_BINDING },
    .{ .prop = "attributename", .namespace = "svg", .tag = "animatemotion", .context = .ATTRIBUTE_NO_BINDING },
    .{ .prop = "attributename", .namespace = "svg", .tag = "animatetransform", .context = .ATTRIBUTE_NO_BINDING },

    // ATTRIBUTE_NO_BINDING (HTML namespace — unknown elements)
    .{ .prop = "attributename", .namespace = "", .tag = "unknown", .context = .ATTRIBUTE_NO_BINDING },
    .{ .prop = "values", .namespace = "", .tag = "unknown", .context = .ATTRIBUTE_NO_BINDING },
    .{ .prop = "to", .namespace = "", .tag = "unknown", .context = .ATTRIBUTE_NO_BINDING },
    .{ .prop = "from", .namespace = "", .tag = "unknown", .context = .ATTRIBUTE_NO_BINDING },
    .{ .prop = "sandbox", .namespace = "", .tag = "unknown", .context = .ATTRIBUTE_NO_BINDING },
    .{ .prop = "allow", .namespace = "", .tag = "unknown", .context = .ATTRIBUTE_NO_BINDING },
    .{ .prop = "allowfullscreen", .namespace = "", .tag = "unknown", .context = .ATTRIBUTE_NO_BINDING },
    .{ .prop = "referrerpolicy", .namespace = "", .tag = "unknown", .context = .ATTRIBUTE_NO_BINDING },
    .{ .prop = "csp", .namespace = "", .tag = "unknown", .context = .ATTRIBUTE_NO_BINDING },
    .{ .prop = "fetchpriority", .namespace = "", .tag = "unknown", .context = .ATTRIBUTE_NO_BINDING },
    .{ .prop = "credentialless", .namespace = "", .tag = "unknown", .context = .ATTRIBUTE_NO_BINDING },

    // ATTRIBUTE_NO_BINDING (HTML namespace — iframe)
    .{ .prop = "sandbox", .namespace = "", .tag = "iframe", .context = .ATTRIBUTE_NO_BINDING },
    .{ .prop = "allow", .namespace = "", .tag = "iframe", .context = .ATTRIBUTE_NO_BINDING },
    .{ .prop = "allowfullscreen", .namespace = "", .tag = "iframe", .context = .ATTRIBUTE_NO_BINDING },
    .{ .prop = "referrerpolicy", .namespace = "", .tag = "iframe", .context = .ATTRIBUTE_NO_BINDING },
    .{ .prop = "csp", .namespace = "", .tag = "iframe", .context = .ATTRIBUTE_NO_BINDING },
    .{ .prop = "fetchpriority", .namespace = "", .tag = "iframe", .context = .ATTRIBUTE_NO_BINDING },
    .{ .prop = "credentialless", .namespace = "", .tag = "iframe", .context = .ATTRIBUTE_NO_BINDING },
};

/// Backward-compatible static map for simple property name lookups.
/// Direct port of the original SECURITY_CONTEXTS map.
pub const SECURITY_CONTEXTS = std.StaticStringMap(SecurityContext).initComptime(.{
    .{ "innerhtml", .HTML },
    .{ "outerhtml", .HTML },
    .{ "style", .STYLE },
    .{ "href", .URL },
    .{ "src", .URL },
    .{ "action", .URL },
    .{ "formaction", .URL },
    .{ "srcdoc", .HTML },
});

/// Get the security context for a property name (simple lookup).
pub fn getSecurityContext(name: []const u8) ?SecurityContext {
    return SECURITY_CONTEXTS.get(name);
}

/// Check the SecurityContext for a given tag, property, and namespace.
/// Direct port of `checkSecurityContext(tagName, propName, namespace)` in the TS source.
///
/// Returns the most specific SecurityContext for the combination of
/// tag name + property name + namespace. Falls back to wildcard matches.
pub fn checkSecurityContext(
    tag_name: []const u8,
    prop_name: []const u8,
    namespace: ?[]const u8,
) SecurityContext {
    // Convert to lowercase for comparison
    var prop_lower_buf: [128]u8 = undefined;
    var tag_lower_buf: [128]u8 = undefined;
    const prop_lower = std.ascii.lowerString(&prop_lower_buf, prop_name);
    const tag_lower = std.ascii.lowerString(&tag_lower_buf, tag_name);

    const ns = namespace orelse NO_NAMESPACE;

    var best_context: SecurityContext = .NONE;

    // First pass: try exact namespace + exact tag match
    for (SECURITY_SCHEMA_ENTRIES) |entry| {
        if (std.mem.eql(u8, entry.prop, prop_lower) and
            std.mem.eql(u8, entry.namespace, ns) and
            std.mem.eql(u8, entry.tag, tag_lower))
        {
            return entry.context;
        }
    }

    // Second pass: try exact namespace + wildcard tag
    for (SECURITY_SCHEMA_ENTRIES) |entry| {
        if (std.mem.eql(u8, entry.prop, prop_lower) and
            std.mem.eql(u8, entry.namespace, ns) and
            std.mem.eql(u8, entry.tag, MATCH_ALL_ELEMENTS))
        {
            best_context = entry.context;
        }
    }

    // Third pass: if namespace was specified, try no-namespace + exact tag
    if (namespace != null and !std.mem.eql(u8, ns, NO_NAMESPACE)) {
        for (SECURITY_SCHEMA_ENTRIES) |entry| {
            if (std.mem.eql(u8, entry.prop, prop_lower) and
                std.mem.eql(u8, entry.namespace, NO_NAMESPACE) and
                std.mem.eql(u8, entry.tag, tag_lower))
            {
                return entry.context;
            }
        }
        // Try no-namespace + wildcard tag
        for (SECURITY_SCHEMA_ENTRIES) |entry| {
            if (std.mem.eql(u8, entry.prop, prop_lower) and
                std.mem.eql(u8, entry.namespace, NO_NAMESPACE) and
                std.mem.eql(u8, entry.tag, MATCH_ALL_ELEMENTS))
            {
                best_context = entry.context;
            }
        }
    }

    return best_context;
}

// ─── Tests ──────────────────────────────────────────────────

test "SecurityContext values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(SecurityContext.NONE));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(SecurityContext.HTML));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(SecurityContext.STYLE));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(SecurityContext.SCRIPT));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(SecurityContext.URL));
    try std.testing.expectEqual(@as(u8, 5), @intFromEnum(SecurityContext.RESOURCE_URL));
    try std.testing.expectEqual(@as(u8, 6), @intFromEnum(SecurityContext.ATTRIBUTE_NO_BINDING));
}

test "checkSecurityContext innerHTML" {
    try std.testing.expectEqual(SecurityContext.HTML, checkSecurityContext("div", "innerHTML", null));
    try std.testing.expectEqual(SecurityContext.HTML, checkSecurityContext("div", "innerhtml", null));
    try std.testing.expectEqual(SecurityContext.HTML, checkSecurityContext("span", "outerHTML", null));
}

test "checkSecurityContext style" {
    try std.testing.expectEqual(SecurityContext.STYLE, checkSecurityContext("div", "style", null));
}

test "checkSecurityContext href on a tag" {
    try std.testing.expectEqual(SecurityContext.URL, checkSecurityContext("a", "href", null));
}

test "checkSecurityContext href on base tag" {
    try std.testing.expectEqual(SecurityContext.RESOURCE_URL, checkSecurityContext("base", "href", null));
}

test "checkSecurityContext src on iframe" {
    try std.testing.expectEqual(SecurityContext.RESOURCE_URL, checkSecurityContext("iframe", "src", null));
}

test "checkSecurityContext srcdoc on iframe" {
    try std.testing.expectEqual(SecurityContext.HTML, checkSecurityContext("iframe", "srcdoc", null));
}

test "checkSecurityContext SVG namespace href" {
    try std.testing.expectEqual(SecurityContext.URL, checkSecurityContext("a", "href", "svg"));
    try std.testing.expectEqual(SecurityContext.URL, checkSecurityContext("a", "xlink:href", "svg"));
}

test "checkSecurityContext MathML namespace href" {
    try std.testing.expectEqual(SecurityContext.URL, checkSecurityContext("mi", "href", "math"));
}

test "checkSecurityContext unknown property" {
    try std.testing.expectEqual(SecurityContext.NONE, checkSecurityContext("div", "class", null));
    try std.testing.expectEqual(SecurityContext.NONE, checkSecurityContext("div", "unknownProp", null));
}

test "checkSecurityContext ATTRIBUTE_NO_BINDING sandbox" {
    try std.testing.expectEqual(SecurityContext.ATTRIBUTE_NO_BINDING, checkSecurityContext("iframe", "sandbox", null));
}

test "checkSecurityContext ATTRIBUTE_NO_BINDING SVG animate" {
    try std.testing.expectEqual(SecurityContext.ATTRIBUTE_NO_BINDING, checkSecurityContext("animate", "attributeName", "svg"));
    try std.testing.expectEqual(SecurityContext.ATTRIBUTE_NO_BINDING, checkSecurityContext("animate", "values", "svg"));
}

test "checkSecurityContext formAction wildcard" {
    try std.testing.expectEqual(SecurityContext.URL, checkSecurityContext("button", "formAction", null));
    try std.testing.expectEqual(SecurityContext.URL, checkSecurityContext("input", "formaction", null));
}

test "getSecurityContext simple lookup" {
    try std.testing.expectEqual(SecurityContext.HTML, getSecurityContext("innerhtml").?);
    try std.testing.expectEqual(SecurityContext.STYLE, getSecurityContext("style").?);
    try std.testing.expect(getSecurityContext("unknown") == null);
}
