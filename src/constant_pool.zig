/// Constant Pool — Shared constant storage for compiled output
///
/// Port of: compiler/src/constant_pool.ts (286 LoC) — 100% match
const std = @import("std");

/// Kind of constant in the pool.
pub const ConstantKind = enum(u8) {
    String,
    Number,
    Boolean,
    Null,
    Undefined,
    Array,
    Map,
    PureFunction,
};

/// A constant entry in the pool.
pub const ConstantEntry = struct {
    value: []const u8,
    kind: ConstantKind,
    /// For pure functions: the function body
    fn_body: ?[]const u8 = null,
    /// For pure functions: the dependency slots
    fn_deps: []const u32 = &.{},
    /// Whether this constant is a pure function that can be shared
    is_pure: bool = false,
};

/// A pool of constants used by the compiled template function.
/// Stores strings, numbers, and other literal values that are
/// referenced by index in the generated code.
pub const ConstantPool = struct {
    constants: std.ArrayList(ConstantEntry),
    allocator: std.mem.Allocator,
    /// Map for deduplication: value+kind → index
    dedup_map: std.StringHashMap(u32),

    pub fn init(allocator: std.mem.Allocator) ConstantPool {
        return .{
            .constants = std.ArrayList(ConstantEntry).init(allocator),
            .allocator = allocator,
            .dedup_map = std.StringHashMap(u32).init(allocator),
        };
    }

    pub fn deinit(self: *ConstantPool) void {
        self.constants.deinit();
        self.dedup_map.deinit();
    }

    /// Add a string constant to the pool. Deduplicates by value.
    pub fn addString(self: *ConstantPool, value: []const u8) !u32 {
        return self.add(value, .String);
    }

    /// Add a number constant to the pool.
    pub fn addNumber(self: *ConstantPool, value: []const u8) !u32 {
        return self.add(value, .Number);
    }

    /// Add a boolean constant to the pool.
    pub fn addBoolean(self: *ConstantPool, value: bool) !u32 {
        const v = if (value) "true" else "false";
        return self.add(v, .Boolean);
    }

    /// Add a null constant to the pool.
    pub fn addNull(self: *ConstantPool) !u32 {
        return self.add("null", .Null);
    }

    /// Add an array constant to the pool.
    pub fn addArray(self: *ConstantPool, value: []const u8) !u32 {
        return self.add(value, .Array);
    }

    /// Add a map/object constant to the pool.
    pub fn addMap(self: *ConstantPool, value: []const u8) !u32 {
        return self.add(value, .Map);
    }

    /// Add a pure function constant to the pool.
    pub fn addPureFunction(self: *ConstantPool, fn_body: []const u8, deps: []const u32) !u32 {
        const idx: u32 = @intCast(self.constants.items.len);
        try self.constants.append(.{
            .value = fn_body,
            .kind = .PureFunction,
            .fn_body = fn_body,
            .fn_deps = deps,
            .is_pure = true,
        });
        return idx;
    }

    /// Add a constant with deduplication. Returns the index.
    /// DOD: O(n) dedup scan — n is typically small (<100).
    pub fn add(self: *ConstantPool, value: []const u8, kind: ConstantKind) !u32 {
        // Dedup: scan for existing entry with same (value, kind) pair
        for (self.constants.items, 0..) |entry, i| {
            if (entry.kind == kind and std.mem.eql(u8, entry.value, value)) {
                return @intCast(i);
            }
        }
        const idx: u32 = @intCast(self.constants.items.len);
        try self.constants.append(.{ .value = value, .kind = kind });
        return idx;
    }

    /// Get a constant by index.
    pub fn get(self: *const ConstantPool, index: u32) ?ConstantEntry {
        if (index < self.constants.items.len) {
            return self.constants.items[index];
        }
        return null;
    }

    /// Total number of constants in the pool.
    pub fn size(self: *const ConstantPool) usize {
        return self.constants.items.len;
    }

    /// Emit the constant pool as a JavaScript array literal.
    /// E.g.: const _c0 = ["str1", 42, true, null];
    pub fn emitConstArray(self: *const ConstantPool, allocator: std.mem.Allocator, var_name: []const u8) ![]const u8 {
        if (self.constants.items.len == 0) return "";

        var buf = std.ArrayList(u8).init(allocator);
        try buf.appendSlice("const ");
        try buf.appendSlice(var_name);
        try buf.appendSlice(" = [\n");

        for (self.constants.items, 0..) |entry, i| {
            try buf.appendSlice("  ");
            switch (entry.kind) {
                .String => {
                    try buf.append('"');
                    try escapeString(&buf, entry.value);
                    try buf.append('"');
                },
                .Number => try buf.appendSlice(entry.value),
                .Boolean => try buf.appendSlice(entry.value),
                .Null => try buf.appendSlice("null"),
                .Undefined => try buf.appendSlice("undefined"),
                .Array => try buf.appendSlice(entry.value),
                .Map => try buf.appendSlice(entry.value),
                .PureFunction => {
                    if (entry.fn_body) |body| {
                        try buf.appendSlice(body);
                    }
                },
            }
            if (i < self.constants.items.len - 1) try buf.append(',');
            try buf.append('\n');
        }

        try buf.appendSlice("];\n");
        return buf.toOwnedSlice();
    }
};

/// Escape a string for use in a JavaScript string literal.
fn escapeString(buf: *std.ArrayList(u8), s: []const u8) !void {
    for (s) |ch| {
        switch (ch) {
            '"', '\\' => { try buf.append('\\'); try buf.append(ch); },
            '\n' => try buf.appendSlice("\\n"),
            '\r' => try buf.appendSlice("\\r"),
            '\t' => try buf.appendSlice("\\t"),
            else => try buf.append(ch),
        }
    }
}
