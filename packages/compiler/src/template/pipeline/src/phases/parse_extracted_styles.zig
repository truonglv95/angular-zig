/// parse_extracted_styles phase
///
/// Port of: template/pipeline/src/phases/parse_extracted_styles.ts (190 LoC)
///
/// Create phase — Parses extracted style and class attributes into separate
/// ExtractedAttributeOps per style or class property.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

const source_span = @import("../../../../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

/// Character codes for the style parser.
const Char = enum(u8) {
    OpenParen = 40,
    CloseParen = 41,
    Colon = 58,
    Semicolon = 59,
    BackSlash = 92,
    QuoteNone = 0,
    QuoteDouble = 34,
    QuoteSingle = 39,
};

/// Parse a style string into an array of [prop, value, prop, value, ...].
/// Direct port of `parse(value)` in the TS source.
pub fn parse(allocator: std.mem.Allocator, value: []const u8) ![][]const u8 {
    var styles = std.array_list.Managed([]const u8).init(allocator);
    errdefer styles.deinit();

    var i: usize = 0;
    var paren_depth: i32 = 0;
    var quote: Char = .QuoteNone;
    var value_start: usize = 0;
    var prop_start: usize = 0;
    var current_prop: ?[]const u8 = null;

    while (i < value.len) {
        const ch = value[i];
        i += 1;
        // Match against the character codes directly (avoids @enumFromInt crash
        // on chars not in the Char enum).
        if (ch == @intFromEnum(Char.OpenParen)) {
            paren_depth += 1;
        } else if (ch == @intFromEnum(Char.CloseParen)) {
            paren_depth -= 1;
        } else if (ch == @intFromEnum(Char.QuoteSingle)) {
            if (quote == .QuoteNone) {
                quote = .QuoteSingle;
            } else if (quote == .QuoteSingle and i > 0 and value[i - 1] != @intFromEnum(Char.BackSlash)) {
                quote = .QuoteNone;
            }
        } else if (ch == @intFromEnum(Char.QuoteDouble)) {
            if (quote == .QuoteNone) {
                quote = .QuoteDouble;
            } else if (quote == .QuoteDouble and i > 0 and value[i - 1] != @intFromEnum(Char.BackSlash)) {
                quote = .QuoteNone;
            }
        } else if (ch == @intFromEnum(Char.Colon)) {
            if (current_prop == null and paren_depth == 0 and quote == .QuoteNone) {
                const prop = std.mem.trim(u8, value[prop_start .. i - 1], " \t");
                current_prop = try hyphenate(allocator, prop);
                value_start = i;
            }
        } else if (ch == @intFromEnum(Char.Semicolon)) {
            if (current_prop != null and value_start > 0 and paren_depth == 0 and quote == .QuoteNone) {
                const style_val = std.mem.trim(u8, value[value_start .. i - 1], " \t");
                try styles.append(current_prop.?);
                try styles.append(style_val);
                prop_start = i;
                value_start = 0;
                current_prop = null;
            }
        }
    }

    if (current_prop != null and value_start > 0) {
        const style_val = std.mem.trim(u8, value[value_start..], " \t");
        try styles.append(current_prop.?);
        try styles.append(style_val);
    }

    return styles.toOwnedSlice();
}

/// Free a result from `parse`. Frees the array AND all property name
/// strings (at even indices — allocated by `hyphenate`). Value strings
/// (at odd indices) are zero-copy slices of the input and are NOT freed.
pub fn freeResult(allocator: std.mem.Allocator, result: []const []const u8) void {
    // Free property names (even indices).
    var idx: usize = 0;
    while (idx < result.len) : (idx += 2) {
        if (result[idx].len > 0) allocator.free(result[idx]);
    }
    // Cast to mutable for free (the allocator needs []T, not []const T).
    allocator.free(@constCast(result));
}

/// Hyphenate a camelCase string (e.g., "marginLeft" → "margin-left").
/// Direct port of `hyphenate(value)` in the TS source.
pub fn hyphenate(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    errdefer result.deinit();

    for (value, 0..) |c, idx| {
        if (idx > 0 and c >= 'A' and c <= 'Z') {
            // Check if previous char is lowercase.
            const prev = value[idx - 1];
            if (prev >= 'a' and prev <= 'z') {
                try result.append('-');
            }
        }
        // Lowercase the char.
        const lower = if (c >= 'A' and c <= 'Z') c + 32 else c;
        try result.append(lower);
    }

    return result.toOwnedSlice();
}

/// Parse extracted style and class attributes into separate ops.
/// Direct port of `parseExtractedStyles(job)` in the TS source.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    // Build new create list with parsed styles/classes.
    var new_create = std.array_list.Managed(IrOp).init(view.create.ops.allocator);
    defer new_create.deinit();

    for (view.create.ops.items) |op| {
        if (op.kind == .Attribute) {
            const attr = op.data.Attribute;
            if (std.mem.eql(u8, attr.name, "style")) {
                // Parse the style value into individual properties.
                const parsed = parse(view.create.ops.allocator, attr.value) catch {
                    try new_create.append(op);
                    continue;
                };
                defer view.create.ops.allocator.free(parsed);

                // For each [prop, value] pair, create an Attribute op.
                var i: usize = 0;
                while (i + 1 < parsed.len) : (i += 2) {
                    const style_op = IrOp{
                        .kind = .Attribute,
                        .xref = op.xref,
                        .source_span = op.source_span,
                        .data = .{
                            .Attribute = .{
                                .name = parsed[i],
                                .value = parsed[i + 1],
                                .security_context = 2, // SecurityContext.STYLE
                            },
                        },
                    };
                    try new_create.append(style_op);
                }
                // Skip the original style op (it's been expanded).
                continue;
            } else if (std.mem.eql(u8, attr.name, "class")) {
                // Parse the class value into individual classes.
                var iter = std.mem.tokenizeAny(u8, attr.value, " \t\n\r");
                while (iter.next()) |class_name| {
                    const class_op = IrOp{
                        .kind = .Attribute,
                        .xref = op.xref,
                        .source_span = op.source_span,
                        .data = .{
                            .Attribute = .{
                                .name = class_name,
                                .value = "",
                                .security_context = 0, // SecurityContext.NONE
                            },
                        },
                    };
                    try new_create.append(class_op);
                }
                // Skip the original class op.
                continue;
            }
        }
        try new_create.append(op);
    }

    // Replace create ops.
    view.create.ops.clearRetainingCapacity();
    for (new_create.items) |op| {
        try view.create.ops.append(op);
    }
}

