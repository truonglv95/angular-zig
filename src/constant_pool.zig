/// Constant Pool — Shared constant storage for compiled output
///
/// Port of: compiler/src/constant_pool.ts
const std = @import("std");

/// A pool of constants used by the compiled template function.
/// Stores strings, numbers, and other literal values that are
/// referenced by index in the generated code.
pub const ConstantPool = struct {
    constants: std.ArrayList(ConstantEntry),
    allocator: std.mem.Allocator,

    pub const ConstantEntry = struct {
        value: []const u8,
        kind: enum { String, Number, Bool, Null, Array, Map },
    };

    pub fn init(allocator: std.mem.Allocator) ConstantPool {
        return .{
            .constants = std.ArrayList(ConstantEntry).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ConstantPool) void {
        self.constants.deinit();
    }

    pub fn add(self: *ConstantPool, value: []const u8, kind: ConstantEntry.kind) !u32 {
        const idx: u32 = @intCast(self.constants.items.len);
        try self.constants.append(.{ .value = value, .kind = kind });
        return idx;
    }

    pub fn size(self: *const ConstantPool) usize {
        return self.constants.items.len;
    }
};
