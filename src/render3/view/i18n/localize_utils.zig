/// R3 View i18n Localize Utils — $localize tagged-template emission
///
/// Port of: compiler/src/render3/render3/view/i18n/.ts (187 LoC)
const std = @import("std");

/// Create $localize tagged-template statements for runtime i18n.
pub fn createLocalizeStatements(allocator: std.mem.Allocator, message: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "$localize`{s}`", .{message});
}
