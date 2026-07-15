/// R3 Partial Service — Compile service definitions
///
/// Port of: compiler/src/render3/partial/service.ts (59 LoC)
const std = @import("std");

/// Compile a service definition.
pub fn compileService(
    allocator: std.mem.Allocator,
    type_name: []const u8,
    provided_in: ?[]const u8,
) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    try buf.appendSlice("ɵɵdefineInjectable({ ");
    try buf.appendSlice("factory: () => new ");
    try buf.appendSlice(type_name);
    try buf.appendSlice("(), token: ");
    try buf.appendSlice(type_name);

    if (provided_in) |pi| {
        try buf.appendSlice(", providedIn: ");
        try buf.appendSlice(pi);
    }

    try buf.appendSlice(" })");
    return buf.toOwnedSlice();
}

test "compileService" {
    const allocator = std.testing.allocator;
    const result = try compileService(allocator, "MyService", "root");
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "ɵɵdefineInjectable") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "root") != null);
}
