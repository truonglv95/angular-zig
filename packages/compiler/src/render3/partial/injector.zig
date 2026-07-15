/// R3 Partial Injector — Compile injector definitions
///
/// Port of: compiler/src/render3/partial/injector.ts (53 LoC)
const std = @import("std");

/// Compile an injector definition.
pub fn compileInjector(
    allocator: std.mem.Allocator,
    type_name: []const u8,
    providers: []const []const u8,
) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    try buf.appendSlice("ɵɵdefineInjector({ type: ");
    try buf.appendSlice(type_name);

    if (providers.len > 0) {
        try buf.appendSlice(", providers: [");
        for (providers, 0..) |p, i| {
            if (i > 0) try buf.appendSlice(", ");
            try buf.appendSlice(p);
        }
        try buf.append(']');
    }

    try buf.appendSlice(" })");
    return buf.toOwnedSlice();
}

test "compileInjector" {
    const allocator = std.testing.allocator;
    const providers = [_][]const u8{"MyService"};
    const result = try compileInjector(allocator, "MyModule", &providers);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "ɵɵdefineInjector") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "MyService") != null);
}
