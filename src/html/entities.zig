/// HTML Entity Decoding
const std = @import("std");

/// Decode common HTML entities
pub fn decodeEntities(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '&') {
            if (std.mem.indexOfScalarPos(u8, input, i, ';')) |semi_pos| {
                const entity = input[i .. semi_pos + 1];
                if (resolveEntityInto(&buf, entity)) {
                    i = semi_pos + 1;
                    continue;
                }
            }
        }
        try buf.append(input[i]);
        i += 1;
    }
    return buf.toOwnedSlice();
}

/// Named entity resolution — writes directly into buf, returns true if resolved.
fn resolveEntityInto(buf: *std.array_list.Managed(u8), entity: []const u8) bool {
    const entities = .{
        .{ "&amp;", "&" },
        .{ "&lt;", "<" },
        .{ "&gt;", ">" },
        .{ "&quot;", "\"" },
        .{ "&apos;", "'" },
        .{ "&nbsp;", "\xc2\xa0" },
        .{ "&#39;", "'" },
        .{ "&copy;", "\xc2\xa9" },
        .{ "&reg;", "\xc2\xae" },
        .{ "&mdash;", "\xe2\x80\x94" },
        .{ "&ndash;", "\xe2\x80\x93" },
        .{ "&laquo;", "\xc2\xab" },
        .{ "&raquo;", "\xc2\xbb" },
        .{ "&hellip;", "\xe2\x80\xa6" },
    };

    inline for (entities) |e| {
        if (std.mem.eql(u8, entity, e.@"0")) {
            buf.appendSliceAssumeCapacity(e.@"1");
            return true;
        }
    }

    // Numeric entities: &#NNN; or &#xNN;
    if (entity.len > 3 and entity[1] == '#') {
        var code_point: u21 = undefined;
        _ = if (entity.len > 4 and (entity[2] == 'x' or entity[2] == 'X')) blk: {
            code_point = std.fmt.parseInt(u21, entity[3 .. entity.len - 1], 16) catch return false;
            break :blk 0;
        } else blk: {
            code_point = std.fmt.parseInt(u21, entity[2 .. entity.len - 1], 10) catch return false;
            break :blk 0;
        };

        // Reject null and surrogates
        if (code_point == 0 or (code_point >= 0xD800 and code_point <= 0xDFFF)) return false;

        // UTF-8 encode directly into the buffer
        var encode_buf: [4]u8 = undefined;
        if (std.unicode.utf8Encode(code_point, &encode_buf)) |len| {
            buf.appendSliceAssumeCapacity(encode_buf[0..len]);
            return true;
        } else |_| {
            return false;
        }
    }

    return false;
}

test "decode common entities" {
    const allocator = std.testing.allocator;
    const result = try decodeEntities(allocator, "a &amp; b &lt; c");
    try std.testing.expectEqualStrings("a & b < c", result);
    allocator.free(result);
}

test "decode numeric decimal entities" {
    const allocator = std.testing.allocator;
    const result = try decodeEntities(allocator, "&#65;&#66;&#67;");
    try std.testing.expectEqualStrings("ABC", result);
    allocator.free(result);
}

test "decode numeric hex entities" {
    const allocator = std.testing.allocator;
    const result = try decodeEntities(allocator, "&#x41;&#x42;&#x43;");
    try std.testing.expectEqualStrings("ABC", result);
    allocator.free(result);
}

test "decode mixed entities" {
    const allocator = std.testing.allocator;
    const result = try decodeEntities(allocator, "&amp;&#39;&lt;");
    try std.testing.expectEqualStrings("&'<", result);
    allocator.free(result);
}

test "decode unicode entities" {
    const allocator = std.testing.allocator;
    // &#x2764; = ❤ (U+2764)
    const result = try decodeEntities(allocator, "&#x2764;");
    try std.testing.expectEqualStrings("\xe2\x9d\xa4", result);
    allocator.free(result);
}

test "invalid numeric entity passes through" {
    const allocator = std.testing.allocator;
    const result = try decodeEntities(allocator, "&#ZZZ;");
    try std.testing.expectEqualStrings("&#ZZZ;", result);
    allocator.free(result);
}

test "no entities returns input" {
    const allocator = std.testing.allocator;
    const result = try decodeEntities(allocator, "hello world");
    try std.testing.expectEqualStrings("hello world", result);
    allocator.free(result);
}
