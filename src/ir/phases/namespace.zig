/// namespace phase
///
/// Port of: template/pipeline/src/phases/namespace.ts
///
/// Create phase — migrated from impl.zig
const std = @import("std");

const job_mod = @import("../job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;
const OpData = ir_ops.OpData;

const ir_enums = @import("../enums.zig");
const CompilationKind = ir_enums.CompilationKind;

const ir_expr = @import("../expression.zig");
const IrExpr = ir_expr.IrExpr;

const source_span = @import("../../source_span.zig");

// ─── Shared helpers ──
const MAX_DEPTH = helpers.MAX_DEPTH;
const helpers = @import("helpers.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

const Namespace = ir_ops.Namespace;

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.create.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    // Stack of namespaces per depth (stack-allocated)
    var ns_stack: [MAX_DEPTH]Namespace = undefined;
    @memset(&ns_stack, Namespace.HTML);
    var depth: u32 = 0;

    const items = view.create.ops.items;
    for (items) |op| {
        switch (op.kind) {
            .ElementStart => {
                const elem_ns = op.data.ElementStart.namespace;
                const parent_ns = if (depth > 0) ns_stack[depth - 1] else Namespace.HTML;
                // Insert NamespaceDeclare when namespace changes
                if (elem_ns != parent_ns) {
                    try result.append(.{
                        .kind = .NamespaceDeclare,
                        .xref = op.xref,
                        .source_span = op.source_span,
                        .data = .{ .NamespaceDeclare = elem_ns },
                    });
                }
                if (depth < MAX_DEPTH) {
                    ns_stack[depth] = elem_ns;
                }
                depth += 1;
                try result.append(op);
            },
            .ElementEnd => {
                try result.append(op);
                if (depth > 0) depth -= 1;
            },
            .ContainerStart => {
                depth += 1;
                try result.append(op);
            },
            .ContainerEnd => {
                try result.append(op);
                if (depth > 0) depth -= 1;
            },
            else => {
                try result.append(op);
            },
        }
    }

    view.create.ops.deinit();
    view.create.ops = result;
}
