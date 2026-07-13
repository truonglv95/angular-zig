/// DOM Security Schema — Maps elements/attributes to SecurityContext
///
/// Port of: compiler/src/schema/dom_security_schema.ts
const std = @import("std");

/// Security contexts (matching Angular's SecurityContext enum).
pub const SecurityContext = enum(u8) {
    None = 0,
    HTML = 1,
    Style = 2,
    Script = 3,
    Url = 4,
    ResourceUrl = 5,
};

/// Map of property names to security contexts.
/// These properties can contain untrusted content and need sanitization.
pub const SECURITY_CONTEXTS = std.StaticStringMap(SecurityContext).initComptime(.{
    // HTML context (innerHTML, outerHTML)
    .{ "innerHTML", .HTML },
    .{ "outerHTML", .HTML },
    // Style context
    .{ "style", .Style },
    // Script context
    .{ "srcdoc", .Script },
    // URL context
    .{ "href", .Url },
    .{ "src", .Url },
    .{ "action", .Url },
    .{ "formaction", .Url },
    .{ "data", .Url },
    .{ "cite", .Url },
    .{ "background", .Url },
    .{ "poster", .Url },
    .{ "longDesc", .Url },
    .{ "useMap", .Url },
    .{ "profile", .Url },
    .{ "manifest", .Url },
    .{ "codeBase", .Url },
    .{ "icon", .Url },
    .{ "dynsrc", .Url },
    .{ "lowsrc", .Url },
    // Resource URL context
    .{ "xlinkHref", .ResourceUrl },
});

/// Get the security context for a property name.
pub fn getSecurityContext(name: []const u8) ?SecurityContext {
    return SECURITY_CONTEXTS.get(name);
}
