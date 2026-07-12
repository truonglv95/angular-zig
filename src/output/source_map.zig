/// Source Map V3 with VLQ encoding
///
/// Generates standard Source Map V3 JSON for debugging.
/// DOD: Mappings stored in contiguous array, encoded in one pass.
///
/// VLQ encoding follows the spec:
///   1. Sign-encode: shift left 1, put sign bit in LSB
///   2. Split into 5-bit groups from LSB
///   3. For each group except last: set bit 5 (continuation), base64 encode
///   4. For last group: just base64 encode
///   5. Base64 chars: ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Base64 VLQ character set
const BASE64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/// Continuation bit mask (bit 5 in a 6-bit VLQ digit)
const VLQ_CONTINUATION_BIT: u6 = 1 << 5;
/// Value bits mask (lower 5 bits)
const VLQ_VALUE_MASK: u6 = (1 << 5) - 1;

pub const SourceMap = struct {
    file: []const u8,
    source_content: ?[]const u8,
    sources: std.array_list.Managed([]const u8),
    names: std.array_list.Managed([]const u8),
    mappings: std.array_list.Managed(Mapping),
    allocator: Allocator,

    pub const Mapping = struct {
        generated_line: u32,
        generated_column: u32,
        source_index: u32,
        source_line: u32,
        source_column: u32,
        name_index: u32,
    };

    pub fn init(allocator: Allocator, file: []const u8) SourceMap {
        return .{
            .file = file,
            .source_content = null,
            .sources = std.array_list.Managed([]const u8).init(allocator),
            .names = std.array_list.Managed([]const u8).init(allocator),
            .mappings = std.array_list.Managed(Mapping).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SourceMap) void {
        self.mappings.deinit();
        self.sources.deinit();
        self.names.deinit();
    }

    pub fn addMapping(self: *SourceMap, m: Mapping) !void {
        try self.mappings.append(m);
    }

    pub fn addSource(self: *SourceMap, source: []const u8) !u32 {
        // Check for duplicate
        for (self.sources.items, 0..) |existing, i| {
            if (std.mem.eql(u8, existing, source)) {
                return @intCast(i);
            }
        }
        const index: u32 = @intCast(self.sources.items.len);
        try self.sources.append(source);
        return index;
    }

    pub fn addName(self: *SourceMap, name: []const u8) !u32 {
        // Check for duplicate
        for (self.names.items, 0..) |existing, i| {
            if (std.mem.eql(u8, existing, name)) {
                return @intCast(i);
            }
        }
        const index: u32 = @intCast(self.names.items.len);
        try self.names.append(name);
        return index;
    }

    /// Encode all mappings as a VLQ string (the "mappings" field in source map JSON).
    ///
    /// Algorithm:
    ///   1. Sort mappings by (generated_line, generated_column)
    ///   2. First mapping encodes absolute values
    ///   3. Subsequent mappings encode DELTAS from previous
    ///   4. Fields per segment: [genCol, sourceIdx, sourceLine, sourceCol, nameIdx]
    ///   5. Semicolons separate lines, commas separate segments within a line
    pub fn encodeMappings(self: *SourceMap) ![]const u8 {
        if (self.mappings.items.len == 0) {
            // Always return an allocator-owned slice so callers can safely free it
            return self.allocator.dupe(u8, "");
        }

        // Sort mappings by generated position
        const sorted = try self.sortMappings();
        defer self.allocator.free(sorted);

        // Encode segments
        var aw = std.Io.Writer.Allocating.initCapacity(self.allocator, sorted.len * 16) catch return error.OutOfMemory;
        defer aw.deinit();

        var prev_gen_line: u32 = 0;
        var prev_gen_col: i32 = 0;
        var prev_source_idx: i32 = 0;
        var prev_source_line: i32 = 0;
        var prev_source_col: i32 = 0;
        var prev_name_idx: i32 = 0;
        var last_byte: u8 = 0;
        var has_output = false;

        for (sorted) |m| {
            // Emit semicolons for any skipped lines
            while (prev_gen_line < m.generated_line) : (prev_gen_line += 1) {
                try aw.writer.writeByte(';');
                last_byte = ';';
                has_output = true;
                // New line resets the generated column state
                prev_gen_col = 0;
            }

            // Emit comma separator between segments on same line
            if (has_output and last_byte != ';') {
                try aw.writer.writeByte(',');
                last_byte = ',';
            }

            // Encode generated column delta
            const gen_col_delta = @as(i32, @intCast(m.generated_column)) - prev_gen_col;
            try vlqEncode(gen_col_delta, &aw.writer);
            has_output = true;
            last_byte = 0; // VLQ encoding may have written multiple bytes
            prev_gen_col = @intCast(m.generated_column);

            // Source index delta
            const src_idx_delta = @as(i32, @intCast(m.source_index)) - prev_source_idx;
            try vlqEncode(src_idx_delta, &aw.writer);
            prev_source_idx = @intCast(m.source_index);

            // Source line delta (0-based)
            const src_line_delta = @as(i32, @intCast(m.source_line)) - prev_source_line;
            try vlqEncode(src_line_delta, &aw.writer);
            prev_source_line = @intCast(m.source_line);

            // Source column delta
            const src_col_delta = @as(i32, @intCast(m.source_column)) - prev_source_col;
            try vlqEncode(src_col_delta, &aw.writer);
            prev_source_col = @intCast(m.source_column);

            // Name index delta (only if name_index != 0, meaning no name)
            if (m.name_index > 0) {
                const name_idx_delta = @as(i32, @intCast(m.name_index)) - prev_name_idx;
                try vlqEncode(name_idx_delta, &aw.writer);
                prev_name_idx = @intCast(m.name_index);
            }
        }

        var list = aw.toArrayList();
        return list.toOwnedSlice(self.allocator);
    }

    /// Sort mappings by (generated_line, generated_column).
    /// Returns a new sorted slice (allocated, caller doesn't own —
    /// the returned slice borrows from the internal allocation).
    fn sortMappings(self: *SourceMap) ![]const Mapping {
        // Copy to sortable slice
        const items = self.mappings.items;
        const sorted = try self.allocator.dupe(Mapping, items);
        std.mem.sort(Mapping, sorted, {}, struct {
            fn lessThan(_: void, a: Mapping, b: Mapping) bool {
                if (a.generated_line != b.generated_line) {
                    return a.generated_line < b.generated_line;
                }
                return a.generated_column < b.generated_column;
            }
        }.lessThan);
        return sorted;
    }

    /// Serialize the full source map as a JSON string.
    ///
    /// Produces:
    /// ```json
    /// {
    ///   "version": 3,
    ///   "file": "...",
    ///   "sourceRoot": "",
    ///   "sources": [...],
    ///   "names": [...],
    ///   "mappings": "..."
    /// }
    /// ```
    /// If source_content is set, adds "sourcesContent": [...].
    pub fn toJson(self: *SourceMap) ![]const u8 {
        const mappings_str = try self.encodeMappings();
        defer self.allocator.free(mappings_str);

        // Estimate buffer size
        var aw = std.Io.Writer.Allocating.init(self.allocator);
        defer aw.deinit();

        const w = &aw.writer;

        try w.writeAll("{\"version\":3,\"file\":\"");
        try writeJsonString(w, self.file);
        try w.writeAll("\",\"sourceRoot\":\"\",\"sources\":[");

        // Sources array
        for (self.sources.items, 0..) |src, i| {
            if (i > 0) try w.writeAll(",");
            try w.writeAll("\"");
            try writeJsonString(w, src);
            try w.writeAll("\"");
        }

        try w.writeAll("],\"names\":[");

        // Names array
        for (self.names.items, 0..) |name, i| {
            if (i > 0) try w.writeAll(",");
            try w.writeAll("\"");
            try writeJsonString(w, name);
            try w.writeAll("\"");
        }

        try w.writeAll("],\"mappings\":\"");
        try writeJsonString(w, mappings_str);
        try w.writeAll("\"");

        // Optional sourcesContent
        if (self.source_content) |content| {
            try w.writeAll(",\"sourcesContent\":[\"");
            try writeJsonString(w, content);
            try w.writeAll("\"]");
        }

        try w.writeAll("}");

        var list = aw.toArrayList();
        return list.toOwnedSlice(self.allocator);
    }
};

// ─── VLQ Encoding ────────────────────────────────────────────

/// Encode a signed integer as a base64 VLQ string segment.
///
/// Algorithm:
///   1. Sign-encode: vlq = (value << 1) | (value < 0 ? 1 : 0)
///   2. Take lowest 5 bits; if more bits remain, set continuation bit
///   3. Repeat until all bits consumed
fn vlqEncode(value: i32, writer: anytype) !void {
    // Sign-encode: shift left 1, put sign bit in LSB
    // Use u33 to hold the sign-encoded value (i32 needs 32 bits + 1 sign = 33)
    var vlq: u33 = if (value < 0) blk: {
        // Compute abs(value) via two's complement in u32 to avoid
        // overflow for i32 min value (-2147483648).
        const bits: u32 = @bitCast(value);
        const abs_u32: u32 = ~bits + 1;
        break :blk (@as(u33, abs_u32) << 1) | 1;
    } else @as(u33, @intCast(value)) << 1;

    // Encode 5-bit groups, LSB first
    while (true) {
        var digit: u6 = @truncate(vlq & VLQ_VALUE_MASK);
        vlq >>= 5;

        // If more bits remain, set continuation bit
        if (vlq > 0) {
            digit |= VLQ_CONTINUATION_BIT;
        }

        try writer.writeByte(BASE64_CHARS[digit]);

        if (vlq == 0) break;
    }
}

/// Encode a signed integer and return the VLQ string as an allocated slice.
/// Convenience wrapper for testing.
pub fn vlqEncodeAlloc(allocator: Allocator, value: i32) ![]const u8 {
    var aw = std.Io.Writer.Allocating.initCapacity(allocator, 8) catch return error.OutOfMemory;
    defer aw.deinit();
    try vlqEncode(value, &aw.writer);
    var list = aw.toArrayList();
    return list.toOwnedSlice(allocator);
}

/// Write a string with JSON escaping (handles backslashes, quotes, etc.)
fn writeJsonString(writer: anytype, s: []const u8) !void {
    for (s) |ch| {
        switch (ch) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(ch),
        }
    }
}

