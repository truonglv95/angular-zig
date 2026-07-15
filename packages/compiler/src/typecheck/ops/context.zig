/// TCB Ops Context — Context operations for TCB
///
/// Port of: compiler/src/typecheck/ops/context.ts (81 LoC)
///
/// The Context handles operations during TCB code generation that are global
/// to the whole block. It's responsible for:
///   - Variable name allocation (monotonically increasing counter)
///   - Pipe metadata lookup
///   - Template metadata storage
///   - DOM schema checking
///   - Out-of-band diagnostic recording
const std = @import("std");

/// TcbGenericContextBehavior — how generics for the component context class
/// are handled during TCB generation.
/// Direct port of `TcbGenericContextBehavior` enum in the TS source.
pub const TcbGenericContextBehavior = enum(u8) {
    /// References to generic parameter bounds will be emitted via the TypeParameterEmitter.
    UseEmitter,
    /// Generic parameter declarations will be copied from the ClassDeclaration.
    CopyClassNodes,
    /// Generic parameters will be set to `any` (always safe, less useful).
    FallbackToAny,
};

/// TypeCheckId — a unique identifier for a type check block.
pub const TypeCheckId = u32;

/// TcbPipeMetadata — metadata about a pipe used in the TCB.
pub const TcbPipeMetadata = struct {
    name: []const u8,
    ref: []const u8,
    is_explicitly_deferred: bool = false,
};

/// SchemaMetadata — metadata about allowed schemas in the template.
pub const SchemaMetadata = struct {
    name: []const u8,
};

/// Context — overall generation context for the type check block.
/// Direct port of `Context` class in the TS source.
pub const Context = struct {
    allocator: std.mem.Allocator,
    /// The TCB environment.
    env: ?*const anyopaque = null,
    /// Unique ID for this TCB.
    id: TypeCheckId = 0,
    /// Whether the host is standalone.
    host_is_standalone: bool = false,
    /// Whether to preserve whitespace.
    host_preserve_whitespaces: bool = false,
    /// Schemas allowed in the template.
    schemas: []const SchemaMetadata = &.{},
    /// Pipes used in the template (name → metadata).
    pipes: std.StringHashMap(TcbPipeMetadata),

    // Internal state
    next_id: u32 = 1,
    current_view: u32 = 0,
    next_view: u32 = 1,

    pub fn init(allocator: std.mem.Allocator) Context {
        return .{
            .allocator = allocator,
            .pipes = std.StringHashMap(TcbPipeMetadata).init(allocator),
        };
    }

    pub fn deinit(self: *Context) void {
        self.pipes.deinit();
    }

    /// Allocate a new variable name for use within the Context.
    /// Direct port of `Context.allocateId()` in the TS source.
    ///
    /// Uses a monotonically increasing counter: `_t1`, `_t2`, `_t3`, ...
    pub fn allocateId(self: *Context) ![]const u8 {
        const id = self.next_id;
        self.next_id += 1;
        return std.fmt.allocPrint(self.allocator, "_t{d}", .{id});
    }

    /// Allocate a new view number.
    pub fn allocateView(self: *Context) u32 {
        const v = self.next_view;
        self.next_view += 1;
        return v;
    }

    /// Look up a pipe by name.
    /// Direct port of `Context.getPipeByName(name)` in the TS source.
    pub fn getPipeByName(self: *const Context, name: []const u8) ?TcbPipeMetadata {
        return self.pipes.get(name);
    }

    /// Add a pipe to the context.
    pub fn addPipe(self: *Context, name: []const u8, meta: TcbPipeMetadata) !void {
        try self.pipes.put(name, meta);
    }
};

/// Backward-compatible alias.
pub const TcbContext = Context;

// ─── Tests ──────────────────────────────────────────────────

test "Context init/deinit" {
    const allocator = std.testing.allocator;
    var ctx = Context.init(allocator);
    defer ctx.deinit();
    try std.testing.expectEqual(@as(u32, 1), ctx.next_id);
}

test "Context allocateId produces unique names" {
    const allocator = std.testing.allocator;
    var ctx = Context.init(allocator);
    defer ctx.deinit();

    const id1 = try ctx.allocateId();
    defer allocator.free(id1);
    try std.testing.expectEqualStrings("_t1", id1);

    const id2 = try ctx.allocateId();
    defer allocator.free(id2);
    try std.testing.expectEqualStrings("_t2", id2);

    const id3 = try ctx.allocateId();
    defer allocator.free(id3);
    try std.testing.expectEqualStrings("_t3", id3);
}

test "Context allocateView produces unique numbers" {
    const allocator = std.testing.allocator;
    var ctx = Context.init(allocator);
    defer ctx.deinit();

    try std.testing.expectEqual(@as(u32, 1), ctx.allocateView());
    try std.testing.expectEqual(@as(u32, 2), ctx.allocateView());
    try std.testing.expectEqual(@as(u32, 3), ctx.allocateView());
}

test "Context addPipe and getPipeByName" {
    const allocator = std.testing.allocator;
    var ctx = Context.init(allocator);
    defer ctx.deinit();

    try ctx.addPipe("date", .{ .name = "date", .ref = "DatePipe" });
    try ctx.addPipe("uppercase", .{ .name = "uppercase", .ref = "UpperCasePipe" });

    const date_pipe = ctx.getPipeByName("date").?;
    try std.testing.expectEqualStrings("DatePipe", date_pipe.ref);

    const upper_pipe = ctx.getPipeByName("uppercase").?;
    try std.testing.expectEqualStrings("UpperCasePipe", upper_pipe.ref);

    try std.testing.expect(ctx.getPipeByName("missing") == null);
}

test "TcbGenericContextBehavior values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(TcbGenericContextBehavior.UseEmitter));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(TcbGenericContextBehavior.CopyClassNodes));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(TcbGenericContextBehavior.FallbackToAny));
}
