/// IR Operations — Op interface, OpList, XrefId
///
/// Port of: compiler/src/template/pipeline/ir/src/operations.ts (358 LoC)
///
/// DOD patterns:
///   - OpList uses contiguous ArrayList instead of linked list
///     (cache-friendly iteration, O(1) append, no pointer chasing)
///   - XrefId is a plain u32 (branded type in TS, but Zig doesn't need branding)
///   - Arena-allocated ops — single free at end
const std = @import("std");
const ir_enums = @import("enums.zig");
const OpKind = ir_enums.OpKind;

/// XrefId — cross-reference ID for linking ops across views.
pub const XrefId = u32;

/// Op — base interface for all IR operations.
/// DOD: plain struct with kind + xref + source_span.
/// No prev/next pointers (uses ArrayList instead of linked list).
pub const Op = struct {
    kind: OpKind,
    xref: XrefId = 0,
    source_span: ?@import("../../source_span.zig").AbsoluteSourceSpan = null,
};

/// OpList — a list of operations.
/// DOD: Uses ArrayList for contiguous memory layout (cache-friendly).
/// The TS version uses a linked list; we use an array for better performance.
pub fn OpList(comptime T: type) type {
    return struct {
        items: std.ArrayList(T),
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .items = std.ArrayList(T).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }

        /// Append an op to the end of the list.
        pub fn append(self: *Self, op: T) !void {
            try self.items.append(op);
        }

        /// Prepend an op to the beginning of the list.
        pub fn prepend(self: *Self, op: T) !void {
            try self.items.insert(0, op);
        }

        /// Insert an op at a specific index.
        pub fn insert(self: *Self, index: usize, op: T) !void {
            try self.items.insert(index, op);
        }

        /// Remove the op at the given index.
        pub fn remove(self: *Self, index: usize) T {
            return self.items.orderedRemove(index);
        }

        /// Get the number of ops in the list.
        pub fn len(self: *const Self) usize {
            return self.items.items.len;
        }

        /// Check if the list is empty.
        pub fn isEmpty(self: *const Self) bool {
            return self.items.items.len == 0;
        }

        /// Get a slice of all ops (for iteration).
        pub fn slice(self: *const Self) []const T {
            return self.items.items;
        }

        /// Get a mutable slice of all ops.
        pub fn sliceMut(self: *Self) []T {
            return self.items.items;
        }

        /// Get the first op, or null if empty.
        pub fn first(self: *const Self) ?T {
            if (self.items.items.len == 0) return null;
            return self.items.items[0];
        }

        /// Get the last op, or null if empty.
        pub fn last(self: *const Self) ?T {
            if (self.items.items.len == 0) return null;
            return self.items.items[self.items.items.len - 1];
        }

        /// Clear all ops but keep the allocated capacity.
        pub fn clearRetainingCapacity(self: *Self) void {
            self.items.clearRetainingCapacity();
        }

        /// Clear all ops and free the memory.
        pub fn clearAndFree(self: *Self) void {
            self.items.clearAndFree();
        }

        /// Filter ops in-place, keeping only those that match the predicate.
        pub fn filter(self: *Self, comptime predicate: fn (T) bool) void {
            var write: usize = 0;
            for (self.items.items) |op| {
                if (predicate(op)) {
                    self.items.items[write] = op;
                    write += 1;
                }
            }
            self.items.items.len = write;
        }

        /// Map ops in-place, transforming each with the mapper function.
        pub fn map(self: *Self, comptime mapper: fn (T) T) void {
            for (self.items.items) |*op| {
                op.* = mapper(op.*);
            }
        }
    };
}

/// Create a new OpList with the given allocator.
pub fn createOpList(comptime T: type, allocator: std.mem.Allocator) OpList(T) {
    return OpList(T).init(allocator);
}

/// ListEndOp — special marker op for the end of a list.
pub const ListEndOp = struct {
    kind: OpKind = .ListEnd,
};

/// StatementOp — wraps an output AST statement.
pub fn StatementOp(comptime OpT: type) type {
    return struct {
        kind: OpKind = .Statement,
        xref: XrefId = 0,
        statement: []const u8 = "",
        source_span: ?@import("../../source_span.zig").AbsoluteSourceSpan = null,
        _phantom: ?*const OpT = null,
    };
}

/// VariableOp — declares a SemanticVariable.
pub fn VariableOp(comptime OpT: type) type {
    return struct {
        kind: OpKind = .Variable,
        xref: XrefId = 0,
        name: []const u8 = "",
        value: []const u8 = "",
        source_span: ?@import("../../source_span.zig").AbsoluteSourceSpan = null,
        _phantom: ?*const OpT = null,
    };
}

test "OpList basic operations" {
    const allocator = std.testing.allocator;
    var list = OpList(u32).init(allocator);
    defer list.deinit();

    try list.append(1);
    try list.append(2);
    try list.append(3);

    try std.testing.expectEqual(@as(usize, 3), list.len());
    try std.testing.expectEqual(@as(u32, 1), list.first().?);
    try std.testing.expectEqual(@as(u32, 3), list.last().?);

    try list.prepend(0);
    try std.testing.expectEqual(@as(u32, 0), list.first().?);

    const removed = list.remove(0);
    try std.testing.expectEqual(@as(u32, 0), removed);
    try std.testing.expectEqual(@as(usize, 3), list.len());
}

test "OpList filter" {
    const allocator = std.testing.allocator;
    var list = OpList(u32).init(allocator);
    defer list.deinit();

    try list.append(1);
    try list.append(2);
    try list.append(3);
    try list.append(4);

    const isEven = struct {
        fn pred(n: u32) bool {
            return n % 2 == 0;
        }
    }.pred;

    list.filter(isEven);
    try std.testing.expectEqual(@as(usize, 2), list.len());
    try std.testing.expectEqual(@as(u32, 2), list.items.items[0]);
    try std.testing.expectEqual(@as(u32, 4), list.items.items[1]);
}
