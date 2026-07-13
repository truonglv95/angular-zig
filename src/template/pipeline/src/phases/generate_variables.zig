/// generate_variables — Emit variable declarations for template function
const std = @import("std");
const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    var var_count: u32 = 0;
    for (view.create.ops.items) |op| { if (op.kind == .Variable) { var_count += 1; } }
    var store_let_count: u32 = 0;
    for (view.update.ops.items) |op| { if (op.kind == .StoreLet) { store_let_count += 1; } }
    if (var_count > 0 or store_let_count > 0) {
        view.vars = var_count + store_let_count;
    }
}

pub fn generateVariables(allocator: std.mem.Allocator) void { _ = allocator; }