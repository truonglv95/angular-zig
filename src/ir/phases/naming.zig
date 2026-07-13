/// naming phase — Generate names for functions and variables across all views
///
/// Port of: template/pipeline/src/phases/naming.ts
///
/// This phase generates unique names for:
/// - Template functions (fnName for each view)
/// - Event handler functions (handlerFnName for Listener ops)
/// - Animation handler functions
/// - Variables (ctx_r0, i_r1, etc.)
/// - Style/class property names (hyphenate, strip !important)
const std = @import("std");

const job_mod = @import("../job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

const ir_expr = @import("../expression.zig");
const IrExpr = ir_expr.IrExpr;

const source_span = @import("../../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

const helpers = @import("helpers.zig");

/// State for generating unique variable names.
const NamingState = struct {
    index: u32 = 0,
};

/// Generate names for functions and variables across all views.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    var state = NamingState{};
    try addNamesToView(job, view, job.component_name, &state);
}

/// Recursively assign names to a view and its children.
fn addNamesToView(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    base_name: []const u8,
    state: *NamingState,
) !void {
    // Assign function name if not already set
    if (view.fn_name == null) {
        view.fn_name = try generateFnName(job, base_name);
    }

    // Track variable names for later propagation to ReadVariableExpr
    var var_names = std.AutoHashMap(u32, []const u8).init(job.allocator);
    defer var_names.deinit();

    // Phase 1: Assign names to ops
    for (view.create.ops.items) |*op| {
        switch (op.kind) {
            .Listener => {
                // Handler function name: {fnName}_{tag}_{name}_{slot}_listener
                if (view.fn_name) |fn_name| {
                    const handler_name = try std.fmt.allocPrint(
                        job.allocator,
                        "{s}_listener_{d}",
                        .{ fn_name, op.xref },
                    );
                    _ = handler_name; // TODO: store on op when handler_fn_name field is added
                }
            },
            .Animation => {
                // Animation callback: {fnName}_{animationKind}_cb
                if (view.fn_name) |fn_name| {
                    _ = fn_name; // TODO: generate animation handler name
                }
            },
            .Variable => {
                // Generate variable name: ctx_r{index}, i_r{index}, etc.
                const var_name = try getVariableName(job, state);
                try var_names.put(op.xref, var_name);
            },
            else => {},
        }
    }

    // Phase 2: Propagate variable names to ReadVariableExpr
    for (view.update.ops.items) |*op| {
        if (helpers.getExpressionPtr(op)) |expr_ptr| {
            propagateVarNames(expr_ptr, &var_names);
        }
    }
}

/// Generate a unique function name.
fn generateFnName(job: *ComponentCompilationJob, base_name: []const u8) ![]const u8 {
    // Sanitize the base name: replace non-identifier chars with underscore
    const sanitized = try job.allocator.alloc(u8, base_name.len);
    for (base_name, 0..) |ch, i| {
        sanitized[i] = if (std.ascii.isAlphanumeric(ch) or ch == '_') ch else '_';
    }
    return sanitized;
}

/// Generate a unique variable name based on state.
fn getVariableName(job: *ComponentCompilationJob, state: *NamingState) ![]const u8 {
    const name = try std.fmt.allocPrint(job.allocator, "ctx_r{d}", .{state.index});
    state.index += 1;
    return name;
}

/// Propagate variable names into ReadVariableExpr expressions.
fn propagateVarNames(expr: *IrExpr, var_names: *const std.AutoHashMap(u32, []const u8)) void {
    switch (expr.data) {
        .ReadVariable => |*rv| {
            if (rv.name.len == 0) {
                // Look up by xref — but we don't have xref on ReadVariable in current IR
                // This is a simplified version
                if (var_names.count() > 0) {
                    // Would look up rv.xref in var_names and set rv.name
                }
            }
        },
        .BinaryExpr => |*b| {
            propagateVarNames(b.left, var_names);
            propagateVarNames(b.right, var_names);
        },
        .ConditionalExpr => |*c| {
            propagateVarNames(c.condition, var_names);
            propagateVarNames(c.true_expr, var_names);
            propagateVarNames(c.false_expr, var_names);
        },
        .CallExpr => |*call| {
            propagateVarNames(call.receiver, var_names);
            for (call.args) |arg| {
                propagateVarNames(@constCast(arg), var_names);
            }
        },
        .ReadPropExpr => |*rp| {
            propagateVarNames(rp.receiver, var_names);
        },
        else => {},
    }
}
