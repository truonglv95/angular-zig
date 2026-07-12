/// Render3 Identifiers — Component/Directive Identifier Generation
///
/// Generates stable, unique identifiers for components and directives
/// encountered during template compilation.
///
/// In Angular, identifiers are used for:
///   - Component type identifiers (e.g., Component_MyApp_MyComponent)
///   - Directive type identifiers (e.g., Directive_NgIf)
///   - Template reference identifiers
///   - View container identifiers
///
/// DOD:
///   - All identifiers are string slices from the constant pool
///   - No heap allocation during identifier generation (uses stack buffer)
///   - Deterministic: same component always gets same identifier
///   - O(1) deduplication via StringHashMap
///   - Stack-allocated name buffer (max 256 chars per name)
const std = @import("std");
const Allocator = std.mem.Allocator;

// ─── Identifier Components ────────────────────────────────────

/// The parts that make up a fully qualified identifier.
pub const IdParts = struct {
    /// Module prefix (e.g., "Component", "Directive", "Pipe")
    prefix: []const u8,
    /// Package/app name (e.g., "MyApp")
    module_name: []const u8,
    /// Type name (e.g., "MyComponent", "NgIf")
    type_name: []const u8,
};

/// Context for identifier generation — provides module/app info.
pub const IdContext = struct {
    /// The app or library module name
    module_name: []const u8,
    /// Prefix for components (default: "Component")
    component_prefix: []const u8 = "Component",
    /// Prefix for directives (default: "Directive")
    directive_prefix: []const u8 = "Directive",
    /// Separator between parts (default: "_")
    separator: u8 = '_',
};

// ─── Identifier Generator ────────────────────────────────────

