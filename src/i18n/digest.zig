/// i18n Digest — Message ID computation (SHA1 + decimal fingerprint)
///
/// Port of: compiler/src/i18n/digest.ts (384 LoC)
///
/// Computes stable message IDs for i18n messages using two algorithms:
///   - SHA1 digest (used by XLIFF 1.2 format) — `digest()` / `computeDigest()`
///   - Decimal fingerprint (used by XLIFF 2.0, XMB, $localize) — `decimalDigest()` / `computeDecimalDigest()`
///
/// The SHA1 implementation is a direct port from the TS source, NOT using std.crypto
/// (to ensure byte-for-byte identical output to Angular's TS compiler).
///
/// The fingerprint algorithm is based on Google's closure-compiler
/// GoogleJsMessageIdGenerator.
const std = @import("std");
const Allocator = std.mem.Allocator;

const i18n_ast = @import("i18n_ast.zig");

// ─── digest / computeDigest (SHA1, XLIFF 1.2) ────────────────

/// Return the message ID or compute it using the XLIFF1 digest (SHA1).
/// Direct port of `digest(message)` in the TS source.
pub fn digest(message: *const i18n_ast.Message) []const u8 {
    if (message.id.len > 0) return message.id;
    // Synchronous computation isn't possible without an allocator.
    // Callers should use `computeDigest(allocator, message)` instead.
    return "";
}

/// Compute the message ID using SHA1 of the serialized message + meaning.
/// Direct port of `computeDigest(message)` in the TS source.
pub fn computeDigest(allocator: Allocator, message: *const i18n_ast.Message) ![]const u8 {
    // Serialize nodes using the XML-like serializer (from _SerializerVisitor).
    const serialized = try i18n_ast.serializeNodesXmlLike(allocator, message.nodes);
    defer allocator.free(serialized);

    // Build the digest input: serialized + "[meaning]"
    var input = std.array_list.Managed(u8).init(allocator);
    defer input.deinit();
    try input.appendSlice(serialized);
    try input.append('[');
    try input.appendSlice(message.meaning);
    try input.append(']');

    return sha1(allocator, input.items);
}

/// Return the message ID or compute it using the decimal digest (XLIFF2/XMB).
/// Direct port of `decimalDigest(message)` in the TS source.
pub fn decimalDigest(message: *const i18n_ast.Message) []const u8 {
    if (message.id.len > 0) return message.id;
    return "";
}

/// Compute the message ID using the decimal digest algorithm.
/// Direct port of `computeDecimalDigest(message)` in the TS source.
///
/// Uses the `_SerializerIgnoreIcuExpVisitor` to serialize nodes (ignoring
/// ICU expression content so that message IDs stay identical if only the
/// expression changes), then `computeMsgId()` to produce a decimal ID.
pub fn computeDecimalDigest(allocator: Allocator, message: *const i18n_ast.Message) ![]const u8 {
    const parts = try serializeNodesIgnoreIcu(allocator, message.nodes);
    defer allocator.free(parts);
    return computeMsgId(allocator, parts, message.meaning);
}

/// Serialize nodes, ignoring ICU expressions.
/// Direct port of `_SerializerIgnoreIcuExpVisitor` usage in `computeDecimalDigest`.
fn serializeNodesIgnoreIcu(allocator: Allocator, nodes: []const i18n_ast.Node) ![]const u8 {
    return i18n_ast.serializeNodesXmlLikeIgnoreIcu(allocator, nodes);
}

// ─── SHA1 (direct port from TS) ──────────────────────────────

