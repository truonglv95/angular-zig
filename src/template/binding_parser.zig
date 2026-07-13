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

    // [prop]
    if (name[0] == '[') {
        if (name.len > 1 and name[name.len - 1] == ']') {
            return .{ .class = .Property, .name = name[1 .. name.len - 1], .original = name };
        }
        // [(twoWay)]
        if (name.len > 2 and name[1] == '(' and name[name.len - 2] == ')') {
            return .{ .class = .TwoWay, .name = name[2 .. name.len - 2], .original = name };
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
        defer parts.deinit();

        var i: usize = 0;
        while (i < value.len) {
            // Find {{
            if (i + 1 < value.len and value[i] == '{' and value[i + 1] == '{') {
                const expr_start = i + 2;
                // Find }}
                var depth: u32 = 1;
                var j = expr_start;
                while (j < value.len and depth > 0) : (j += 1) {
                    if (j + 1 < value.len and value[j] == '{' and value[j + 1] == '{') {
                        depth += 1;
                        j += 1;
                    } else if (j + 1 < value.len and value[j] == '}' and value[j + 1] == '}') {
                        depth -= 1;
                        j += 1;
                    }
                }
                const expr_str = value[expr_start .. j - 1];
                try parts.append(.{
                    .text = null,
                    .expression = expr_str,
                    .start = @intCast(i),
                    .end = @intCast(j + 1),
                });
                i = j + 1;
            } else {
                // Plain text
                const text_start = i;
                while (i < value.len and !(i + 1 < value.len and value[i] == '{' and value[i + 1] == '{')) {
                    i += 1;
                }
                if (i > text_start) {
                    try parts.append(.{
                        .text = value[text_start..i],
                        .expression = null,
                        .start = @intCast(text_start),
                        .end = @intCast(i),
                    });
                }
            }
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

    try std.testing.expectEqual(@as(usize, 3), result.parts.len);
    try std.testing.expect(result.parts[0].text != null);
    try std.testing.expect(result.parts[1].expression != null);
    try std.testing.expect(result.parts[2].text != null);
    try std.testing.expectEqualStrings("name", result.parts[1].expression.?);
}
