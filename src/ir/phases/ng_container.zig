/// ng_container phase — Replace ng-container Element/ElementStart with Container/ContainerStart
///
/// Port of: template/pipeline/src/phases/ng_container.ts
///
/// Angular's <ng-container> is a special element that acts as a grouping
/// container without rendering a real DOM element. The compiler replaces
/// ElementStart/ElementEnd ops for ng-container with ContainerStart/ContainerEnd.
const std = @import("std");

const job_mod = @import("../job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

const CONTAINER_TAG = "ng-container";

/// Replace ElementStart/ElementEnd ops for ng-container with ContainerStart/ContainerEnd.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    // Track which xrefs have been transmuted from ElementStart to ContainerStart
    // so we can find the matching ElementEnd and transmute it too.
    var transmuted_xrefs = std.AutoHashMap(u32, void).init(view.create.allocator);
    defer transmuted_xrefs.deinit();

    // Phase 1: Transmute ElementStart → ContainerStart for ng-container
    const create_items = view.create.ops.items;
    for (create_items) |*op| {
        if (op.kind == .ElementStart) {
            if (std.mem.eql(u8, op.data.ElementStart.name, CONTAINER_TAG)) {
                const attrs_xref = op.data.ElementStart.attrs_xref;
                op.* = .{
                    .kind = .ContainerStart,
                    .xref = op.xref,
                    .source_span = op.source_span,
                    .data = .{ .ContainerStart = .{ .attrs_xref = attrs_xref } },
                };
                try transmuted_xrefs.put(op.xref, {});
            }
        }
    }

    // Phase 2: Transmute ElementEnd → ContainerEnd for matching xrefs
    for (create_items) |*op| {
        if (op.kind == .ElementEnd) {
            if (transmuted_xrefs.contains(op.xref)) {
                op.* = .{
                    .kind = .ContainerEnd,
                    .xref = op.xref,
                    .source_span = op.source_span,
                    .data = .{ .ContainerEnd = {} },
                };
            }
        }
    }
}
