/// host_style_property_parsing phase
///
/// Port of: template/pipeline/src/phases/host_style_property_parsing.ts
///
/// Update phase — migrated from impl.zig
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;
const OpData = ir_ops.OpData;

const ir_enums = @import("../../ir/enums.zig");
const CompilationKind = ir_enums.CompilationKind;

const ir_expr = @import("../../ir/expression.zig");
const IrExpr = ir_expr.IrExpr;

const source_span = @import("../../../../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;


pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    const items = view.update.ops.items;
    const HOST_FLAG: u32 = 0x80000000;

    // Pass 1: host binding ops (xref has context flag set)
    for (items) |op| {
        if (op.xref & HOST_FLAG != 0) {
            try result.append(op);
        }
    }
    // Pass 2: all other ops (stable order)
    for (items) |op| {
        if (op.xref & HOST_FLAG == 0) {
            try result.append(op);
        }
    }

    view.update.ops.deinit();
    view.update.ops = result;
}

pub fn parseHostStyleProperties(allocator: std.mem.Allocator) void { _ = allocator; }