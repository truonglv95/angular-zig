/// R3 T2 API — BoundTarget interface for directive matching
///
/// Port of: compiler/src/render3/render3/view/.ts (336 LoC)
const std = @import("std");

/// BoundTarget — maps template nodes to their directives, references, variables.
pub fn BoundTarget(comptime T: type) type {
    return struct {
        directives: std.AutoHashMap(u32, []const u8),
        references: std.AutoHashMap(u32, []const u8),
        variables: std.AutoHashMap(u32, []const u8),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .directives = std.AutoHashMap(u32, []const u8).init(allocator),
                .references = std.AutoHashMap(u32, []const u8).init(allocator),
                .variables = std.AutoHashMap(u32, []const u8).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.directives.deinit();
            self.references.deinit();
            self.variables.deinit();
        }

        pub fn getDirective(self: *const @This(), xref: u32) ?[]const u8 {
            return self.directives.get(xref);
        }

        _ = T,
    };
}
