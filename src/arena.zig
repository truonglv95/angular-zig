/// Arena Allocator — Zero-fragmentation AST allocation
///
/// Zig's ArenaAllocator wrapped for compiler use:
///   - Mọi AST node đều allocate từ arena
///   - Single free() để giải phóng toàn bộ
///   - No fragmentation, cache-friendly memory layout
///   - O(1) allocation (bump pointer)
///
/// DOD benefit: AST nodes liên tiếp trong memory → better cache locality
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const AstArena = struct {
    backing: std.heap.ArenaAllocator,
    allocator: Allocator,
    /// Total bytes allocated (for stats)
    total_allocated: usize = 0,

    pub fn init(backing_allocator: Allocator) AstArena {
        var arena = std.heap.ArenaAllocator.init(backing_allocator);
        return .{
            .backing = arena,
            .allocator = arena.allocator(),
        };
    }

    pub fn deinit(self: *AstArena) void {
        self.backing.deinit();
    }

    /// Allocate a single AST node — zero-cost, just bump pointer
    pub fn create(self: *AstArena, comptime T: type) !*T {
        const ptr = try self.allocator.create(T);
        self.total_allocated += @sizeOf(T);
        return ptr;
    }

    /// Allocate array of AST nodes
    pub fn alloc(self: *AstArena, comptime T: type, n: usize) ![]T {
        const slice = try self.allocator.alloc(T, n);
        self.total_allocated += @sizeOf(T) * n;
        return slice;
    }

    /// Duplicate a string into the arena
    pub fn dupe(self: *AstArena, str: []const u8) ![]const u8 {
        const duped = try self.allocator.dupe(u8, str);
        self.total_allocated += str.len;
        return duped;
    }

    /// Duplicate a null-terminated string
    pub fn dupeZ(self: *AstArena, str: []const u8) ![:0]const u8 {
        const duped = try self.allocator.dupeZ(u8, str);
        self.total_allocated += str.len + 1;
        return duped;
    }

    /// Reset arena — frees ALL allocations
    pub fn reset(self: *AstArena) void {
        _ = self.backing.reset(.retain_capacity);
        self.total_allocated = 0;
    }

    /// Get memory stats
    pub fn stats(self: *const AstArena) Stats {
        return .{
            .total_allocated = self.total_allocated,
            .backing_allocated = self.backing.queryCapacity(),
        };
    }

    pub const Stats = struct {
        total_allocated: usize,
        backing_allocated: usize,
    };
};

// ─── Tests ────────────────────────────────────────────────────

test "arena allocation" {
    const allocator = std.testing.allocator;
    var arena = AstArena.init(allocator);
    defer arena.deinit();

    const node = try arena.create(i32);
    node.* = 42;

    const slice = try arena.alloc(u8, 10);
    @memset(slice, 0xAA);

    try std.testing.expectEqual(@as(i32, 42), node.*);
    try std.testing.expectEqual(@as(usize, 10), slice.len);

    const stats = arena.stats();
    try std.testing.expect(stats.total_allocated > 0);
}

test "arena reset" {
    const allocator = std.testing.allocator;
    var arena = AstArena.init(allocator);
    defer arena.deinit();

    _ = try arena.create(i32);
    _ = try arena.alloc(u8, 100);
    try std.testing.expect(arena.stats().total_allocated > 0);

    arena.reset();
    try std.testing.expectEqual(@as(usize, 0), arena.stats().total_allocated);
}