// ─── Tests ────────────────────────────────────────────────────

test "vlqEncode — zero" {
    const allocator = std.testing.allocator;
    const result = try vlqEncodeAlloc(allocator, 0);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("A", result);
}

test "vlqEncode — positive small" {
    const allocator = std.testing.allocator;
    const r1 = try vlqEncodeAlloc(allocator, 1);
    defer allocator.free(r1);
    try std.testing.expectEqualStrings("C", r1); // 1 << 1 = 2 → 'C'

    const r2 = try vlqEncodeAlloc(allocator, 2);
    defer allocator.free(r2);
    try std.testing.expectEqualStrings("E", r2); // 2 << 1 = 4 → 'E'

    const r5 = try vlqEncodeAlloc(allocator, 5);
    defer allocator.free(r5);
    try std.testing.expectEqualStrings("K", r5); // 5 << 1 = 10 → 'K'
}

test "vlqEncode — negative small" {
    const allocator = std.testing.allocator;
    const r1 = try vlqEncodeAlloc(allocator, -1);
    defer allocator.free(r1);
    try std.testing.expectEqualStrings("D", r1); // (1 << 1) | 1 = 3 → 'D'

    const r2 = try vlqEncodeAlloc(allocator, -2);
    defer allocator.free(r2);
    try std.testing.expectEqualStrings("F", r2); // (2 << 1) | 1 = 5 → 'F'
}

