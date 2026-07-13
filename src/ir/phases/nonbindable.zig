/// nonbindable phase
///
/// Port of: template/pipeline/src/phases/nonbindable.ts
///
/// Status: STUB — not yet implemented.
/// This phase needs to be ported from the Angular TypeScript original.
const std = @import("std");

const job_mod = @import("../job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

/// Phase entry point.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    _ = view;
    // TODO: implement nonbindable phase
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