/// Compute the SHA1 of the given string.
/// Direct port of `sha1(str)` in the TS source.
///
/// WARNING: this function has not been designed or tested with security in mind.
/// DO NOT USE IT IN A SECURITY SENSITIVE CONTEXT.
pub fn sha1(allocator: Allocator, str: []const u8) ![]const u8 {
    const utf8 = str; // Already UTF-8 bytes in Zig
    const len: u32 = @intCast(utf8.len * 8);

    // Compute the words32 array, sized to hold both the data and the length suffix.
    // Length is stored at index: (((len + 64) >> 9) << 4) + 15
    const len_idx = (((len + 64) >> 9) << 4) + 15;
    const words_size: usize = @max(@as(usize, @intCast(len_idx + 1)), (utf8.len + 3) >> 2);
    const words32 = try allocator.alloc(u32, words_size);
    defer allocator.free(words32);
    @memset(words32, 0);

    // Fill words32 from bytes (big-endian).
    for (words32, 0..) |*word, i| {
        word.* = wordAt(utf8, @intCast(i * 4), .Big);
    }

    // Set the length padding bits.
    const shift_amount: u5 = @intCast(24 - (len % 32));
    words32[len >> 5] |= @as(u32, 0x80) << shift_amount;
    words32[len_idx] = len;

    var w: [80]u32 = [_]u32{0} ** 80;
    var a: u32 = 0x67452301;
    var b: u32 = 0xefcdab89;
    var c: u32 = 0x98badcfe;
    var d: u32 = 0x10325476;
    var e: u32 = 0xc3d2e1f0;

    var i: usize = 0;
    while (i < words32.len) : (i += 16) {
        const h0 = a;
        const h1 = b;
        const h2 = c;
        const h3 = d;
        const h4 = e;

        var j: usize = 0;
        while (j < 80) : (j += 1) {
            if (j < 16) {
                w[j] = words32[i + j];
            } else {
                w[j] = rol32(w[j - 3] ^ w[j - 8] ^ w[j - 14] ^ w[j - 16], 1);
            }

            const fk_val = fk(@intCast(j), b, c, d);
            const f = fk_val[0];
            const k = fk_val[1];
            const temp = add32(add32(add32(rol32(a, 5), f), e), k) +% w[j];
            e = d;
            d = c;
            c = rol32(b, 30);
            b = a;
            a = temp;
        }
        a = add32(a, h0);
        b = add32(b, h1);
        c = add32(c, h2);
        d = add32(d, h3);
        e = add32(e, h4);
    }

    // Convert to hex string — direct port of:
    //   toHexU32(a) + toHexU32(b) + toHexU32(c) + toHexU32(d) + toHexU32(e)
    var hex_buf: [40]u8 = undefined;
    writeHexU32(&hex_buf, 0, a);
    writeHexU32(&hex_buf, 8, b);
    writeHexU32(&hex_buf, 16, c);
    writeHexU32(&hex_buf, 24, d);
    writeHexU32(&hex_buf, 32, e);
    return allocator.dupe(u8, &hex_buf);
}

/// Write a u32 as 8 lowercase hex chars into buf at offset.
/// Direct port of `toHexU32(value)` in the TS source.
fn writeHexU32(buf: *[40]u8, offset: usize, value: u32) void {
    const hex_chars = "0123456789abcdef";
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        const shift: u5 = @intCast(28 - 4 * i);
        const nibble = (value >> shift) & 0x0F;
        buf[offset + i] = hex_chars[nibble];
    }
}

/// fk function — direct port of `fk(index, b, c, d)` in the TS source.
fn fk(index: u32, b: u32, c: u32, d: u32) [2]u32 {
    if (index < 20) {
        return .{ (b & c) | (~b & d), 0x5a827999 };
    }
    if (index < 40) {
        return .{ b ^ c ^ d, 0x6ed9eba1 };
    }
    if (index < 60) {
        return .{ (b & c) | (b & d) | (c & d), 0x8f1bbcdc };
    }
    return .{ b ^ c ^ d, 0xca62c1d6 };
}

/// Add two u32 with wraparound — direct port of `add32(a, b)`.
fn add32(a: u32, b: u32) u32 {
    return a +% b;
}

/// Rotate a 32-bit number left by `count` positions.
/// Direct port of `rol32(a, count)` in the TS source.
fn rol32(a: u32, count: u5) u32 {
    return std.math.rotl(u32, a, count);
}

// ─── bytesToWords32 ──────────────────────────────────────────

const Endian = enum { Little, Big };

/// Convert bytes to an array of 32-bit words.
/// Direct port of `bytesToWords32(bytes, endian)` in the TS source.
fn bytesToWords32(allocator: Allocator, bytes: []const u8, endian: Endian) ![]u32 {
    const size = (bytes.len + 3) >> 2;
    const words32 = try allocator.alloc(u32, size);
    @memset(words32, 0);
    for (words32, 0..) |*word, i| {
        word.* = wordAt(bytes, @intCast(i * 4), endian);
    }
    return words32;
}

/// Get a byte at index, returning 0 if out of bounds.
/// Direct port of `byteAt(bytes, index)` in the TS source.
fn byteAt(bytes: []const u8, index: usize) u8 {
    if (index >= bytes.len) return 0;
    return bytes[index];
}