test "vlqEncode — multi-digit 16" {
    const allocator = std.testing.allocator;
    // 16 << 1 = 32 = 0b100000
    // Group 0: 00000 = 0, remaining 1 → continuation set
    // digit = 0 | 32 = 32 → BASE64_CHARS[32] = 'g'
    // Group 1: 00001 = 1, remaining 0 → no continuation
    // BASE64_CHARS[1] = 'B'
    const r = try vlqEncodeAlloc(allocator, 16);
    defer allocator.free(r);
    try std.testing.expectEqualStrings("gB", r);
}

test "vlqEncode — large positive 1000" {
    const allocator = std.testing.allocator;
    // Value 1000: 1000 << 1 = 2000 = 0b11111010000
    // Group 0: 10000 = 16, remaining 31 → continuation
    // digit = 16 | 32 = 48 → BASE64_CHARS[48] = 'w'
    // Group 1: 11111 = 31, remaining 0 → no continuation
    // BASE64_CHARS[31] = 'f'
    const r = try vlqEncodeAlloc(allocator, 1000);
    defer allocator.free(r);
    try std.testing.expectEqualStrings("wf", r);
}

test "SourceMap addMapping and encodeMappings" {
    const allocator = std.testing.allocator;
    var sm = SourceMap.init(allocator, "output.js");
    defer sm.deinit();

    const src_idx = try sm.addSource("input.ts");
    try std.testing.expectEqual(@as(u32, 0), src_idx);

    // Add a mapping: generated line 0, col 10 → source line 2, col 5
    try sm.addMapping(.{
        .generated_line = 0,
        .generated_column = 10,
        .source_index = 0,
        .source_line = 2,
        .source_column = 5,
        .name_index = 0,
    });

    const encoded = try sm.encodeMappings();
    defer allocator.free(encoded);
    // First segment encodes absolute values: genCol=10, srcIdx=0, srcLine=2, srcCol=5
    // 10 << 1 = 20 → 'U' (index 20)
    // 0 << 1 = 0 → 'A'
    // 2 << 1 = 4 → 'E'
    // 5 << 1 = 10 → 'K'
    try std.testing.expectEqualStrings("UAEK", encoded);
}

