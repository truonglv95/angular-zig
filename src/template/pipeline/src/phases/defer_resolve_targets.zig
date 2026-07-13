/// defer_resolve_targets phase
///
/// Port of: template/pipeline/src/phases/defer_resolve_targets.ts (139 LoC)
///
/// Create phase — Some `defer` conditions can reference other elements in the
/// template, using their local reference names. However, the semantics are
/// quite different from the normal local reference system: in particular, we
/// need to look at local reference names in enclosing views. This phase
/// resolves all such references to actual xrefs.
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

const ir_enums = @import("../../ir/enums.zig");
const DeferTriggerKind = ir_enums.DeferTriggerKind;

/// Scope — maps local reference names to their xref and slot.
const Scope = struct {
    targets: std.StringHashMap(Target),

    pub const Target = struct {
        xref: u32,
        slot: u32,
    };

    pub fn init(allocator: std.mem.Allocator) Scope {
        return .{ .targets = std.StringHashMap(Target).init(allocator) };
    }

    pub fn deinit(self: *Scope) void {
        self.targets.deinit();
    }
};

/// Resolve defer trigger target names to xrefs.
/// Direct port of `resolveDeferTargetNames(job)` in the TS source.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    // Build a scope for this view: map local ref names → xref+slot.
    var scope = Scope.init(view.create.ops.allocator);
    defer scope.deinit();

    try getScopeForView(view, &scope);

    // Walk create ops for DeferOn ops and resolve their trigger targets.
    for (view.create.ops.items) |*op| {
        if (op.kind != .DeferOn) continue;

        // In the TS source, this checks `op.trigger.kind`:
        //   Idle, Never, Immediate, Timer → no target to resolve (return)
        //   Hover, Interaction, Viewport → resolve targetName to xref+slot
        const trigger_kind: DeferTriggerKind = op.data.DeferOn;
        switch (trigger_kind) {
            .Idle, .Never, .Immediate, .Timer => continue,
            .Hover, .Interaction, .Viewport => {
                // Resolve the target name. The TS source looks up
                // `op.trigger.targetName` in the scope, then walks parent scopes
                // if not found. Our model doesn't have targetName on DeferOn yet.
                // When added, this will resolve it.
            },
        }
    }
}

/// Get the scope for a view, collecting all local ref targets.
/// Direct port of `getScopeForView(view)` in the TS source.
fn getScopeForView(view: *ViewCompilationUnit, scope: *Scope) !void {
    _ = scope;
    for (view.create.ops.items) |op| {
        // Check if this is an element or container op with local refs.
        if (!isElementOrContainerOp(op.kind)) continue;

        // In the TS source, this iterates `op.localRefs` and adds entries
        // where `ref.target === ''` (i.e., refs to the element itself, not
        // to a directive export).
        // Our model doesn't have localRefs on ops yet. When added, this will
        // populate the scope's targets map.
    }
}

/// Check if an op kind is an element or container op.
fn isElementOrContainerOp(kind: OpKind) bool {
    return switch (kind) {
        .ElementStart, .ElementEnd, .ContainerStart, .ContainerEnd, .Template => true,
        else => false,
    };
}

/// Public API matching TS export name.
pub fn resolveDeferTargetNames(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    return run(job, view);
}

test "isElementOrContainerOp" {
    try std.testing.expect(isElementOrContainerOp(.ElementStart));
    try std.testing.expect(isElementOrContainerOp(.ContainerStart));
    try std.testing.expect(!isElementOrContainerOp(.Text));
}

test "run is a no-op on view without DeferOn ops" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "Test", .Full);
    defer job.deinit();
    var view = ViewCompilationUnit.init(allocator, 0, null);
    defer view.deinit();

    try run(&job, &view);
    try std.testing.expectEqual(@as(usize, 0), view.create.ops.items.len);
}
