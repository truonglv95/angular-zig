/// i18n Pipeline — Internationalization Message Extraction & Processing
///
/// Handles Angular's i18n system:
///   - Message extraction from templates (i18n attributes, $localize calls)
///   - ICU message parsing (plural, select)
///   - Message serialization for translation files (XLIFF/ARB/XTB)
///   - Placeholder and meaning/description metadata
///
/// DOD optimizations:
///   - Zero-copy message extraction (slices into source text)
///   - Compact MessageId (u32 hash) for O(1) dedup
///   - Contiguous ArrayList for messages (cache-friendly iteration)
///   - comptime FNV-1a hash for message IDs
///   - Stack-based ICU expression parsing
const std = @import("std");
const Allocator = std.mem.Allocator;

const source_span = @import("../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

// ─── Message ID ──────────────────────────────────────────────
/// 32-bit FNV-1a hash used as message ID.
/// DOD: 4 bytes instead of heap-allocated string.
pub fn computeMessageId(content: []const u8) u32 {
    var hash: u32 = 2166136261; // FNV offset basis
    for (content) |byte| {
        hash ^= byte;
        hash *%= 16777619; // FNV prime
    }
    return hash;
}

// ─── i18n Message ────────────────────────────────────────────

pub const IcuType = enum(u8) {
    Plural,
    Select,
    SelectOrdinal,
};

pub const IcuCase = struct {
    value: []const u8,
    /// The content for this case (may contain interpolation)
    content: []const u8,
    source_span: AbsoluteSourceSpan,
};

pub const IcuExpression = struct {
    icu_type: IcuType,
    /// The variable being switched on (e.g., "items" in {items, plural, ...})
    selector: []const u8,
    cases: []const IcuCase,
    source_span: AbsoluteSourceSpan,
};

pub const Placeholder = struct {
    name: []const u8,
    /// The text that the placeholder replaces
    text: []const u8,
};

pub const I18nMessage = struct {
    /// The original source text (with {placeholders} and ICU expressions)
    source: []const u8,
    /// Computed message ID (FNV-1a hash)
    id: u32,
    /// Custom ID if provided via i18n="@myId|..."
    custom_id: ?[]const u8 = null,
    /// Meaning metadata (i18n="meaning|description")
    meaning: ?[]const u8 = null,
    /// Description metadata
    description: ?[]const u8 = null,
    /// Placeholders found in the message
    placeholders: []const Placeholder = &[_]Placeholder{},
    /// ICU sub-expressions
    icu_expressions: []const IcuExpression = &[_]IcuExpression{},
    /// Source location in the template
    source_span: AbsoluteSourceSpan,
};

// ─── i18n Extraction Result ──────────────────────────────────

pub const I18nExtractionResult = struct {
    messages: []const I18nMessage,
    /// Deduplicated message count
    unique_count: u32,
};

// ─── i18n Extractor ──────────────────────────────────────────

pub const I18nExtractor = struct {
    allocator: Allocator,
    /// All extracted messages (contiguous array)
    messages: std.array_list.Managed(I18nMessage),
    /// Message dedup set (by computed ID)
    seen_ids: std.AutoHashMap(u32, void),

    pub fn init(allocator: Allocator) I18nExtractor {
        return .{
            .allocator = allocator,
            .messages = std.array_list.Managed(I18nMessage).init(allocator),
            .seen_ids = std.AutoHashMap(u32, void).init(allocator),
        };
    }

    pub fn deinit(self: *I18nExtractor) void {
        self.messages.deinit();
        self.seen_ids.deinit();
    }

    /// Extract an i18n message from an element/attribute.
    /// Parses the i18n attribute value for meaning|description|customId.
    pub fn extractMessage(
        self: *I18nExtractor,
        source_text: []const u8,
        i18n_attr_value: ?[]const u8,
        span: AbsoluteSourceSpan,
    ) !?u32 {
        // Compute message ID from source text
        const id = computeMessageId(source_text);

        // Check dedup
        if (self.seen_ids.contains(id)) return null;
        try self.seen_ids.put(id, {});

        var msg = I18nMessage{
            .source = source_text,
            .id = id,
            .source_span = span,
        };

        // Parse i18n attribute metadata
        if (i18n_attr_value) |attr_val| {
            try self.parseI18nAttribute(attr_val, &msg);
        }

        // Extract placeholders from source text
        // Placeholders are in the form: {placeholderName}
        const placeholders = try self.extractPlaceholders(source_text);
        msg.placeholders = placeholders;

        // Extract ICU expressions from source text
        const icu_exprs = try self.extractIcuExpressions(source_text);
        msg.icu_expressions = icu_exprs;

        const index: u32 = @intCast(self.messages.items.len);
        try self.messages.append(msg);
        return index;
    }

    /// Parse i18n attribute value: "meaning|description|@@customId"
    /// Format:
    ///   - i18n="meaning" → meaning only
    ///   - i18n="meaning|description" → meaning + description
    ///   - i18n="@@customId" → custom ID
    ///   - i18n="meaning|description|@@customId" → all three
    fn parseI18nAttribute(_: *I18nExtractor, attr_val: []const u8, msg: *I18nMessage) !void {
        var parts = std.mem.splitSequence(u8, attr_val, "|");
        var part_idx: u32 = 0;

        while (parts.next()) |part| {
            if (part.len == 0) {
                part_idx += 1;
                continue;
            }

            // Check for custom ID: @@customId
            if (std.mem.startsWith(u8, part, "@@")) {
                msg.custom_id = part[2..];
            } else if (part_idx == 0 and msg.meaning == null) {
                msg.meaning = part;
            } else if (msg.description == null) {
                msg.description = part;
            }

            part_idx += 1;
        }
    }

    /// Extract {placeholder} references from source text.
    /// Returns a contiguous array of Placeholder structs.
    fn extractPlaceholders(self: *I18nExtractor, source: []const u8) ![]const Placeholder {
        var placeholders = std.array_list.Managed(Placeholder).initCapacity(self.allocator, 4) catch {
            return &[_]Placeholder{};
        };
        defer placeholders.deinit();

        var i: usize = 0;
        while (i < source.len) {
            if (source[i] == '{') {
                // Find matching }
                const end = std.mem.indexOfScalarPos(u8, source, i + 1, '}') orelse {
                    i += 1;
                    continue;
                };
                const content = source[i + 1 .. end];

                // Skip ICU expressions (they start with a type like "plural," or "select,")
                if (!isIcuStart(content)) {
                    try placeholders.append(.{
                        .name = content,
                        .text = source[i .. end + 1],
                    });
                }

                i = end + 1;
            } else {
                i += 1;
            }
        }

        return if (placeholders.items.len > 0)
            try placeholders.toOwnedSlice()
        else
            &[_]Placeholder{};
    }

    /// Extract ICU expressions from source text.
    /// Format: {selector, plural, one{...} other{...}}
    ///         {selector, select, caseA{...} caseB{...}}
    fn extractIcuExpressions(self: *I18nExtractor, source: []const u8) ![]const IcuExpression {
        var exprs = std.array_list.Managed(IcuExpression).initCapacity(self.allocator, 2) catch {
            return &[_]IcuExpression{};
        };
        defer exprs.deinit();

        var i: usize = 0;
        while (i < source.len) {
            if (source[i] == '{') {
                const end = findMatchingBrace(source, i);
                if (end == null) {
                    i += 1;
                    continue;
                }
                const e = end.?;
                const content = source[i + 1 .. e];

                if (isIcuStart(content)) {
                    if (try self.parseIcuExpression(content, source, i, e)) |icu| {
                        try exprs.append(icu);
                    }
                }

                i = e + 1;
            } else {
                i += 1;
            }
        }

        return if (exprs.items.len > 0)
            try exprs.toOwnedSlice()
        else
            &[_]IcuExpression{};
    }

    /// Parse a single ICU expression from its inner content (between outer braces).
    fn parseIcuExpression(
        self: *I18nExtractor,
        content: []const u8,
        full_source: []const u8,
        start: usize,
        end: usize,
    ) !?IcuExpression {
        // Format: "selector, plural, one{...} other{...}"
        // Split by comma (first two parts: selector and type)
        var comma_iter = std.mem.splitScalar(u8, content, ',');
        const selector = comma_iter.next() orelse return null;
        const type_str = std.mem.trim(u8, comma_iter.next() orelse return null, " ");

        const icu_type: IcuType = if (std.mem.eql(u8, type_str, "plural"))
            .Plural
        else if (std.mem.eql(u8, type_str, "select"))
            .Select
        else if (std.mem.eql(u8, type_str, "selectordinal"))
            .SelectOrdinal
        else
            return null;

        // Parse the remaining content for cases
        // Find the start of cases (after second comma)
        const second_comma = std.mem.indexOfScalarPos(u8, content, selector.len + 1 + type_str.len, ',') orelse return null;
        const cases_str = content[second_comma + 1 ..];

        var cases = std.array_list.Managed(IcuCase).initCapacity(self.allocator, 4) catch {
            return null;
        };
        defer cases.deinit();

        // Parse cases: "one{text} other{text}"
        var ci: usize = 0;
        while (ci < cases_str.len) {
            // Skip whitespace
            while (ci < cases_str.len and cases_str[ci] == ' ') ci += 1;
            if (ci >= cases_str.len) break;

            // Read case value (until '{')
            const brace_pos = std.mem.indexOfScalarPos(u8, cases_str, ci, '{') orelse break;
            const value = std.mem.trim(u8, cases_str[ci..brace_pos], " ");

            // Find matching '}'
            const case_end = findMatchingBrace(cases_str, brace_pos) orelse break;
            const case_content = cases_str[brace_pos + 1 .. case_end];

            try cases.append(.{
                .value = value,
                .content = case_content,
                .source_span = .{
                    .start = @intCast(start + (case_content.ptr - full_source.ptr)),
                    .end = @intCast(start + (case_content.ptr - full_source.ptr) + case_content.len),
                },
            });

            ci = case_end + 1;
        }

        return .{
            .icu_type = icu_type,
            .selector = std.mem.trim(u8, selector, " "),
            .cases = try cases.toOwnedSlice(),
            .source_span = .{
                .start = @intCast(start),
                .end = @intCast(end + 1),
            },
        };
    }

    /// Get all extracted messages
    pub fn getMessages(self: *const I18nExtractor) []const I18nMessage {
        return self.messages.items;
    }

    /// Get unique message count
    pub fn uniqueCount(self: *const I18nExtractor) u32 {
        return @intCast(self.seen_ids.count());
    }
};

// ─── i18n Serializer — Output Formats ────────────────────────

pub const I18nSerializer = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) I18nSerializer {
        return .{ .allocator = allocator };
    }

    /// Serialize messages to ARB format (Application Resource Bundle).
    /// Used by Angular's i18n system with @angular/localize.
    /// DOD: Single-pass string building into ArrayList.
    pub fn toArb(self: *I18nSerializer, messages: []const I18nMessage) ![]const u8 {
        var buf = std.array_list.Managed(u8).initCapacity(self.allocator, 1024) catch unreachable;

        try buf.appendSlice("{\n");

        // Header
        try buf.appendSlice("  \"@@locale\": \"en\",\n\n");

        for (messages, 0..) |msg, i| {
            const id_str = try std.fmt.allocPrint(self.allocator, "{d}", .{msg.id});
            defer self.allocator.free(id_str);

            try buf.appendSlice("  \"");
            try writeJsonString(&buf, if (msg.custom_id) |cid| cid else id_str);
            try buf.appendSlice("\": ");

            // Build description object
            try buf.appendSlice("{\"description\": \"");
            if (msg.description) |desc| {
                try writeJsonString(&buf, desc);
            } else if (msg.meaning) |meaning| {
                try writeJsonString(&buf, meaning);
            }
            try buf.appendSlice("\", \"message\": \"");
            try writeJsonString(&buf, msg.source);
            try buf.appendSlice("\"}");

            if (i < messages.len - 1) try buf.appendSlice(",");
            try buf.appendSlice("\n");
        }

        try buf.appendSlice("}\n");

        return buf.toOwnedSlice();
    }

    /// Serialize messages to XTB format (XML Translation Bundle).
    /// DOD: Single-pass, no DOM tree needed.
    pub fn toXtb(self: *I18nSerializer, messages: []const I18nMessage) ![]const u8 {
        var buf = std.array_list.Managed(u8).initCapacity(self.allocator, 1024) catch unreachable;

        try buf.appendSlice("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        try buf.appendSlice("<!DOCTYPE translationbundle [\n");
        try buf.appendSlice("  <!ELEMENT translationbundle (translation)*>\n");
        try buf.appendSlice("  <!ELEMENT translation (#PCDATA)>\n");
        try buf.appendSlice("  <!ATTLIST translation id CDATA #REQUIRED>\n");
        try buf.appendSlice("]>\n");
        try buf.appendSlice("<translationbundle>\n");

        for (messages) |msg| {
            const id_str = try std.fmt.allocPrint(self.allocator, "{d}", .{msg.id});
            defer self.allocator.free(id_str);

            try buf.appendSlice("  <translation id=\"");
            try writeJsonString(&buf, if (msg.custom_id) |cid| cid else id_str);
            try buf.appendSlice("\">");
            try writeXmlEscape(&buf, msg.source);
            try buf.appendSlice("</translation>\n");
        }

        try buf.appendSlice("</translationbundle>\n");

        return buf.toOwnedSlice();
    }
};

// ─── Helpers ──────────────────────────────────────────────────

/// Check if ICU expression content starts with a known ICU type.
fn isIcuStart(content: []const u8) bool {
    // ICU expressions: "varName, plural, ..." or "varName, select, ..."
    // Must have a comma followed by a type keyword
    const first_comma = std.mem.indexOfScalar(u8, content, ',') orelse return false;
    if (first_comma + 2 >= content.len) return false;

    const rest = content[first_comma + 1 ..];
    const trimmed = std.mem.trim(u8, rest, " ");

    return std.mem.startsWith(u8, trimmed, "plural,") or
        std.mem.startsWith(u8, trimmed, "select,") or
        std.mem.startsWith(u8, trimmed, "selectordinal,");
}

/// Find the matching closing brace for the opening brace at position `start`.
/// Handles nested braces.
fn findMatchingBrace(source: []const u8, start: usize) ?usize {
    if (start >= source.len or source[start] != '{') return null;

    var depth: i32 = 1;
    var i = start + 1;
    while (i < source.len) : (i += 1) {
        if (source[i] == '{') {
            depth += 1;
        } else if (source[i] == '}') {
            depth -= 1;
            if (depth == 0) return i;
        }
    }
    return null;
}

fn writeJsonString(buf: *std.array_list.Managed(u8), s: []const u8) !void {
    for (s) |ch| {
        switch (ch) {
            '\\' => try buf.appendSlice("\\\\"),
            '"' => try buf.appendSlice("\\\""),
            '\n' => try buf.appendSlice("\\n"),
            '\r' => try buf.appendSlice("\\r"),
            '\t' => try buf.appendSlice("\\t"),
            else => try buf.append(ch),
        }
    }
}

fn writeXmlEscape(buf: *std.array_list.Managed(u8), s: []const u8) !void {
    for (s) |ch| {
        switch (ch) {
            '&' => try buf.appendSlice("&amp;"),
            '<' => try buf.appendSlice("&lt;"),
            '>' => try buf.appendSlice("&gt;"),
            '"' => try buf.appendSlice("&quot;"),
            '\'' => try buf.appendSlice("&apos;"),
            else => try buf.append(ch),
        }
    }
}

// ─── Tests ────────────────────────────────────────────────────

test "computeMessageId — deterministic hash" {
    const id1 = computeMessageId("Hello World");
    const id2 = computeMessageId("Hello World");
    const id3 = computeMessageId("Different");
    try std.testing.expectEqual(id1, id2);
    try std.testing.expect(id1 != id3);
}

test "I18nExtractor — basic message extraction" {
    const allocator = std.testing.allocator;
    var ext = I18nExtractor.init(allocator);
    defer ext.deinit();

    const span = AbsoluteSourceSpan{ .start = 0, .end = 12 };

    const idx = try ext.extractMessage("Hello World", null, span);
    try std.testing.expect(idx != null);
    try std.testing.expectEqual(@as(usize, 1), ext.messages.items.len);
    try std.testing.expectEqualStrings("Hello World", ext.messages.items[0].source);
}

test "I18nExtractor — dedup" {
    const allocator = std.testing.allocator;
    var ext = I18nExtractor.init(allocator);
    defer ext.deinit();

    const span = AbsoluteSourceSpan{ .start = 0, .end = 5 };

    const idx1 = try ext.extractMessage("hello", null, span);
    const idx2 = try ext.extractMessage("hello", null, span); // duplicate

    try std.testing.expect(idx1 != null);
    try std.testing.expect(idx2 == null); // deduped
    try std.testing.expectEqual(@as(usize, 1), ext.messages.items.len);
}

test "I18nExtractor — i18n attribute parsing" {
    const allocator = std.testing.allocator;
    var ext = I18nExtractor.init(allocator);
    defer ext.deinit();

    const span = AbsoluteSourceSpan{ .start = 0, .end = 5 };

    // i18n="meaning|description"
    _ = try ext.extractMessage("Save", "meaning|description", span);
    const msg = ext.messages.items[0];
    try std.testing.expectEqualStrings("meaning", msg.meaning.?);
    try std.testing.expectEqualStrings("description", msg.description.?);
}

test "I18nExtractor — custom ID" {
    const allocator = std.testing.allocator;
    var ext = I18nExtractor.init(allocator);
    defer ext.deinit();

    const span = AbsoluteSourceSpan{ .start = 0, .end = 5 };

    // i18n="@@myCustomId"
    _ = try ext.extractMessage("Hello", "@@myCustomId", span);
    const msg = ext.messages.items[0];
    try std.testing.expectEqualStrings("myCustomId", msg.custom_id.?);
}

test "I18nExtractor — placeholder extraction" {
    const allocator = std.testing.allocator;
    var ext = I18nExtractor.init(allocator);
    defer ext.deinit();

    const span = AbsoluteSourceSpan{ .start = 0, .end = 20 };

    _ = try ext.extractMessage("Hello {name}, you have {count} messages", null, span);
    const msg = ext.messages.items[0];
    try std.testing.expectEqual(@as(usize, 2), msg.placeholders.len);
    try std.testing.expectEqualStrings("name", msg.placeholders[0].name);
    try std.testing.expectEqualStrings("count", msg.placeholders[1].name);
}

test "I18nExtractor — ICU expression extraction" {
    const allocator = std.testing.allocator;
    var ext = I18nExtractor.init(allocator);
    defer ext.deinit();

    const span = AbsoluteSourceSpan{ .start = 0, .end = 60 };

    const source = "{items, plural, =0{no items} =1{one item} other{many items}}";
    _ = try ext.extractMessage(source, null, span);
    const msg = ext.messages.items[0];
    try std.testing.expectEqual(@as(usize, 1), msg.icu_expressions.len);
    try std.testing.expectEqual(IcuType.Plural, msg.icu_expressions[0].icu_type);
    try std.testing.expectEqualStrings("items", msg.icu_expressions[0].selector);
    try std.testing.expectEqual(@as(usize, 3), msg.icu_expressions[0].cases.len); // =0, =1, other
}

test "I18nSerializer — ARB format" {
    const allocator = std.testing.allocator;
    var ext = I18nExtractor.init(allocator);
    defer ext.deinit();

    const span = AbsoluteSourceSpan{ .start = 0, .end = 5 };

    _ = try ext.extractMessage("Hello World", "greeting|A simple greeting", span);

    var serializer = I18nSerializer.init(allocator);
    const arb = try serializer.toArb(ext.getMessages());
    defer allocator.free(arb);

    try std.testing.expect(std.mem.indexOf(u8, arb, "\"@@locale\": \"en\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, arb, "\"description\": \"A simple greeting\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, arb, "\"message\": \"Hello World\"") != null);
}

test "I18nSerializer — XTB format" {
    const allocator = std.testing.allocator;
    var ext = I18nExtractor.init(allocator);
    defer ext.deinit();

    const span = AbsoluteSourceSpan{ .start = 0, .end = 5 };

    _ = try ext.extractMessage("Hello", null, span);

    var serializer = I18nSerializer.init(allocator);
    const xtb = try serializer.toXtb(ext.getMessages());
    defer allocator.free(xtb);

    try std.testing.expect(std.mem.indexOf(u8, xtb, "<?xml") != null);
    try std.testing.expect(std.mem.indexOf(u8, xtb, "<translationbundle>") != null);
    try std.testing.expect(std.mem.indexOf(u8, xtb, ">Hello<") != null);
}

test "findMatchingBrace — nested" {
    const src = "{a{b{c}d}e}";
    const result = findMatchingBrace(src, 0);
    try std.testing.expectEqual(@as(usize, 10), result.?);
}

test "isIcuStart — detection" {
    try std.testing.expect(isIcuStart("items, plural, one{...}"));
    try std.testing.expect(isIcuStart("x, select, a{...} b{...}"));
    try std.testing.expect(isIcuStart("x, selectordinal, one{...}"));
    try std.testing.expect(!isIcuStart("plain text"));
    try std.testing.expect(!isIcuStart("{not_icu}"));
}
