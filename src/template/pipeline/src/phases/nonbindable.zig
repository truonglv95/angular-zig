/// nonbindable phase — Emit disableBindings/enableBindings for ngNonBindable
///
/// Port of: template/pipeline/src/phases/nonbindable.ts
///
/// When a container is marked with ngNonBindable, the non-bindable characteristic
/// applies to all descendants. This phase inserts DisableBindings ops after
/// ElementStart/ContainerStart and EnableBindings ops before ElementEnd/ContainerEnd
/// for elements with the nonBindable flag.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

const source_span = @import("../../../../source_span.zig");

/// Phase entry point — insert DisableBindings/EnableBindings for ngNonBindable elements.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    // Build a set of xrefs for elements with nonBindable flag
    // TODO: the current IrOp doesn't have a `nonBindable` field on ElementStart/ContainerStart
    // When this field is added, this phase will:
    // 1. Scan create ops for ElementStart/ContainerStart with nonBindable=true
    // 2. Insert DisableBindings op after each such element
    // 3. Insert EnableBindings op before the matching ElementEnd/ContainerEnd
    //
    // For now, this is a no-op — ngNonBindable support requires IR schema changes.
    _ = view;
}


// ─── Merged from remove_noop_ops.zig (1:1 structure consolidation) ──
pub fn removeNoopOps(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    // Process create ops
    {
        var write: usize = 0;
        var disable_depth: u32 = 0;
        const items = view.create.ops.items;
        for (items) |op| {
            var skip = false;
            switch (op.kind) {
                .SourceLocation => skip = true, // metadata only
                .Statement => skip = op.data.Statement.len == 0,
                .DisableBindings => {
                    disable_depth += 1;
                },
                .EnableBindings => {
                    if (disable_depth > 0) {
                        disable_depth -= 1;
                    }
                },
                else => {},
            }
            if (!skip) {
                items[write] = op;
                write += 1;
            }
        }
        view.create.ops.items.len = write;
    }

    // Process update ops
    {
        var write: usize = 0;
        const items = view.update.ops.items;
        for (items) |op| {
            var skip = false;
            switch (op.kind) {
                .Advance => skip = op.data.Advance == 0,
                .SourceLocation => skip = true,
                else => {},
            }
            if (!skip) {
                items[write] = op;
                write += 1;
            }
        }
        view.update.ops.items.len = write;
    }
}
