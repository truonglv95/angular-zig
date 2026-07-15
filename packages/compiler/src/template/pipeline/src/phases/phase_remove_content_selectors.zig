/// phase_remove_content_selectors phase
///
/// Port of: template/pipeline/src/phases/phase_remove_content_selectors.ts (49 LoC)
///
/// Update phase — Attributes of `ng-content` named 'select' are specifically
/// removed, because they control which content matches as a property of the
/// `projection`, and are not a plain attribute.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

/// Check if a binding name is 'select' (case-insensitive).
/// Direct port of `isSelectAttribute(name)` in the TS source.
fn isSelectAttribute(name: []const u8) bool {
    // The TS source uses `name.toLowerCase() === 'select'`.
    // We do a case-insensitive comparison directly.
    if (name.len != 6) return false;
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        const c = name[i];
        const lower = if (c >= 'A' and c <= 'Z') c + 32 else c;
        const expected: u8 = switch (i) {
            0 => 's',
            1 => 'e',
            2 => 'l',
            3 => 'e',
            4 => 'c',
            5 => 't',
            else => unreachable,
        };
        if (lower != expected) return false;
    }
    return true;
}

/// Remove content selectors from binding ops that target Projection ops.
/// Direct port of `removeContentSelectors(job)` in the TS source.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    // Build a map of xref → op kind for create ops (to check if target is Projection).
    // In the TS source, this uses `createOpXrefMap(unit)` from `util/elements.ts`.
    // Here we do a simpler scan: collect all Projection op xrefs.
    var projection_xrefs = std.AutoHashMap(u32, void).init(view.create.ops.allocator);
    defer projection_xrefs.deinit();

    for (view.create.ops.items) |create_op| {
        if (create_op.kind == .Projection) {
            try projection_xrefs.put(create_op.xref, {});
        }
    }

    // Filter update ops: remove Binding ops whose name is 'select' and whose
    // target (xref) is a Projection op.
    var write: usize = 0;
    for (view.update.ops.items) |op| {
        if (op.kind == .Binding) {
            const binding = op.data.Binding;
            if (isSelectAttribute(binding.name)) {
                // Check if the target (op.xref) is a Projection op.
                if (projection_xrefs.get(op.xref) != null) {
                    // Skip this op — remove it.
                    continue;
                }
            }
        }
        view.update.ops.items[write] = op;
        write += 1;
    }
    view.update.ops.items.len = write;
}

/// Public API matching TS export name.
pub fn removeContentSelectors(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    return run(job, view);
}

// ─── Tests ──────────────────────────────────────────────────

test "isSelectAttribute matches 'select' case-insensitively" {
    try std.testing.expect(isSelectAttribute("select"));
    try std.testing.expect(isSelectAttribute("SELECT"));
    try std.testing.expect(isSelectAttribute("Select"));
    try std.testing.expect(!isSelectAttribute("selected"));
    try std.testing.expect(!isSelectAttribute("sel"));
    try std.testing.expect(!isSelectAttribute("selector"));
}
