/// remove_illegal_let_references — Remove @let references to out-of-scope vars
const std = @import("std");
const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;
const helpers = @import("../helpers.zig");

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    var valid_vars = std.StringHashMap(void).init(view.create.allocator);
    defer valid_vars.deinit();
    for (view.create.ops.items) |op| {
        if (op.kind == .Variable) {
            const name = switch (op.data) {
                .Variable => |v| v.name,
                else => continue,
            };
            if (name.len > 0) {
                valid_vars.put(name, {}) catch {};
            }
        }
    }
    var write: usize = 0;
    const items = view.update.ops.items;
    for (items) |op| {
        var skip = false;
        if (op.kind == .StoreLet) {
            if (helpers.getExpressionPtrConst(op)) |expr| {
                if (referencesInvalidVar(expr, &valid_vars)) {
                    skip = true;
                }
            }
        }
        if (!skip) {
            items[write] = op;
            write += 1;
        }
    }
    view.update.ops.items.len = write;
}

fn referencesInvalidVar(expr: *const @import("../../ir/expression.zig").IrExpr, valid: *const std.StringHashMap(void)) bool {
    return switch (expr.data) {
        .ReadVariable => |rv| !valid.contains(rv.name),
        .BinaryExpr => |b| referencesInvalidVar(b.left, valid) or referencesInvalidVar(b.right, valid),
        .CallExpr => |call| blk: {
            if (referencesInvalidVar(call.receiver, valid)) break :blk true;
            for (call.args) |a| {
                if (referencesInvalidVar(a, valid)) break :blk true;
            }
            break :blk false;
        },
        else => false,
    };
}
