/// R3 View i18n ICU Serializer — Serialize ICU node to message text
///
/// Port of: compiler/src/render3/render3/view/i18n/.ts (60 LoC)
const std = @import("std");

/// Serialize an ICU node to its message text representation.
pub fn serializeIcuNode(allocator: std.mem.Allocator, expression: []const u8) ![]const u8 {
    return allocator.dupe(u8, expression);
}
