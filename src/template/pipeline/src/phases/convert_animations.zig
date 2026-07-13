/// convert_animations phase
///
/// Port of: template/pipeline/src/phases/convert_animations.ts (75 LoC)
///
/// Both phase — Converts AnimationBinding update ops into Animation or
/// AnimationString create ops, placing them after the target element.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

const ir_enums = @import("../../ir/enums.zig");
const AnimationKind = ir_enums.AnimationKind;
const CompilationKind = ir_enums.CompilationKind;

/// ComponentCompilationJob is always .Tmpl kind.
const JOB_KIND: CompilationKind = .Tmpl;

const source_span = @import("../../../../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

/// Convert AnimationBinding update ops to Animation/AnimationString create ops.
/// Direct port of `convertAnimations(job)` in the TS source.
///
/// For each AnimationBinding op in update:
///   1. Determine if it's a STRING or VALUE animation binding
///   2. Create an AnimationString or Animation create op
///   3. Insert the create op after the target element (or push to create for Host jobs)
///   4. Remove the AnimationBinding update op
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    // Build a map of xref → create op index for element/container ops.
    var element_indices = std.AutoHashMap(u32, usize).init(view.create.ops.allocator);
    defer element_indices.deinit();

    for (view.create.ops.items, 0..) |create_op, i| {
        if (isElementOrContainerOp(create_op.kind)) {
            try element_indices.put(create_op.xref, i);
        }
    }

    // Collect new animation create ops to insert (with their target indices).
    var new_create_ops = std.array_list.Managed(struct { index: usize, op: IrOp }).init(view.create.ops.allocator);
    defer new_create_ops.deinit();

    // Filter update ops: remove AnimationBinding ops.
    var write: usize = 0;
    for (view.update.ops.items) |op| {
        if (op.kind == .AnimationBinding) {
            const anim_binding = op.data.AnimationBinding;

            // Determine animation kind: ENTER if name is "animate.enter", else LEAVE.
            const anim_kind: AnimationKind = if (std.mem.eql(u8, anim_binding.name, "animate.enter"))
                .ENTER
            else
                .LEAVE;
            _ = anim_kind;

            // Create an Animation create op (for both STRING and VALUE kinds;
            // our model doesn't distinguish them).
            const anim_op = IrOp{
                .kind = .Animation,
                .xref = op.xref,
                .source_span = op.source_span,
                .data = .{ .Animation = .{
                    .name = anim_binding.name,
                    .expr = anim_binding.expression,
                } },
            };

            if (JOB_KIND == .HostBinding) {
                // For Host jobs, push to the end of create ops.
                try view.create.ops.append(anim_op);
            } else {
                // For Tmpl jobs, insert after the target element.
                if (element_indices.get(op.xref)) |target_idx| {
                    try new_create_ops.append(.{ .index = target_idx + 1, .op = anim_op });
                }
            }

            // Skip this op (remove from update list).
            continue;
        }
        // Also handle AnimationString ops (legacy animation).
        if (op.kind == .AnimationString) {
            const anim_string = op.data.AnimationString;

            const anim_kind: AnimationKind = if (std.mem.eql(u8, anim_string.name, "animate.enter"))
                .ENTER
            else
                .LEAVE;
            _ = anim_kind;

            const anim_op = IrOp{
                .kind = .AnimationString,
                .xref = op.xref,
                .source_span = op.source_span,
                .data = .{ .AnimationString = .{
                    .name = anim_string.name,
                    .expression = anim_string.expression,
                } },
            };

            if (JOB_KIND == .HostBinding) {
                try view.create.ops.append(anim_op);
            } else {
                if (element_indices.get(op.xref)) |target_idx| {
                    try new_create_ops.append(.{ .index = target_idx + 1, .op = anim_op });
                }
            }
            continue;
        }
        view.update.ops.items[write] = op;
        write += 1;
    }
    view.update.ops.items.len = write;

    // Insert new create ops at their target indices (in reverse order to
    // preserve indices).
    const EntryType = @TypeOf(new_create_ops.items[0]);
    std.mem.sort(EntryType, new_create_ops.items, {}, struct {
        fn cmp(_: void, a: EntryType, b: EntryType) bool {
            return a.index > b.index;
        }
    }.cmp);
    for (new_create_ops.items) |entry| {
        try view.create.ops.insert(entry.index, entry.op);
    }
}

/// Check if an op kind is an element or container op.
/// Mirrors `ir.isElementOrContainerOp(op)` from the TS source.
fn isElementOrContainerOp(kind: OpKind) bool {
    return switch (kind) {
        .ElementStart, .ElementEnd, .ContainerStart, .ContainerEnd, .Template => true,
        else => false,
    };
}

/// Public API matching TS export name.
pub fn convertAnimations(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    return run(job, view);
}

test "isElementOrContainerOp" {
    try std.testing.expect(isElementOrContainerOp(.ElementStart));
    try std.testing.expect(isElementOrContainerOp(.ContainerStart));
    try std.testing.expect(isElementOrContainerOp(.Template));
    try std.testing.expect(!isElementOrContainerOp(.Text));
    try std.testing.expect(!isElementOrContainerOp(.Property));
}
