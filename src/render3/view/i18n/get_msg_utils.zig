/// R3 View i18n Get Msg — goog.getMsg emission
///
/// Port of: compiler/src/render3/render3/view/i18n/.ts (160 LoC)
const std = @import("std");

/// Emit goog.getMsg() calls for Closure-style i18n.
pub fn createGetMsgCall(allocator: std.mem.Allocator, msg_id: []const u8, text: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "goog.getMsg('{s}')", .{text});
    _ = msg_id;
}
