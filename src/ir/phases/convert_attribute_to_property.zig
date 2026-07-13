/// convert_attribute_to_property phase
///
/// Port of: template/pipeline/src/phases/convert_attribute_to_property.ts
///
/// Update phase — migrated from impl.zig
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
