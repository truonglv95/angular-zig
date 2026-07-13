/// resolve_foreign_content — Resolve SVG/MathML namespace inheritance
const std = @import("std");
const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;
const Namespace = @import("../../ir/ops.zig").Namespace;

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    var current_ns: Namespace = .HTML;
    var ns_stack: [32]Namespace = undefined;
    var ns_depth: u32 = 0;
    for (view.create.ops.items) |*op| {
        switch (op.kind) {
            .ElementStart => {
                if (ns_depth < 32) { ns_stack[ns_depth] = current_ns; ns_depth += 1; }
                const elem = &op.data.ElementStart;
                if (elem.namespace == .HTML and current_ns != .HTML) { elem.namespace = current_ns; }
                current_ns = elem.namespace;
            },
            .ElementEnd => { if (ns_depth > 0) { ns_depth -= 1; current_ns = ns_stack[ns_depth]; } },
            .ContainerStart => { if (ns_depth < 32) { ns_stack[ns_depth] = current_ns; ns_depth += 1; } },
            .ContainerEnd => { if (ns_depth > 0) { ns_depth -= 1; current_ns = ns_stack[ns_depth]; } },
            else => {},
        }
    }
}
