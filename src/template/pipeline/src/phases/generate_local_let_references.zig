/// generate_local_let_references — Generate StoreLet ops for @let declarations
const std = @import("std");
const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    var let_count: u32 = 0;
    for (view.create.ops.items) |op| {
        if (op.kind == .Variable) { let_count += 1; }
    }
    var i: u32 = 0;
    while (i < let_count) : (i += 1) {
        const slot = job.slots.allocSlot();
        try view.update.append(.{
            .kind = .StoreLet, .xref = slot, .source_span = .empty(),
            .data = .{ .StoreLet = .{ .name = "", .expression = undefined } },
        });
    }
}
