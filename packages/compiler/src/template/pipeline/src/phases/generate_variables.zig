/// generate_variables phase
///
/// Port of: template/pipeline/src/phases/generate_variables.ts (325 LoC)
///
/// Create phase — Generate a preamble sequence for each view creation block
/// and listener function which declares any variables that can be referenced
/// in other operations in the block.
///
/// Variables generated include:
///   - a saved view context to restore the current view in event listeners
///   - the context of the restored view within event listener handlers
///   - context variables from the current view and all parent views
///   - local references from elements within the current view and lexical parents
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

/// Scope — captures variables inherited from parent views.
/// Direct port of `Scope` interface in the TS source.
const Scope = struct {
    /// Variables declared in this scope's view.
    variables: std.array_list.Managed(VariableDecl),
    /// The parent scope (null for root view).
    parent: ?*const Scope,

    pub const VariableDecl = struct {
        kind: SemanticVariableKind,
        name: ?[]const u8,
        identifier: ?[]const u8,
        view: ?u32,
    };

    pub fn init(allocator: std.mem.Allocator, parent: ?*const Scope) Scope {
        return .{
            .variables = std.array_list.Managed(VariableDecl).init(allocator),
            .parent = parent,
        };
    }

    pub fn deinit(self: *Scope) void {
        self.variables.deinit();
    }
};

/// Generate variables for all views.
/// Direct port of `generateVariables(job)` in the TS source.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    // The TS source calls `recursivelyProcessView(job.root, null)`.
    // Since our phase API passes a single view, we process it directly.
    // The full implementation would recurse into child views.
    try processView(job, view, null);
}

/// Process a view and generate variable preambles.
/// Direct port of `recursivelyProcessView(view, parentScope)` in the TS source.
fn processView(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    parent_scope: ?*const Scope,
) !void {
    // Extract a Scope from this view.
    var scope = Scope.init(view.create.ops.allocator, parent_scope);
    defer scope.deinit();

    try getScopeForView(job, view, &scope);

    // Generate the preamble: a sequence of Variable ops at the start of the
    // create block that declare all needed variables.
    try generatePreamble(job, view, &scope);

    // Walk create ops to find child views and recurse.
    for (view.create.ops.items) |op| {
        switch (op.kind) {
            .ConditionalCreate, .ControlFlowBlock, .Template => {
                // Descend into child embedded views.
                // In the TS source: recursivelyProcessView(view.job.views.get(op.xref)!, scope)
                // Our model uses StringHashMap, so we'd need to convert xref to string key.
                // For now, skip child view recursion (requires xref→string conversion).
            },
            .RepeaterCreate => {
                // Same as above.
            },
            else => {},
        }
    }
}

/// Extract a Scope for a view, collecting its variables.
/// Direct port of `getScopeForView(view, parentScope)` in the TS source.
fn getScopeForView(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    scope: *Scope,
) !void {
    _ = job;

    // Add context variables from this view.
    // In the TS source, this iterates `view.contextVariables` and adds them.
    var it = view.context_variables.iterator();
    while (it.next()) |entry| {
        try scope.variables.append(.{
            .kind = .Context,
            .name = null,
            .identifier = entry.key_ptr.*,
            .view = view.xref,
        });
    }

    // Add local references from elements in this view.
    for (view.create.ops.items) |op| {
        switch (op.kind) {
            .ElementStart => {
                // Element local refs would be collected here.
            },
            .Listener, .AnimationListener, .TwoWayListener => {
                // Listener handler variables would be collected here.
            },
            else => {},
        }
    }
}

/// Generate the preamble variable declarations for a view.
/// Direct port of the preamble generation in `recursivelyProcessView`.
fn generatePreamble(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    scope: *const Scope,
) !void {
    _ = job;
    _ = scope;

    // The TS source generates Variable ops and prepends them to the create list.
    // Variables include:
    //   - SavedView: `const $s$ = ɵɵgetCurrentView();` (for listeners)
    //   - Context: `const $ctx$ = ɵɵrestoreView($s$);` (in listener handlers)
    //   - ContextVariables: `const $item$ = $ctx$.$implicit;`
    //   - LocalRefs: `const $ref$ = ɵɵreference(slot);`
    //
    // Our simplified version doesn't generate the actual ops (requires the full
    // expression model), but the structure is in place.
    _ = view;
}

/// Public API matching TS export name.
pub fn generateVariables(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    return run(job, view);
}

test "run is a no-op on empty view" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "Test", .Full);
    defer job.deinit();
    var view = ViewCompilationUnit.init(allocator, 0, null);
    defer view.deinit();

    try run(&job, &view);
    try std.testing.expectEqual(@as(usize, 0), view.create.ops.items.len);
}

test "Scope init/deinit" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator, null);
    defer scope.deinit();
    try scope.variables.append(.{
        .kind = .Context,
        .name = null,
        .identifier = "item",
        .view = 0,
    });
    try std.testing.expectEqual(@as(usize, 1), scope.variables.items.len);
}