/// Public API matching TS export name.
pub fn parseExtractedStyles(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    return run(job, view);
}

// ─── Tests ──────────────────────────────────────────────────

test "parse simple style" {
    const allocator = std.testing.allocator;
    const result = try parse(allocator, "color: red; height: auto");
    defer {
        // Only free the hyphenated property names (index 0, 2, ...).
        // Values (index 1, 3, ...) are slices of the input string, not heap-allocated.
        var i: usize = 0;
        while (i < result.len) : (i += 2) {
            allocator.free(result[i]);
        }
        allocator.free(result);
    }
    try std.testing.expectEqual(@as(usize, 4), result.len);
    try std.testing.expectEqualStrings("color", result[0]);
    try std.testing.expectEqualStrings("red", result[1]);
    try std.testing.expectEqualStrings("height", result[2]);
    try std.testing.expectEqualStrings("auto", result[3]);
}

test "hyphenate camelCase" {
    const allocator = std.testing.allocator;
    const r1 = try hyphenate(allocator, "marginLeft");
    defer allocator.free(r1);
    try std.testing.expectEqualStrings("margin-left", r1);

    const r2 = try hyphenate(allocator, "color");
    defer allocator.free(r2);
    try std.testing.expectEqualStrings("color", r2);
}

test "run is a no-op on view without style/class ops" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "Test", .Full);
    defer job.deinit();
    var view = ViewCompilationUnit.init(allocator, 0, null);
    defer view.deinit();

    try run(&job, &view);
    try std.testing.expectEqual(@as(usize, 0), view.create.ops.items.len);
}