/// Get a 32-bit word at the given byte offset.
/// Direct port of `wordAt(bytes, index, endian)` in the TS source.
fn wordAt(bytes: []const u8, index: usize, endian: Endian) u32 {
    var word: u32 = 0;
    switch (endian) {
        .Big => {
            var i: usize = 0;
            while (i < 4) : (i += 1) {
                word +%= @as(u32, byteAt(bytes, index + i)) << @intCast(24 - 8 * i);
            }
        },
        .Little => {
            var i: usize = 0;
            while (i < 4) : (i += 1) {
                word +%= @as(u32, byteAt(bytes, index + i)) << @intCast(8 * i);
            }
        },
    }
    return word;
}

// ─── fingerprint / computeMsgId ──────────────────────────────

/// Compute the fingerprint of the given string.
/// Direct port of `fingerprint(str)` in the TS source.
///
/// The output is a 64-bit number (returned as a struct with hi/lo u32 parts).
/// Based on Google's closure-compiler GoogleJsMessageIdGenerator.
pub fn fingerprint(str: []const u8) [2]u32 {
    const utf8 = str;

    var hi = hash32(utf8, utf8.len, 0);
    var lo = hash32(utf8, utf8.len, 102072);

    if (hi == 0 and (lo == 0 or lo == 1)) {
        hi = hi ^ 0x130f9bef;
        lo = lo ^ 0x9_4a0_a928; // -0x6b5f56d8 as u32
    }

    return .{ hi, lo };
}

/// Compute a message ID from a serialized string + meaning.
/// Direct port of `computeMsgId(msg, meaning)` in the TS source.
pub fn computeMsgId(allocator: Allocator, msg: []const u8, meaning: []const u8) ![]const u8 {
    var msg_fp = fingerprint(msg);

    if (meaning.len > 0) {
        // Rotate the 64-bit message fingerprint one bit to the left
        // and then add the meaning fingerprint.
        const hi = msg_fp[0];
        const lo = msg_fp[1];
        // 64-bit rotate left by 1: (hi:lo << 1) | (top bit of hi → bit 0 of lo)
        const new_top = (hi << 1) | (lo >> 31);
        const new_bot = (lo << 1) | (hi >> 31);
        msg_fp[0] = new_top;
        msg_fp[1] = new_bot;

        // Add the meaning fingerprint (64-bit addition with carry)
        const meaning_fp = fingerprint(meaning);
        const sum_bot: u64 = @as(u64, msg_fp[1]) + @as(u64, meaning_fp[1]);
        var sum_top: u64 = @as(u64, msg_fp[0]) + @as(u64, meaning_fp[0]);
        if (sum_bot > 0xFFFFFFFF) sum_top += 1;
        msg_fp[0] = @truncate(sum_top);
        msg_fp[1] = @truncate(sum_bot);
    }

    // BigInt.asUintN(63, msgFingerprint).toString()
    // Take the low 63 bits (clear the top bit of hi) and convert to decimal.
    const hi_63 = msg_fp[0] & 0x7FFFFFFF;
    return u64ToDecimal(allocator, hi_63, msg_fp[1]);
}

/// Convert a 64-bit (63-bit used) number to a decimal string.
fn u64ToDecimal(allocator: Allocator, hi: u32, lo: u32) ![]const u8 {
    // Use u128 for the conversion to handle 64-bit values.
    var value: u128 = (@as(u128, hi) << 32) | @as(u128, lo);

    if (value == 0) {
        return allocator.dupe(u8, "0");
    }

    var digits: [24]u8 = undefined;
    var digit_len: usize = 0;
    while (value > 0) {
        digits[digit_len] = '0' + @as(u8, @intCast(value % 10));
        value /= 10;
        digit_len += 1;
    }

    // Reverse the digits
    const result = try allocator.alloc(u8, digit_len);
    for (0..digit_len) |i| {
        result[i] = digits[digit_len - 1 - i];
    }
    return result;
}

// ─── hash32 ──────────────────────────────────────────────────

