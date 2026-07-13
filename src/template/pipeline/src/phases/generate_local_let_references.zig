/// generate_local_let_references phase
///
/// Port of: template/pipeline/src/phases/generate_local_let_references.ts (42 LoC)
///
/// Update phase — Replaces the `storeLet` ops with variables that can be
/// used to reference the value within the same view.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

const ir_enums = @import("../../ir/enums.zig");
const SemanticVariableKind = ir_enums.SemanticVariableKind;

const source_span = @import("../../../../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

/// Replace StoreLet ops with Variable ops that reference the stored value.
/// Direct port of `generateLocalLetReferences(job)` in the TS source.
///
/// For each StoreLet update op:
///   1. Create an IdentifierVariable with `identifier = op.declaredName`
///   2. Replace the StoreLet op with a Variable op containing a StoreLetExpr
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    for (view.update.ops.items) |*op| {
        if (op.kind != .StoreLet) continue;

        const store_let = op.data.StoreLet;

        // Allocate a new xref for the variable.
        const var_xref = job.slots.allocXref();

        // Create a Variable op that replaces the StoreLet.
        // In the TS source:
        //   const variable = { kind: Identifier, name: null, identifier: op.declaredName, local: true }
        //   ir.OpList.replace(op, ir.createVariableOp(xref, variable, StoreLetExpr(target, value, span), None))
        //
        // Our model: convert the StoreLet op in-place to a Variable op.
        op.* = IrOp{
            .kind = .Variable,
            .xref = var_xref,
            .source_span = op.source_span,
            .data = .{ .Variable = .{
                .name = store_let.name,
                .value = store_let.expression,
            } },
        };
    }
}

/// Public API matching TS export name.
pub fn generateLocalLetReferences(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    return run(job, view);
}

test "run converts StoreLet to Variable" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "Test", .Full);
    defer job.deinit();
    var view = ViewCompilationUnit.init(allocator, 0, null);
    defer view.deinit();

    // Create a stub expression for the StoreLet value.
    const stub_expr = try job.allocExpr(IrExpr);
    stub_expr.* = IrExpr.empty(AbsoluteSourceSpan.empty());

    // Add a StoreLet op.
    try view.update.ops.append(.{
        .kind = .StoreLet,
        .xref = 0,
        .source_span = AbsoluteSourceSpan.empty(),
        .data = .{ .StoreLet = .{
            .name = "myLet",
            .expression = stub_expr,
        } },
    });

    try run(&job, &view);
    try std.testing.expectEqual(@as(usize, 1), view.update.ops.items.len);
    try std.testing.expectEqual(OpKind.Variable, view.update.ops.items[0].kind);
    try std.testing.expectEqualStrings("myLet", view.update.ops.items[0].data.Variable.name);
}

const IrExpr = @import("../../ir/expression.zig").IrExpr;