test "SourceMap multiple mappings with deltas" {
    const allocator = std.testing.allocator;
    var sm = SourceMap.init(allocator, "output.js");
    defer sm.deinit();

    _ = try sm.addSource("input.ts");

    // Mapping 1: gen(0,10) → src(0, 2, 5)
    try sm.addMapping(.{
        .generated_line = 0,
        .generated_column = 10,
        .source_index = 0,
        .source_line = 2,
        .source_column = 5,
        .name_index = 0,
    });

    // Mapping 2: gen(0,20) → src(0, 3, 0) — same line, delta from mapping 1
    try sm.addMapping(.{
        .generated_line = 0,
        .generated_column = 20,
        .source_index = 0,
        .source_line = 3,
        .source_column = 0,
        .name_index = 0,
    });

    const encoded = try sm.encodeMappings();
    defer allocator.free(encoded);

    // First segment: genCol=10, srcIdx=0, srcLine=2, srcCol=5 → UAEK
    // Comma separator
    // Second segment (deltas): genCol=10, srcIdx=0, srcLine=1, srcCol=-5
    // 10 << 1 = 20 → 'U'
    // 0 → 'A'
    // 1 << 1 = 2 → 'C'
    // -5: (5 << 1) | 1 = 11 → 'L'
    try std.testing.expectEqualStrings("UAEK,UACL", encoded);
}

test "SourceMap multiple lines with semicolons" {
    const allocator = std.testing.allocator;
    var sm = SourceMap.init(allocator, "output.js");
    defer sm.deinit();

    _ = try sm.addSource("input.ts");

    // Line 0, col 0 → src(0, 0)
    try sm.addMapping(.{
        .generated_line = 0,
        .generated_column = 0,
        .source_index = 0,
        .source_line = 0,
        .source_column = 0,
        .name_index = 0,
    });

    // Line 2, col 5 → src(0, 10)
    try sm.addMapping(.{
        .generated_line = 2,
        .generated_column = 5,
        .source_index = 0,
        .source_line = 0,
        .source_column = 10,
        .name_index = 0,
    });

    const encoded = try sm.encodeMappings();
    defer allocator.free(encoded);

    // Line 0: AAAA (all zeros)
    // Skip line 1: ';'
    // Line 2: genCol=5 (absolute, since new line), srcIdx=0 (delta from prev 0=0), srcLine=0 (delta), srcCol=10
    // 5 << 1 = 10 → 'K'
    // 0 → 'A'
    // 0 → 'A'
    // 10 << 1 = 20 → 'U'
    try std.testing.expectEqualStrings("AAAA;;KAAU", encoded);
}