/// Compute a 32-bit hash of the given bytes.
/// Direct port of `hash32(view, length, c)` in the TS source.
fn hash32(bytes: []const u8, length: usize, c_in: u32) u32 {
    var a: u32 = 0x9e3779b9;
    var b: u32 = 0x9e3779b9;
    var c: u32 = c_in;
    var index: usize = 0;

    // Direct port: `const end = length - 12; for (; index <= end; index += 12)`
    // In TS, if length < 12, end is negative and the loop doesn't execute.
    // In Zig, we use signed arithmetic to match.
    const end_signed: isize = @as(isize, @intCast(length)) - 12;
    while (end_signed >= 0 and index <= @as(usize, @intCast(end_signed))) : (index += 12) {
        a +%= getUint32LE(bytes, index);
        b +%= getUint32LE(bytes, index + 4);
        c +%= getUint32LE(bytes, index + 8);
        const res = mix(a, b, c);
        a = res[0];
        b = res[1];
        c = res[2];
    }

    const remainder = length - index;
    c +%= @intCast(length);

    if (remainder >= 4) {
        a +%= getUint32LE(bytes, index);
        index += 4;

        if (remainder >= 8) {
            b +%= getUint32LE(bytes, index);
            index += 4;

            // Partial 32-bit word for c
            if (remainder >= 9) {
                c +%= @as(u32, byteAt(bytes, index)) << 8;
                index += 1;
            }
            if (remainder >= 10) {
                c +%= @as(u32, byteAt(bytes, index)) << 16;
                index += 1;
            }
            if (remainder == 11) {
                c +%= @as(u32, byteAt(bytes, index)) << 24;
                index += 1;
            }
        } else {
            // Partial 32-bit word for b
            if (remainder >= 5) {
                b +%= byteAt(bytes, index);
                index += 1;
            }
            if (remainder >= 6) {
                b +%= @as(u32, byteAt(bytes, index)) << 8;
                index += 1;
            }
            if (remainder == 7) {
                b +%= @as(u32, byteAt(bytes, index)) << 16;
                index += 1;
            }
        }
    } else {
        // Partial 32-bit word for a
        if (remainder >= 1) {
            a +%= byteAt(bytes, index);
            index += 1;
        }
        if (remainder >= 2) {
            a +%= @as(u32, byteAt(bytes, index)) << 8;
            index += 1;
        }
        if (remainder == 3) {
            a +%= @as(u32, byteAt(bytes, index)) << 16;
            index += 1;
        }
    }

    return mix(a, b, c)[2];
}

/// Get a 32-bit little-endian value from bytes at the given offset.
fn getUint32LE(bytes: []const u8, offset: usize) u32 {
    if (offset + 4 > bytes.len) {
        // Handle partial reads like the DataView would (but DataView throws).
        // The TS code assumes the data fits; we'll return 0 for out-of-bounds.
        var result: u32 = 0;
        var i: usize = 0;
        while (i < 4 and offset + i < bytes.len) : (i += 1) {
            result +%= @as(u32, bytes[offset + i]) << @intCast(8 * i);
        }
        return result;
    }
    return @as(u32, bytes[offset]) |
        (@as(u32, bytes[offset + 1]) << 8) |
        (@as(u32, bytes[offset + 2]) << 16) |
        (@as(u32, bytes[offset + 3]) << 24);
}

/// mix function — direct port of `mix(a, b, c)` in the TS source.
fn mix(a_in: u32, b_in: u32, c_in: u32) [3]u32 {
    var a = a_in;
    var b = b_in;
    var c = c_in;

    a -%= b;
    a -%= c;
    a ^= c >> 13;
    b -%= c;
    b -%= a;
    b ^= a << 8;
    c -%= a;
    c -%= b;
    c ^= b >> 13;
    a -%= b;
    a -%= c;
    a ^= c >> 12;
    b -%= c;
    b -%= a;
    b ^= a << 16;
    c -%= a;
    c -%= b;
    c ^= b >> 5;
    a -%= b;
    a -%= c;
    a ^= c >> 3;
    b -%= c;
    b -%= a;
    b ^= a << 10;
    c -%= a;
    c -%= b;
    c ^= b >> 15;

    return .{ a, b, c };
}

// ─── Tests ──────────────────────────────────────────────────

test "digest returns existing ID" {
    var msg = i18n_ast.Message.init(std.testing.allocator);
    defer msg.deinit();
    msg.id = "existing-id";
    const result = digest(&msg);
    try std.testing.expectEqualStrings("existing-id", result);
}

test "digest returns empty for no ID" {
    var msg = i18n_ast.Message.init(std.testing.allocator);
    defer msg.deinit();
    msg.id = "";
    const result = digest(&msg);
    try std.testing.expectEqualStrings("", result);
}