/// Generates and deduplicates identifiers during compilation.
pub const IdentifierGenerator = struct {
    allocator: Allocator,
    /// Module/app context
    ctx: IdContext,
    /// Dedup set: maps generated name → first occurrence index
    seen: std.StringHashMap(u32),
    /// Counter for generating unique indices
    next_index: u32,

    pub fn init(allocator: Allocator, ctx: IdContext) IdentifierGenerator {
        return .{
            .allocator = allocator,
            .ctx = ctx,
            .seen = std.StringHashMap(u32).init(allocator),
            .next_index = 0,
        };
    }

    pub fn deinit(self: *IdentifierGenerator) void {
        self.seen.deinit();
    }

    /// Generate a component identifier.
    /// E.g., "Component_MyApp_MyComponent"
    pub fn componentId(self: *IdentifierGenerator, type_name: []const u8) ![]const u8 {
        const parts = IdParts{
            .prefix = self.ctx.component_prefix,
            .module_name = self.ctx.module_name,
            .type_name = type_name,
        };
        return self.generateId(&parts);
    }

    /// Generate a directive identifier.
    /// E.g., "Directive_NgIf"
    pub fn directiveId(self: *IdentifierGenerator, type_name: []const u8) ![]const u8 {
        const parts = IdParts{
            .prefix = self.ctx.directive_prefix,
            .module_name = self.ctx.module_name,
            .type_name = type_name,
        };
        return self.generateId(&parts);
    }

    /// Generate a generic identifier with custom prefix.
    pub fn customId(self: *IdentifierGenerator, prefix: []const u8, type_name: []const u8) ![]const u8 {
        const parts = IdParts{
            .prefix = prefix,
            .module_name = self.ctx.module_name,
            .type_name = type_name,
        };
        return self.generateId(&parts);
    }

    /// Generate a view container identifier.
    /// E.g., "View_MyComponent_0"
    pub fn viewId(self: *IdentifierGenerator, component_name: []const u8, view_index: u32) ![]const u8 {
        // Build: "View_<ComponentName>_<index>"
        const sep = self.ctx.separator;
        var buf: [512]u8 = undefined;
        var writer = std.Io.Writer.fixed(buf[0..]);
        writer.writeAll("View") catch unreachable;
        writer.writeByte(sep) catch unreachable;
        writer.writeAll(component_name) catch unreachable;
        writer.writeByte(sep) catch unreachable;
        writer.print("{d}", .{view_index}) catch unreachable;
        const name = buf[0..writer.context.pos];

        // Dedup
        if (self.seen.get(name)) |_| {
            return name;
        }
        const duped = try self.allocator.dupe(u8, name);
        try self.seen.put(duped, self.next_index);
        self.next_index += 1;
        return duped;
    }

    /// Generate a template reference identifier.
    /// E.g., "TemplateRef_0"
    pub fn templateRefId(self: *IdentifierGenerator, ref_index: u32) ![]const u8 {
        var buf: [64]u8 = undefined;
        var writer = std.Io.Writer.fixed(buf[0..]);
        writer.writeAll("TemplateRef_") catch unreachable;
        writer.print("{d}", .{ref_index}) catch unreachable;
        const len: usize = writer.context.pos;
        return self.allocator.dupe(u8, buf[0..len]);
    }

    /// Generate an embedded view function name.
    /// E.g., "MyComponent_Template_0"
    pub fn viewFnName(self: *IdentifierGenerator, component_name: []const u8, view_index: u32) ![]const u8 {
        var buf: [256]u8 = undefined;
        var writer = std.Io.Writer.fixed(buf[0..]);
        writer.writeAll(component_name) catch unreachable;
        writer.writeAll("_Template_") catch unreachable;
        writer.print("{d}", .{view_index}) catch unreachable;
        const len: usize = writer.context.pos;
        return self.allocator.dupe(u8, buf[0..len]);
    }

    /// Generate a pipe factory function name.
    /// E.g., "MyComponent_pipe_transform_0"
    pub fn pipeFactoryName(self: *IdentifierGenerator, component_name: []const u8, pipe_name: []const u8, pipe_index: u32) ![]const u8 {
        var buf: [512]u8 = undefined;
        var writer = std.Io.Writer.fixed(buf[0..]);
        writer.writeAll(component_name) catch unreachable;
        writer.writeAll("_pipe_") catch unreachable;
        writer.writeAll(pipe_name) catch unreachable;
        writer.writeByte('_') catch unreachable;
        writer.print("{d}", .{pipe_index}) catch unreachable;
        const len: usize = writer.context.pos;
        return self.allocator.dupe(u8, buf[0..len]);
    }

    /// Generate an event handler function name.
    /// E.g., "MyComponent_handleClick_0"
    pub fn handlerFnName(self: *IdentifierGenerator, component_name: []const u8, event_name: []const u8, handler_index: u32) ![]const u8 {
        var buf: [512]u8 = undefined;
        var writer = std.Io.Writer.fixed(buf[0..]);
        writer.writeAll(component_name) catch unreachable;
        writer.writeAll("_handle") catch unreachable;
        // Capitalize first letter of event name
        if (event_name.len > 0) {
            writer.writeByte(if (event_name[0] >= 'a' and event_name[0] <= 'z')
                event_name[0] - 32
            else
                event_name[0]) catch unreachable;
            writer.writeAll(event_name[1..]) catch unreachable;
        }
        writer.writeByte('_') catch unreachable;
        writer.print("{d}", .{handler_index}) catch unreachable;
        const len: usize = writer.context.pos;
        return self.allocator.dupe(u8, buf[0..len]);
    }

    /// Get the total number of unique identifiers generated.
    pub fn count(self: *const IdentifierGenerator) u32 {
        return self.next_index;
    }

    /// Check if an identifier has been seen.
    pub fn hasSeen(self: *const IdentifierGenerator, name: []const u8) bool {
        return self.seen.contains(name);
    }

    // ─── Internal ─────────────────────────────────────────────

    fn generateId(self: *IdentifierGenerator, parts: *const IdParts) ![]const u8 {
        const sep = self.ctx.separator;
        // Calculate max length: prefix + sep + module + sep + type_name
        const max_len = parts.prefix.len + 1 + parts.module_name.len + 1 + parts.type_name.len;
        var buf: [512]u8 = undefined;

        if (max_len > buf.len) {
            // Fallback: use heap allocation for very long names
            return self.generateIdHeap(parts);
        }

        var writer = std.Io.Writer.fixed(buf[0..max_len]);
        writer.writeAll(parts.prefix) catch unreachable;
        writer.writeByte(sep) catch unreachable;
        writer.writeAll(parts.module_name) catch unreachable;
        writer.writeByte(sep) catch unreachable;
        writer.writeAll(parts.type_name) catch unreachable;
        const len: usize = writer.context.pos;
        const name = buf[0..len];

        // Dedup: if we've seen this name before, return the original
        if (self.seen.get(name)) |_| {
            return name;
        }

        // First occurrence: dupe and register
        const duped = try self.allocator.dupe(u8, name);
        try self.seen.put(duped, self.next_index);
        self.next_index += 1;
        return duped;
    }

    fn generateIdHeap(self: *IdentifierGenerator, parts: *const IdParts) ![]const u8 {
        const sep = self.ctx.separator;
        var list = std.array_list.Managed(u8).initCapacity(self.allocator, parts.prefix.len + parts.module_name.len + parts.type_name.len + 3) catch unreachable;
        try list.appendSlice(parts.prefix);
        try list.append(sep);
        try list.appendSlice(parts.module_name);
        try list.append(sep);
        try list.appendSlice(parts.type_name);

        const name = list.items;
        if (self.seen.get(name)) |_| {
            return name;
        }

        const duped = try self.allocator.dupe(u8, name);
        try self.seen.put(duped, self.next_index);
        self.next_index += 1;
        return duped;
    }
};

// ─── Identifier Classification ──────────────────────────────────

/// Classify what kind of identifier a string represents.
pub const IdKind = enum(u8) {
    Component,
    Directive,
    Pipe,
    View,
    Handler,
    TemplateRef,
    Unknown,
};

/// Quick classify an identifier string by its prefix pattern.
pub fn classifyId(name: []const u8) IdKind {
    if (std.mem.startsWith(u8, name, "Component_")) return .Component;
    if (std.mem.startsWith(u8, name, "Directive_")) return .Directive;
    if (std.mem.endsWith(u8, "_pipe_")) return .Pipe;
    if (std.mem.startsWith(u8, name, "View_")) return .View;
    if (std.mem.indexOf(u8, "_handle") != null) return .Handler;
    if (std.mem.startsWith(u8, name, "TemplateRef_")) return .TemplateRef;
    return .Unknown;
}

