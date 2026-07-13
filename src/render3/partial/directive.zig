/// R3 Partial Directive — ɵɵdeclareDirective emission
///
/// Port of: compiler/src/render3/render3/partial/.ts (344 LoC)
const std = @import("std");

/// Compile a partial directive declaration into a full ɵɵdefineDirective call.
pub fn compileDirective(allocator: std.mem.Allocator, type_name: []const u8, selector: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        "ɵɵdefineDirective({{ type: {s}, selectors: [['{s}']] }})", .{ type_name, selector });
}
