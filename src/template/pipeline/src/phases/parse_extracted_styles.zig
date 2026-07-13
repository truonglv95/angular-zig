/// parse_extracted_styles — Parse extracted style strings from host bindings
const std = @import("std");
const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;
const helpers = @import("../helpers.zig");

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    for (view.update.ops.items) |*op| {
        if (op.kind == .StyleMap) {
            if (helpers.getExpressionPtrConst(op.*)) |expr| { parseStyleExpression(expr); }
        }
    }
}

fn parseStyleExpression(expr: *const @import("../../ir/expression.zig").IrExpr) void {
    switch (expr.data) {
        .LiteralExpr => |lit| {
            var parts = std.mem.splitScalar(u8, lit.value, ';');
            while (parts.next()) |part| {
                const trimmed = std.mem.trim(u8, part, " \t\n\r");
                if (trimmed.len == 0) continue;
                // Parse "property: value" → individual StyleProp ops
            }
        },
        else => {},
    }
}

pub fn hyphenate(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    for (name) |ch| {
        if (ch >= 'A' and ch <= 'Z') { try result.append('-'); try result.append(std.ascii.toLower(ch)); }
        else { try result.append(ch); }
    }
    return result.toOwnedSlice();
}

pub fn parseExtractedStyles(allocator: std.mem.Allocator) void { _ = allocator; }