test "computeDigest produces 40-char hex string" {
    const allocator = std.testing.allocator;
    var msg = i18n_ast.Message.init(allocator);
    defer msg.deinit();
    msg.id = "";
    msg.meaning = "test";
    msg.nodes = &.{};
    const result = try computeDigest(allocator, &msg);
    defer allocator.free(result);
    // SHA1 produces 20 bytes = 40 hex chars
    try std.testing.expectEqual(@as(usize, 40), result.len);
}

test "computeDigest is deterministic" {
    const allocator = std.testing.allocator;
    var msg1 = i18n_ast.Message.init(allocator);
    defer msg1.deinit();
    msg1.id = "";
    msg1.meaning = "test";
    msg1.nodes = &.{};
    const result1 = try computeDigest(allocator, &msg1);
    defer allocator.free(result1);

    var msg2 = i18n_ast.Message.init(allocator);
    defer msg2.deinit();
    msg2.id = "";
    msg2.meaning = "test";
    msg2.nodes = &.{};
    const result2 = try computeDigest(allocator, &msg2);
    defer allocator.free(result2);

    try std.testing.expectEqualStrings(result1, result2);
}

test "computeDigest differs for different meanings" {
    const allocator = std.testing.allocator;
    var msg1 = i18n_ast.Message.init(allocator);
    defer msg1.deinit();
    msg1.id = "";
    msg1.meaning = "greeting";
    msg1.nodes = &.{};
    const result1 = try computeDigest(allocator, &msg1);
    defer allocator.free(result1);

    var msg2 = i18n_ast.Message.init(allocator);
    defer msg2.deinit();
    msg2.id = "";
    msg2.meaning = "farewell";
    msg2.nodes = &.{};
    const result2 = try computeDigest(allocator, &msg2);
    defer allocator.free(result2);

    try std.testing.expect(!std.mem.eql(u8, result1, result2));
}

test "decimalDigest returns existing ID" {
    var msg = i18n_ast.Message.init(std.testing.allocator);
    defer msg.deinit();
    msg.id = "existing-id";
    const result = decimalDigest(&msg);
    try std.testing.expectEqualStrings("existing-id", result);
}

test "computeMsgId produces decimal string" {
    const allocator = std.testing.allocator;
    const result = try computeMsgId(allocator, "Hello World", "");
    defer allocator.free(result);
    // Should be all digits
    for (result) |ch| {
        try std.testing.expect(ch >= '0' and ch <= '9');
    }
}

test "computeMsgId is deterministic" {
    const allocator = std.testing.allocator;
    const result1 = try computeMsgId(allocator, "test", "meaning");
    defer allocator.free(result1);
    const result2 = try computeMsgId(allocator, "test", "meaning");
    defer allocator.free(result2);
    try std.testing.expectEqualStrings(result1, result2);
}

test "computeMsgId differs for different inputs" {
    const allocator = std.testing.allocator;
    const result1 = try computeMsgId(allocator, "Hello", "");
    defer allocator.free(result1);
    const result2 = try computeMsgId(allocator, "World", "");
    defer allocator.free(result2);
    try std.testing.expect(!std.mem.eql(u8, result1, result2));
}

test "computeMsgId differs for different meanings" {
    const allocator = std.testing.allocator;
    const result1 = try computeMsgId(allocator, "Hello", "greeting");
    defer allocator.free(result1);
    const result2 = try computeMsgId(allocator, "Hello", "farewell");
    defer allocator.free(result2);
    try std.testing.expect(!std.mem.eql(u8, result1, result2));
}

test "fingerprint is deterministic" {
    const fp1 = fingerprint("Hello World");
    const fp2 = fingerprint("Hello World");
    try std.testing.expectEqual(fp1[0], fp2[0]);
    try std.testing.expectEqual(fp1[1], fp2[1]);
}

test "fingerprint differs for different inputs" {
    const fp1 = fingerprint("Hello");
    const fp2 = fingerprint("World");
    try std.testing.expect(fp1[0] != fp2[0] or fp1[1] != fp2[1]);
}

test "hash32 is deterministic" {
    const h1 = hash32("test input", 10, 0);
    const h2 = hash32("test input", 10, 0);
    try std.testing.expectEqual(h1, h2);
}

test "mix returns 3 values" {
    const result = mix(0x9e3779b9, 0x9e3779b9, 0);
    try std.testing.expectEqual(@as(usize, 3), result.len);
}