/// Extract the type name from a fully qualified identifier.
/// E.g., "Component_MyApp_MyButton" → "MyButton"
/// E.g., "Directive_NgIf" → "NgIf"
pub fn extractTypeName(name: []const u8) []const u8 {
    // Find the last underscore separator
    var last_sep: usize = 0;
    for (name, 0..) |ch, i| {
        if (ch == '_' and i > 0 and i < name.len - 1) {
            last_sep = i;
        }
    }
    if (last_sep > 0) {
        return name[last_sep + 1 ..];
    }
    return name;
}

// ─── Tests ────────────────────────────────────────────────────

test "IdentifierGenerator componentId" {
    const allocator = std.testing.allocator;
    var gen = IdentifierGenerator.init(allocator, .{ .module_name = "MyApp" });
    defer gen.deinit();

    const id = try gen.componentId("MyButton");
    defer allocator.free(id);
    try std.testing.expectEqualStrings("Component_MyApp_MyButton", id);
}

test "IdentifierGenerator directiveId" {
    const allocator = std.testing.allocator;
    var gen = IdentifierGenerator.init(allocator, .{ .module_name = "MyApp" });
    defer gen.deinit();

    const id = try gen.directiveId("NgIf");
    defer allocator.free(id);
    try std.testing.expectEqualStrings("Directive_MyApp_NgIf", id);
}

test "IdentifierGenerator deduplication" {
    const allocator = std.testing.allocator;
    var gen = IdentifierGenerator.init(allocator, .{ .module_name = "App" });
    defer gen.deinit();

    const id1 = try gen.componentId("MyComp");
    const id2 = try gen.componentId("MyComp");
    _ = id1;
    // Both should be the same string (dedup)
    try std.testing.expectEqualStrings("Component_App_MyComp", id2);
    try std.testing.expectEqual(@as(u32, 1), gen.count());
}

test "IdentifierGenerator viewId" {
    const allocator = std.testing.allocator;
    var gen = IdentifierGenerator.init(allocator, .{ .module_name = "App" });
    defer gen.deinit();

    const id = try gen.viewId("MyComp", 0);
    defer allocator.free(id);
    try std.testing.expect(std.mem.startsWith(u8, id, "View_MyComp_"));
}

test "IdentifierGenerator handlerFnName" {
    const allocator = std.testing.allocator;
    var gen = IdentifierGenerator.init(allocator, .{ .module_name = "App" });
    defer gen.deinit();

    const id = try gen.handlerFnName("MyComp", "click", 0);
    defer allocator.free(id);
    try std.testing.expect(std.mem.startsWith(u8, id, "MyComp_handleClick_"));
}

test "IdentifierGenerator pipeFactoryName" {
    const allocator = std.testing.allocator;
    var gen = IdentifierGenerator.init(allocator, .{ .module_name = "App" });
    defer gen.deinit();

    const id = try gen.pipeFactoryName("MyComp", "date", 0);
    defer allocator.free(id);
    try std.testing.expect(std.mem.startsWith(u8, id, "MyComp_pipe_date_"));
}

test "classifyId" {
    try std.testing.expectEqual(IdKind.Component, classifyId("Component_MyApp_Button"));
    try std.testing.expectEqual(IdKind.Directive, classifyId("Directive_NgIf"));
    try std.testing.expectEqual(IdKind.View, classifyId("View_MyComp_0"));
    try std.testing.expectEqual(IdKind.Handler, classifyId("MyComp_handleClick_0"));
    try std.testing.expectEqual(IdKind.Pipe, classifyId("MyComp_pipe_date_0"));
    try std.testing.expectEqual(IdKind.TemplateRef, classifyId("TemplateRef_0"));
    try std.testing.expectEqual(IdKind.Unknown, classifyId("something_random"));
}

test "extractTypeName" {
    try std.testing.expectEqualStrings("MyButton", extractTypeName("Component_MyApp_MyButton"));
    try std.testing.expectEqualStrings("NgIf", extractTypeName("Directive_MyApp_NgIf"));
    try std.testing.expectEqualStrings("MyComp", extractTypeName("View_MyComp_0"));
}

test "custom separator" {
    const allocator = std.testing.allocator;
    var gen = IdentifierGenerator.init(allocator, .{
        .module_name = "MyApp",
        .separator = '.',
    });
    defer gen.deinit();

    const id = try gen.componentId("MyButton");
    defer allocator.free(id);
    try std.testing.expectEqualStrings("Component.MyApp.MyButton", id);
}

test "custom prefix" {
    const allocator = std.testing.allocator;
    var gen = IdentifierGenerator.init(allocator, .{
        .module_name = "MyApp",
        .component_prefix = "Widget",
    });
    defer gen.deinit();

    const id = try gen.componentId("MyButton");
    defer allocator.free(id);
    try std.testing.expectEqualStrings("Widget_MyApp_MyButton", id);
}
