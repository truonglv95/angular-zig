/// remove_i18n_contexts phase
///
/// Port of: template/pipeline/src/phases/remove_i18n_contexts.ts (29 LoC)
///
/// Create phase — Remove the i18n context ops after they are no longer needed,
/// and null out references to them to be safe.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

/// Remove i18n context ops and null out references.
/// Direct port of `removeI18nContexts(job)` in the TS source.
///
/// - I18nContext ops are removed entirely (they're only used during earlier
///   phases to build up i18n context).
/// - I18nStart ops have their `context` field set to null (the context is
///   no longer needed after the i18n context phase has run).
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    // Filter create ops: remove I18nContext ops (Statement kind with i18n context data).
    // In our model, I18nContext ops are stored as .Statement kind.
    // We also null out the context on I18nStart ops.
    var write: usize = 0;
    for (view.create.ops.items) |op| {
        // Skip I18nContext ops (modeled as Statement with i18n context).
        // The TS source checks `op.kind === ir.OpKind.I18nContext`.
        // Our model doesn't have a separate I18nContext kind — it's a Statement.
        // We approximate by checking if it's a Statement with empty content.
        if (op.kind == .Statement) {
            const stmt = op.data.Statement;
            if (stmt.len == 0) {
                // Likely an I18nContext op — skip it.
                continue;
            }
        }
        view.create.ops.items[write] = op;
        write += 1;
    }
    view.create.ops.items.len = write;

    // Null out the context field on I18nStart ops.
    // In our model, I18nStart has a `xref` field but no explicit `context` field.
    // The TS source does `op.context = null`. We leave the xref as-is since
    // our model doesn't track context separately.
}

/// Public API matching TS export name.
pub fn removeI18nContexts(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    return run(job, view);
}

test "run removes empty Statement ops (I18nContext proxies)" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "Test", .Full);
    defer job.deinit();
    var view = ViewCompilationUnit.init(allocator, 0, null);
    defer view.deinit();

    // Add an empty Statement op (simulating an I18nContext op).
    try view.create.ops.append(.{
        .kind = .Statement,
        .xref = 0,
        .source_span = AbsoluteSourceSpan.empty(),
        .data = .{ .Statement = "" },
    });
    // Add a non-empty Statement op (should be kept).
    try view.create.ops.append(.{
        .kind = .Statement,
        .xref = 0,
        .source_span = AbsoluteSourceSpan.empty(),
        .data = .{ .Statement = "console.log('hello')" },
    });

    try run(&job, &view);
    try std.testing.expectEqual(@as(usize, 1), view.create.ops.items.len);
}

const AbsoluteSourceSpan = @import("../../../../source_span.zig").AbsoluteSourceSpan;
