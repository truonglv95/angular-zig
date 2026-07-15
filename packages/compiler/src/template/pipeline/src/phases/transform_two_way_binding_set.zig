/// transform_two_way_binding_set phase
///
/// Port of: template/pipeline/src/phases/transform_two_way_binding_set.ts
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
    const allocator = view.update.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    const items = view.update.ops.items;
    for (items) |op| {
        try result.append(op);

        if (op.kind == .TwoWayProperty) {
            const prop = op.data.TwoWayProperty;
            // Allocate a handler function xref for the write-back listener
            const handler_xref = job.slots.allocXref();
            // Emit TwoWayListener: listens for "nameChange" and writes back
            try result.append(.{
                .kind = .TwoWayListener,
                .xref = op.xref,
                .source_span = op.source_span,
                .data = .{ .TwoWayListener = .{
                    .name = prop.name,
                    .handler_fn_xref = handler_xref,
                } },
            });
        }
    }

    view.update.ops.deinit();
    view.update.ops = result;
}


// ─── Merged from normalize_two_way_binding_pairs.zig (1:1 structure consolidation) ──
pub fn normalizeTwoWayBindingPairs(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const items = view.update.ops.items;
    const n = items.len;

    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (items[i].kind != .TwoWayProperty) continue;

        // Look ahead for matching TwoWayListener
        const prop_name = items[i].data.TwoWayProperty.name;
        const prop_xref = items[i].xref;
        var found: ?usize = null;

        var j = i + 1;
        while (j < n) : (j += 1) {
            if (items[j].kind == .TwoWayListener and
                items[j].xref == prop_xref and
                std.mem.eql(u8, items[j].data.TwoWayListener.name, prop_name))
            {
                found = j;
                break;
            }
            // Stop searching past the next binding on a different xref
            if (items[j].xref != prop_xref and
                (items[j].kind == .Binding or
                    items[j].kind == .Property or
                    items[j].kind == .TwoWayProperty))
            {
                break;
            }
        }

        if (found) |listener_idx| {
            if (listener_idx > i + 1) {
                // Swap TwoWayListener to position i+1
                const listener = items[listener_idx];
                // Shift items i+1..listener_idx-1 right by one
                var k = listener_idx;
                while (k > i + 1) : (k -= 1) {
                    items[k] = items[k - 1];
                }
                items[i + 1] = listener;
                i += 1; // skip past the listener we just placed
            }
        }
    }
}
