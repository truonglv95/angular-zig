/// control_directives — Process legacy structural directives
const std = @import("std");
const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;
const ir_ops = @import("../../ir/ops.zig");

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    for (view.update.ops.items) |*op| {
        if (op.kind == .Property or op.kind == .DomProperty) {
            const name = switch (op.data) { .Property => |p| p.name, .DomProperty => |d| d.name, else => continue };
            // ngClass and ngStyle specialization
            if (std.mem.eql(u8, name, "ngClass")) {  }
            if (std.mem.eql(u8, name, "ngStyle")) {  }
        }
    }
}
