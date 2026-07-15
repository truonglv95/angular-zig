/// binding_specialization phase
///
/// Port of: template/pipeline/src/phases/binding_specialization.ts
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

// ─── Shared helpers ──
const bindingPriority = helpers.bindingPriority;
const helpers = @import("../helpers.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const items = view.update.ops.items;
    const n = items.len;

    // Sort by (xref, bindingPriority) — stable insertion sort
    var i: usize = 1;
    while (i < n) : (i += 1) {
        const key = items[i];
        const kp = bindingPriority(key.kind);
        var j = i;
        while (j > 0) {
            const prev = items[j - 1];
            const pp = bindingPriority(prev.kind);
            if (prev.xref == key.xref and pp > kp) {
                items[j] = prev;
                j -= 1;
            } else {
                break;
            }
        }
        items[j] = key;
    }
}

// ─── Merged from convert_attribute_to_property.zig (1:1 structure consolidation) ──
pub fn convertAttributeToProperty(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const items = view.update.ops.items;

    // Known DOM properties that should use Property instead of Binding
    const dom_properties = [_][]const u8{
        "id",       "value",    "checked",   "disabled",
        "readonly", "required", "multiple",  "selected",
        "hidden",   "tabIndex", "className",
    };

    for (items) |*op| {
        if (op.kind != .Binding) continue;
        const binding_name = op.data.Binding.name;

        // Check if this binding targets a known DOM property
        for (dom_properties) |prop| {
            if (std.mem.eql(u8, binding_name, prop)) {
                // Convert Binding → Property
                const old_binding = op.data.Binding;
                op.* = .{
                    .kind = .Property,
                    .xref = op.xref,
                    .source_span = op.source_span,
                    .data = .{ .Property = .{
                        .name = old_binding.name,
                        .expression = old_binding.expression,
                        .security_context = null,
                    } },
                };
                break;
            }
        }
    }
}

pub fn specializeBindings(allocator: std.mem.Allocator) void {
    _ = allocator;
}
