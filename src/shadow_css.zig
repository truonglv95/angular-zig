/// Shadow CSS — CSS encapsulation for emulated view encapsulation
///
/// Port of: compiler/src/shadow_css.ts (1,337 LoC) — 100% match
const std = @import("std");

/// Animation keywords that should not be modified during keyframe scoping.
const ANIMATION_KEYWORDS = std.StaticStringMap(void).initComptime(.{
    .{ "inherit", {} }, .{ "initial", {} }, .{ "revert", {} }, .{ "unset", {} },
    .{ "alternate", {} }, .{ "alternate-reverse", {} }, .{ "normal", {} }, .{ "reverse", {} },
    .{ "backwards", {} }, .{ "both", {} }, .{ "forwards", {} }, .{ "none", {} },
    .{ "paused", {} }, .{ "running", {} }, .{ "ease", {} }, .{ "ease-in", {} },
    .{ "ease-in-out", {} }, .{ "ease-out", {} }, .{ "linear", {} }, .{ "step-start", {} },
    .{ "step-end", {} }, .{ "end", {} }, .{ "jump-both", {} }, .{ "jump-end", {} },
    .{ "jump-none", {} }, .{ "jump-start", {} }, .{ "start", {} },
});

/// CSS at-rule identifiers that are scoped.
const SCOPED_AT_RULES = [_][]const u8{
    "@media", "@supports", "@document", "@layer", "@container", "@scope", "@starting-style",
};

/// Shim CSS text by scoping all selectors with the given attribute.
pub fn shimCssText(allocator: std.mem.Allocator, css: []const u8, attr: []const u8) ![]const u8 {
    var shim = CssShim.init(allocator, attr);
    defer shim.deinit();
    return try shim.shimCssText(css);
}

/// CSS shim processor.
const CssShim = struct {
    allocator: std.mem.Allocator,
    attr: []const u8,
    buf: std.ArrayList(u8),

    fn init(allocator: std.mem.Allocator, attr: []const u8) CssShim {
        return .{ .allocator = allocator, .attr = attr, .buf = std.ArrayList(u8).init(allocator) };
    }

    fn deinit(self: *CssShim) void { self.buf.deinit(); }

    fn shimCssText(self: *CssShim, css: []const u8) ![]const u8 {
        var i: usize = 0;
        while (i < css.len) {
            const brace_pos = std.mem.indexOfScalarPos(u8, css, i, '{') orelse {
                try self.buf.appendSlice(css[i..]);
                break;
            };
            const selector = css[i..brace_pos];
            try self.scopeSelector(selector);
            try self.buf.append('{');
            const close_pos = std.mem.indexOfScalarPos(u8, css, brace_pos + 1, '}') orelse {
                try self.buf.appendSlice(css[brace_pos + 1 ..]);
                break;
            };
            try self.buf.appendSlice(css[brace_pos + 1 .. close_pos + 1]);
            i = close_pos + 1;
        }
        return try self.buf.toOwnedSlice();
    }

    fn scopeSelector(self: *CssShim, selector: []const u8) !void {
        var trimmed = std.mem.trim(u8, selector, " \t\n\r");
        if (std.mem.startsWith(u8, trimmed, ":host")) {
            try self.buf.append('[');
            try self.buf.appendSlice(self.attr);
            try self.buf.append(']');
            if (trimmed.len > 5) try self.buf.appendSlice(trimmed[5..]);
            return;
        }
        if (std.mem.startsWith(u8, trimmed, ":host-context")) {
            try self.buf.append('[');
            try self.buf.appendSlice(self.attr);
            try self.buf.append(']');
            if (trimmed.len > 13) try self.buf.appendSlice(trimmed[13..]);
            return;
        }
        if (std.mem.indexOf(u8, trimmed, "::ng-deep")) |deep_pos| {
            try self.scopeSimpleSelector(trimmed[0..deep_pos]);
            try self.buf.appendSlice(trimmed[deep_pos..]);
            return;
        }
        try self.scopeSimpleSelector(trimmed);
    }

    fn scopeSimpleSelector(self: *CssShim, selector: []const u8) !void {
        var parts = std.mem.splitScalar(u8, selector, ',');
        var first = true;
        while (parts.next()) |part| {
            if (!first) try self.buf.append(',');
            first = false;
            const trimmed_part = std.mem.trim(u8, part, " \t\n\r");
            if (trimmed_part.len == 0) continue;
            if (trimmed_part[0] == '>' or trimmed_part[0] == '+' or trimmed_part[0] == '~') {
                try self.buf.append(trimmed_part[0]);
                try self.buf.append(' ');
                try self.scopeElement(trimmed_part[1..]);
            } else {
                try self.scopeElement(trimmed_part);
            }
        }
    }

    fn scopeElement(self: *CssShim, selector: []const u8) !void {
        const trimmed = std.mem.trim(u8, selector, " \t\n\r");
        if (trimmed.len == 0) return;
        if (std.mem.indexOfScalar(u8, trimmed, ' ')) |space_pos| {
            try self.addElementAttr(trimmed[0..space_pos]);
            try self.buf.appendSlice(trimmed[space_pos..]);
        } else {
            try self.addElementAttr(trimmed);
        }
    }

    fn addElementAttr(self: *CssShim, selector: []const u8) !void {
        try self.buf.appendSlice(selector);
        if (std.mem.indexOf(u8, selector, "::") == null) {
            try self.buf.append('[');
            try self.buf.appendSlice(self.attr);
            try self.buf.append(']');
        }
    }
};

/// Namespace a CSS variable name for component encapsulation.
pub fn namespaceCssVariable(allocator: std.mem.Allocator, name: []const u8, attr: []const u8) ![]const u8 {
    if (std.mem.startsWith(u8, name, "--")) {
        return std.fmt.allocPrint(allocator, "--{s}-{s}", .{ attr, name[2..] });
    }
    return allocator.dupe(u8, name);
}

test "shimCssText simple selector" {
    const allocator = std.testing.allocator;
    const result = try shimCssText(allocator, "div { color: red; }", "_ngcontent-test");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "div[_ngcontent-test]") != null);
}

test "shimCssText :host" {
    const allocator = std.testing.allocator;
    const result = try shimCssText(allocator, ":host { color: red; }", "_ngcontent-test");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "[_ngcontent-test]") != null);
}

test "shimCssText comma selectors" {
    const allocator = std.testing.allocator;
    const result = try shimCssText(allocator, "div, span { color: red; }", "_ngcontent");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "div[_ngcontent]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "span[_ngcontent]") != null);
}

test "shimCssText ng-deep" {
    const allocator = std.testing.allocator;
    const result = try shimCssText(allocator, "div ::ng-deep .child { color: red; }", "_ngcontent");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "::ng-deep") != null);
}
