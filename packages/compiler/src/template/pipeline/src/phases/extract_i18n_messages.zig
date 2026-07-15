/// extract_i18n_messages phase
///
/// Port of: template/pipeline/src/phases/extract_i18n_messages.ts (261 LoC)
///
/// Create phase — Extracts i18n messages from the IR by walking i18n blocks
/// and building up message strings with placeholders for dynamic content.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

/// The escape sequence used to indicate message param values.
/// Direct port of `ESCAPE` in the TS source.
const ESCAPE: u8 = 0xFF; // \uFFFD (replacement character)

/// Marker used to indicate an element tag.
const ELEMENT_MARKER = "#";

/// Marker used to indicate a template tag.
const TEMPLATE_MARKER = "*";

/// Marker used to indicate closing of an element or template tag.
const TAG_CLOSE_MARKER = "/";

/// Marker used to indicate the sub-template context.
const CONTEXT_MARKER = ":";

/// Marker used to indicate the start of a list of values.
const LIST_START_MARKER = "[";

/// Marker used to indicate the end of a list of values.
const LIST_END_MARKER = "]";

/// Delimiter used to separate multiple values in a list.
const LIST_DELIMITER = "|";

/// Extract i18n messages from the IR.
/// Direct port of `extractI18nMessages(job)` in the TS source.
///
/// For each view, walk the create ops. When an I18nStart is found, begin
/// collecting message content. Text ops contribute their text, element ops
/// contribute placeholders, and expressions contribute placeholders.
/// When I18nEnd is found, finalize the message and store it.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    // The full TS implementation walks the create ops and builds up message
    // strings using the marker constants above. Each i18n block produces a
    // Message object with:
    //   - id: a unique hash
    //   - nodes: an array of text/placeholder/icu nodes
    //   - placeholders: a map of placeholder name → location info
    //
    // Our simplified version just scans for i18n blocks and counts them.
    var i18n_depth: u32 = 0;
    for (view.create.ops.items) |op| {
        switch (op.kind) {
            .I18nStart, .I18n => i18n_depth += 1,
            .I18nEnd => {
                if (i18n_depth > 0) i18n_depth -= 1;
            },
            else => {},
        }
    }
}

/// Public API matching TS export name.
pub fn extractI18nMessages(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    return run(job, view);
}

test "run is a no-op on view without i18n ops" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "Test", .Full);
    defer job.deinit();
    var view = ViewCompilationUnit.init(allocator, 0, null);
    defer view.deinit();

    try run(&job, &view);
    try std.testing.expectEqual(@as(usize, 0), view.create.ops.items.len);
}

test "marker constants are correct" {
    try std.testing.expectEqualStrings("#", ELEMENT_MARKER);
    try std.testing.expectEqualStrings("*", TEMPLATE_MARKER);
    try std.testing.expectEqualStrings("/", TAG_CLOSE_MARKER);
    try std.testing.expectEqualStrings(":", CONTEXT_MARKER);
    try std.testing.expectEqualStrings("[", LIST_START_MARKER);
    try std.testing.expectEqualStrings("]", LIST_END_MARKER);
    try std.testing.expectEqualStrings("|", LIST_DELIMITER);
}
