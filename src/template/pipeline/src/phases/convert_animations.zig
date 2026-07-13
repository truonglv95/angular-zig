/// convert_animations — Convert @animation trigger bindings to Animation ops
const std = @import("std");
const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    for (view.update.ops.items) |*op| {
        if (op.kind == .Property or op.kind == .Binding) {
            const name = switch (op.data) { .Property => |p| p.name, .Binding => |b| b.name, else => continue };
            if (name.len > 0 and name[0] == '@') {
                const trigger_name = if (name.len > 1) name[1..] else name;
                op.* = .{ .kind = .AnimationBinding, .xref = op.xref, .source_span = op.source_span,
                    .data = .{ .AnimationBinding = .{ .name = trigger_name, .expression = undefined } } };
            }
        }
    }
}

pub fn convertAnimations(allocator: std.mem.Allocator) void { _ = allocator; }