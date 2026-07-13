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
    // Common HTML5 named entities (expanded from 13 to ~80).
    // Full HTML5 spec has ~2000+ entities — see Phase 4 of port plan.
    const entities = .{
        // ── Basic ──
        .{ "&amp;", "&" },
        .{ "&lt;", "<" },
        .{ "&gt;", ">" },
        .{ "&quot;", "\"" },
        .{ "&apos;", "'" },
        .{ "&nbsp;", "\xc2\xa0" },
        // ── Numeric ──
        .{ "&#39;", "'" },
        // ── Quotes ──
        .{ "&lsquo;", "\xe2\x80\x98" },
        .{ "&rsquo;", "\xe2\x80\x99" },
        .{ "&sbquo;", "\xe2\x80\x9a" },
        .{ "&ldquo;", "\xe2\x80\x9c" },
        .{ "&rdquo;", "\xe2\x80\x9d" },
        .{ "&bdquo;", "\xe2\x80\x9e" },
        // ── Dashes ──
        .{ "&mdash;", "\xe2\x80\x94" },
        .{ "&ndash;", "\xe2\x80\x93" },
        .{ "&hellip;", "\xe2\x80\xa6" },
        // ── Copyright/trademark ──
        .{ "&copy;", "\xc2\xa9" },
        .{ "&reg;", "\xc2\xae" },
        .{ "&trade;", "\xe2\x84\xa2" },
        // ── Arrows ──
        .{ "&larr;", "\xe2\x86\x90" },
        .{ "&uarr;", "\xe2\x86\x91" },
        .{ "&rarr;", "\xe2\x86\x92" },
        .{ "&darr;", "\xe2\x86\x93" },
        .{ "&harr;", "\xe2\x86\x94" },
        .{ "&lArr;", "\xe2\x87\x90" },
        .{ "&uArr;", "\xe2\x87\x91" },
        .{ "&rArr;", "\xe2\x87\x92" },
        .{ "&dArr;", "\xe2\x87\x93" },
        .{ "&hArr;", "\xe2\x87\x94" },
        // ── Math ──
        .{ "&plusmn;", "\xc2\xb1" },
        .{ "&times;", "\xc3\x97" },
        .{ "&divide;", "\xc3\xb7" },
        .{ "&minus;", "\xe2\x88\x92" },
        .{ "&lowast;", "\xe2\x88\x97" },
        .{ "&le;", "\xe2\x89\xa4" },
        .{ "&ge;", "\xe2\x89\xa5" },
        .{ "&ne;", "\xe2\x89\xa0" },
        .{ "&equiv;", "\xe2\x89\xa1" },
        .{ "&infin;", "\xe2\x88\x9e" },
        .{ "&radic;", "\xe2\x88\x9a" },
        .{ "&sum;", "\xe2\x88\x91" },
        .{ "&prod;", "\xe2\x88\x8f" },
        .{ "&int;", "\xe2\x88\xab" },
        .{ "&part;", "\xe2\x88\x82" },
        .{ "&forall;", "\xe2\x88\x80" },
        .{ "&exist;", "\xe2\x88\x83" },
        .{ "&empty;", "\xe2\x88\x85" },
        .{ "&nabla;", "\xe2\x88\x87" },
        .{ "&isin;", "\xe2\x88\x88" },
        .{ "&notin;", "\xe2\x88\x89" },
        .{ "&ni;", "\xe2\x88\x8b" },
        .{ "&cap;", "\xe2\x88\xa9" },
        .{ "&cup;", "\xe2\x88\xaa" },
        .{ "&sub;", "\xe2\x8a\x82" },
        .{ "&sup;", "\xe2\x8a\x83" },
        .{ "&there4;", "\xe2\x88\xb4" },
        .{ "&because;", "\xe2\x88\xb5" },
        .{ "&asymp;", "\xe2\x89\x88" },
        .{ "&cong;", "\xe2\x89\x85" },
        // ── Currency ──
        .{ "&cent;", "\xc2\xa2" },
        .{ "&pound;", "\xc2\xa3" },
        .{ "&yen;", "\xc2\xa5" },
        .{ "&euro;", "\xe2\x82\xac" },
        .{ "&sect;", "\xc2\xa7" },
        .{ "&para;", "\xc2\xb6" },
        .{ "&middot;", "\xc2\xb7" },
        // ── Guillemets ──
        .{ "&laquo;", "\xc2\xab" },
        .{ "&raquo;", "\xc2\xbb" },
        // ── Spaces ──
        .{ "&ensp;", "\xe2\x80\x82" },
        .{ "&emsp;", "\xe2\x80\x83" },
        .{ "&thinsp;", "\xe2\x80\x89" },
        .{ "&zwnj;", "\xe2\x80\x8c" },
        .{ "&zwj;", "\xe2\x80\x8d" },
        // ── Misc punctuation ──
        .{ "&bull;", "\xe2\x80\xa2" },
        .{ "&dagger;", "\xe2\x80\xa0" },
        .{ "&Dagger;", "\xe2\x80\xa1" },
        .{ "&permil;", "\xe2\x80\xb0" },
        .{ "&prime;", "\xe2\x80\xb2" },
        .{ "&Prime;", "\xe2\x80\xb3" },
        .{ "&spades;", "\xe2\x99\xa0" },
        .{ "&clubs;", "\xe2\x99\xa3" },
        .{ "&hearts;", "\xe2\x99\xa5" },
        .{ "&diams;", "\xe2\x99\xa6" },
    };

    inline for (entities) |e| {
        if (std.mem.eql(u8, entity, e.@"0")) {
            buf.appendSlice(e.@"1") catch return false;
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
            buf.appendSlice(encode_buf[0..len]) catch return false;
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
