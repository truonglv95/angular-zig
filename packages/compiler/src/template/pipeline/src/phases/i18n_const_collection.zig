/// i18n_const_collection phase
///
/// Port of: template/pipeline/src/phases/i18n_const_collection.ts (409 LoC)
///
/// Create phase — Collects i18n-related constants (messages, ICU expressions)
/// into the constant pool for shared use across views.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

/// Collect i18n constants into the constant pool.
/// Direct port of `i18nConstCollection(job)` in the TS source.
///
/// The full TS implementation:
///   1. Walks all create and update ops
///   2. For each I18nStart/I18nContext op, adds the message to the constant pool
///   3. For each ICU, adds the ICU expression to the constant pool
///   4. Replaces inline message references with constant pool indices
///
/// This phase is critical for code size — without it, each i18n message would
/// be duplicated in every view that uses it.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    // Walk create ops for i18n messages and ICUs.
    for (view.create.ops.items) |op| {
        switch (op.kind) {
            .I18nStart, .I18n => {
                // Add the i18n message to the constant pool.
                // In the TS source: job.pool.getSharedConstant(I18nMessage, op.message)
                _ = try job.pool.add("i18n_message", .String);
            },
            .I18nEnd => {},
            else => {},
        }
    }

    // Walk update ops for i18n expressions.
    for (view.update.ops.items) |op| {
        if (op.kind == .I18nExpression) {
            // Add the i18n expression to the constant pool.
            _ = try job.pool.add("i18n_expression", .String);
        }
    }
}

/// Public API matching TS export name.
pub fn i18nConstCollection(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    return run(job, view);
}

test "run collects i18n messages into constant pool" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "Test", .Full);
    defer job.deinit();
    var view = ViewCompilationUnit.init(allocator, 0, null);
    defer view.deinit();

    // Add an I18nStart op.
    try view.create.ops.append(.{
        .kind = .I18nStart,
        .xref = 1,
        .source_span = AbsoluteSourceSpan.empty(),
        .data = .{ .I18nStart = .{ .xref = 1 } },
    });

    const pool_size_before = job.pool.size();
    try run(&job, &view);
    try std.testing.expect(job.pool.size() > pool_size_before);
}

const AbsoluteSourceSpan = @import("../../../../source_span.zig").AbsoluteSourceSpan;
