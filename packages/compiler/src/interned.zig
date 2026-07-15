/// Interned String Pool — Zero-cost string interning
///
/// Tận dụng Zig comptime hash + runtime hashmap:
///   - Mỗi unique string chỉ lưu 1 lần trong memory
///   - So sánh string = so sánh pointer (O(1)) thay vì memcmp (O(n))
///   - comptime string hashing cho fast lookup
///
/// Đây là DOD (Data-Oriented Design) pattern:
///   - Dense array cho string storage
///   - HashMap cho O(1) lookup
///   - StringRef = index vào dense array (4 bytes thay vì 8/16 bytes pointer)
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Reference đến interned string — compact 4-byte index
pub const StringRef = u32;
pub const INVALID_REF: StringRef = std.math.maxInt(u32);

/// Interned string pool — dense storage + hash lookup
pub const StringPool = struct {
    allocator: Allocator,
    /// Dense string storage (each string null-terminated)
    strings: std.array_list.Managed([:0]const u8),
    /// String → index lookup
    map: std.StringHashMap(StringRef),

    pub fn init(allocator: Allocator) StringPool {
        return .{
            .allocator = allocator,
            .strings = std.array_list.Managed([:0]const u8).init(allocator),
            .map = std.StringHashMap(StringRef).init(allocator),
        };
    }

    pub fn deinit(self: *StringPool) void {
        self.map.deinit();
        // Free each interned string (allocated via dupeZ)
        for (self.strings.items) |s| {
            self.allocator.free(s);
        }
        self.strings.deinit();
    }

    /// Intern a string — returns existing ref if already interned
    pub fn intern(self: *StringPool, str: []const u8) !StringRef {
        if (self.map.get(str)) |ref| return ref;
        const owned = try self.allocator.dupeZ(u8, str);
        const ref: StringRef = @intCast(self.strings.items.len);
        try self.strings.append(owned);
        try self.map.putNoClobber(owned, ref);
        return ref;
    }

    /// Get interned string by ref
    pub fn get(self: *StringPool, ref: StringRef) []const u8 {
        return self.strings.items[ref];
    }

    /// Check if two refs are equal (O(1) — just compare indices)
    pub fn eq(_: *const StringPool, a: StringRef, b: StringRef) bool {
        return a == b;
    }

    /// Total unique strings
    pub fn size(self: *const StringPool) usize {
        return self.strings.items.len;
    }

    /// Pre-intern common Angular strings at init time
    pub fn preInternCommon(self: *StringPool) !void {
        const common = [_][]const u8{
            // Binding prefixes
            "[",          "]",           "(",            ")",            "[(",       ")]",
            "#",          "*",           "@",
            // Event/property prefixes
                       "bind-",        "on-",      "bindon-",
            // Special attributes
            "ng-content", "ng-template", "ng-container",
            // Control flow
            "@if",          "@else",    "@for",
            "@switch",    "@case",       "@defer",       "@placeholder", "@loading", "@error",
            // Common HTML
            "div",        "span",        "p",            "a",            "input",    "button",
            "class",      "style",       "id",           "href",         "src",      "type",
            "click",      "input",       "change",
            // Binding types
                  "attr",         "class",    "style",
            // i18n
            "i18n",       "i18n-",
            // Angular directives
                  "ngIf",         "ngFor",        "ngSwitch", "ngClass",
            "ngStyle",    "ngModel",
        };
        for (common) |s| {
            _ = try self.intern(s);
        }
    }
};

// ─── Tests ────────────────────────────────────────────────────

test "string interning deduplication" {
    const allocator = std.testing.allocator;
    var pool = StringPool.init(allocator);
    defer pool.deinit();

    const ref1 = try pool.intern("hello");
    const ref2 = try pool.intern("hello");
    const ref3 = try pool.intern("world");

    try std.testing.expectEqual(ref1, ref2);
    try std.testing.expect(ref1 != ref3);
    try std.testing.expectEqualStrings("hello", pool.get(ref1));
    try std.testing.expectEqualStrings("world", pool.get(ref3));
    try std.testing.expectEqual(@as(usize, 2), pool.size());
}

test "pre-intern common strings" {
    const allocator = std.testing.allocator;
    var pool = StringPool.init(allocator);
    defer pool.deinit();

    try pool.preInternCommon();
    try std.testing.expect(pool.size() > 40);

    const div_ref = try pool.intern("div");
    try std.testing.expectEqualStrings("div", pool.get(div_ref));
}