test "SourceMap toJson basic" {
    const allocator = std.testing.allocator;
    var sm = SourceMap.init(allocator, "test.js");
    defer sm.deinit();

    _ = try sm.addSource("test.ts");

    try sm.addMapping(.{
        .generated_line = 0,
        .generated_column = 0,
        .source_index = 0,
        .source_line = 0,
        .source_column = 0,
        .name_index = 0,
    });

    const json = try sm.toJson();
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"version\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"file\":\"test.js\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"sources\":[\"test.ts\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"mappings\":\"") != null);
}

test "SourceMap toJson with sourceContent" {
    const allocator = std.testing.allocator;
    var sm = SourceMap.init(allocator, "test.js");
    defer sm.deinit();

    sm.source_content = "const x = 1;";
    _ = try sm.addSource("test.ts");

    const json = try sm.toJson();
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"sourcesContent\"") != null);
}

test "SourceMap addSource deduplication" {
    const allocator = std.testing.allocator;
    var sm = SourceMap.init(allocator, "test.js");
    defer sm.deinit();

    const idx1 = try sm.addSource("a.ts");
    const idx2 = try sm.addSource("b.ts");
    const idx3 = try sm.addSource("a.ts"); // duplicate

    try std.testing.expectEqual(@as(u32, 0), idx1);
    try std.testing.expectEqual(@as(u32, 1), idx2);
    try std.testing.expectEqual(@as(u32, 0), idx3);
}

test "SourceMap addName deduplication" {
    const allocator = std.testing.allocator;
    var sm = SourceMap.init(allocator, "test.js");
    defer sm.deinit();

    const idx1 = try sm.addName("foo");
    const idx2 = try sm.addName("bar");
    const idx3 = try sm.addName("foo"); // duplicate

    try std.testing.expectEqual(@as(u32, 0), idx1);
    try std.testing.expectEqual(@as(u32, 1), idx2);
    try std.testing.expectEqual(@as(u32, 0), idx3);
}

test "SourceMap empty mappings" {
    const allocator = std.testing.allocator;
    var sm = SourceMap.init(allocator, "test.js");
    defer sm.deinit();

    const encoded = try sm.encodeMappings();
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("", encoded);
}

test "SourceMap mapping with name" {
    const allocator = std.testing.allocator;
    var sm = SourceMap.init(allocator, "test.js");
    defer sm.deinit();

    _ = try sm.addSource("input.ts");
    const name_idx = try sm.addName("myFunction");

    try sm.addMapping(.{
        .generated_line = 0,
        .generated_column = 0,
        .source_index = 0,
        .source_line = 0,
        .source_column = 0,
        .name_index = name_idx,
    });

    const encoded = try sm.encodeMappings();
    defer allocator.free(encoded);

    // AAAA + name index 1: 1 << 1 = 2 → 'C'
    try std.testing.expectEqualStrings("AAAAC", encoded);
}

test "vlqEncode round-trip validation" {
    // Validate that the VLQ encoding matches the standard source map spec
    // by checking known values from the source-map spec examples:
    //   A → 0, C → 1, D → -1, E → 2, F → -2, etc.
    const allocator = std.testing.allocator;

    const r0 = try vlqEncodeAlloc(allocator, 0);
    defer allocator.free(r0);
    try std.testing.expectEqualStrings("A", r0);

    const r_pos1 = try vlqEncodeAlloc(allocator, 1);
    defer allocator.free(r_pos1);
    try std.testing.expectEqualStrings("C", r_pos1);

    const r_neg1 = try vlqEncodeAlloc(allocator, -1);
    defer allocator.free(r_neg1);
    try std.testing.expectEqualStrings("D", r_neg1);

    const r_pos2 = try vlqEncodeAlloc(allocator, 2);
    defer allocator.free(r_pos2);
    try std.testing.expectEqualStrings("E", r_pos2);

    const r_neg2 = try vlqEncodeAlloc(allocator, -2);
    defer allocator.free(r_neg2);
    try std.testing.expectEqualStrings("F", r_neg2);
}
