/// R3 Partial Pipe — ɵɵdeclarePipe emission
///
/// Port of: compiler/src/render3/render3/partial/.ts (65 LoC)
const std = @import("std");

/// Compile a partial pipe declaration.
pub fn compilePipe(allocator: std.mem.Allocator, type_name: []const u8, pipe_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        "ɵɵdefinePipe({{ type: {s}, name: '{s}' }})", .{ type_name, pipe_name });
}
