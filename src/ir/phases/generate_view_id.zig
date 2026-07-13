/// generate_view_id phase
///
/// Port of: template/pipeline/src/phases/generate_view_id.ts
///
/// Post phase — migrated from impl.zig
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
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;


pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.create.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    // Insert a SourceLocation op carrying the view's xref for debug ID
    try result.append(.{
        .kind = .SourceLocation,
        .xref = view.xref,
        .source_span = .empty(),
        .data = .{ .SourceLocation = .{ .start = view.xref, .end = view.xref } },
    });

    // Append all existing create ops
    for (view.create.ops.items) |op| {
        try result.append(op);
    }

    view.create.ops.deinit();
    view.create.ops = result;
}