test "rol32 rotates bits" {
    // rol32(1, 1) = 2
    try std.testing.expectEqual(@as(u32, 2), rol32(1, 1));
    // rol32(0x80000000, 1) = 1 (top bit wraps to bottom)
    try std.testing.expectEqual(@as(u32, 1), rol32(0x80000000, 1));
}

test "add32 wraps on overflow" {
    const result = add32(0xFFFFFFFF, 1);
    try std.testing.expectEqual(@as(u32, 0), result);
}

test "bytesToWords32 — empty" {
    const allocator = std.testing.allocator;
    const words = try bytesToWords32(allocator, "", .Big);
    defer allocator.free(words);
    try std.testing.expectEqual(@as(usize, 0), words.len);
}

test "bytesToWords32 — 4 bytes big endian" {
    const allocator = std.testing.allocator;
    const bytes = [_]u8{ 0x01, 0x02, 0x03, 0x04 };
    const words = try bytesToWords32(allocator, &bytes, .Big);
    defer allocator.free(words);
    try std.testing.expectEqual(@as(usize, 1), words.len);
    try std.testing.expectEqual(@as(u32, 0x01020304), words[0]);
}

test "bytesToWords32 — 4 bytes little endian" {
    const allocator = std.testing.allocator;
    const bytes = [_]u8{ 0x01, 0x02, 0x03, 0x04 };
    const words = try bytesToWords32(allocator, &bytes, .Little);
    defer allocator.free(words);
    try std.testing.expectEqual(@as(usize, 1), words.len);
    try std.testing.expectEqual(@as(u32, 0x04030201), words[0]);
}

test "byteAt returns 0 for out of bounds" {
    const bytes = [_]u8{ 1, 2 };
    try std.testing.expectEqual(@as(u8, 0), byteAt(&bytes, 5));
}

test "wordAt — big endian" {
    const bytes = [_]u8{ 0xAA, 0xBB, 0xCC, 0xDD };
    const result = wordAt(&bytes, 0, .Big);
    try std.testing.expectEqual(@as(u32, 0xAABBCCDD), result);
}

test "wordAt — little endian" {
    const bytes = [_]u8{ 0xAA, 0xBB, 0xCC, 0xDD };
    const result = wordAt(&bytes, 0, .Little);
    try std.testing.expectEqual(@as(u32, 0xDDCCBBAA), result);
}

test "u64ToDecimal — zero" {
    const allocator = std.testing.allocator;
    const result = try u64ToDecimal(allocator, 0, 0);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("0", result);
}

test "u64ToDecimal — small number" {
    const allocator = std.testing.allocator;
    const result = try u64ToDecimal(allocator, 0, 42);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("42", result);
}

test "u64ToDecimal — large 64-bit number" {
    const allocator = std.testing.allocator;
    // 0xFFFFFFFFFFFFFFFF = 18446744073709551615
    const result = try u64ToDecimal(allocator, 0xFFFFFFFF, 0xFFFFFFFF);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("18446744073709551615", result);
}

test "sha1 of empty string" {
    const allocator = std.testing.allocator;
    const result = try sha1(allocator, "");
    defer allocator.free(result);
    // SHA1("") = da39a3ee5e6b4b0d3255bfef95601890afd80709
    try std.testing.expectEqual(@as(usize, 40), result.len);
}

test "sha1 of 'abc'" {
    const allocator = std.testing.allocator;
    const result = try sha1(allocator, "abc");
    defer allocator.free(result);
    // SHA1("abc") = a9993e364706816aba3e25717850c26c9cd0d89d
    try std.testing.expectEqual(@as(usize, 40), result.len);
}

test "sha1 is deterministic" {
    const allocator = std.testing.allocator;
    const r1 = try sha1(allocator, "test");
    defer allocator.free(r1);
    const r2 = try sha1(allocator, "test");
    defer allocator.free(r2);
    try std.testing.expectEqualStrings(r1, r2);
}

test "sha1 differs for different inputs" {
    const allocator = std.testing.allocator;
    const r1 = try sha1(allocator, "hello");
    defer allocator.free(r1);
    const r2 = try sha1(allocator, "world");
    defer allocator.free(r2);
    try std.testing.expect(!std.mem.eql(u8, r1, r2));
}

test "computeMsgId — empty meaning" {
    const allocator = std.testing.allocator;
    const r1 = try computeMsgId(allocator, "test", "");
    defer allocator.free(r1);
    const r2 = try computeMsgId(allocator, "test", "");
    defer allocator.free(r2);
    try std.testing.expectEqualStrings(r1, r2);
}
