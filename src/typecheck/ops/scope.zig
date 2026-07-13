/// TCB Ops Scope — Per-template-node TCB scope tracking (largest)
///
/// Port of: compiler/src/typecheck/typecheck/ops/scope.ts (1066 LoC)
const std = @import("std");

/// Scope — per-template-node TCB scope tracking, variable visibility, directive ordering.
pub const Scope = struct {
    allocator: std.mem.Allocator,
    directives: std.ArrayList(DirectiveInstance),
    variables: std.StringHashMap([]const u8),
    element_index: u32 = 0,

    pub const DirectiveInstance = struct {
        name: []const u8,
        xref: u32,
        is_component: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator) Scope {
        return .{
            .allocator = allocator,
            .directives = std.ArrayList(DirectiveInstance).init(allocator),
            .variables = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Scope) void {
        self.directives.deinit();
        self.variables.deinit();
    }

    pub fn addDirective(self: *Scope, name: []const u8, xref: u32) !void {
        try self.directives.append(.{ .name = name, .xref = xref });
    }

    pub fn addVariable(self: *Scope, name: []const u8, type_name: []const u8) !void {
        try self.variables.put(name, type_name);
    }

    pub fn lookupVariable(self: *const Scope, name: []const u8) ?[]const u8 {
        return self.variables.get(name);
    }
};
