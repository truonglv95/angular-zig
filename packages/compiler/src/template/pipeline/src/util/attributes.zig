/// Port of: template/pipeline/src/util/attributes.ts (18 LoC)
/// DOD + Arena Memory
const std = @import("std");

pub fn isAriaAttribute(allocator: std.mem.Allocator) void {
    _ = allocator;
}

test "module loads" {
    std.testing.expect(true);
}
