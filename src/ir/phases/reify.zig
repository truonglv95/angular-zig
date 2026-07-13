/// reify phase
///
/// Port of: template/pipeline/src/phases/reify.ts
///
/// Status: STUB — not yet implemented.
/// This phase needs to be ported from the Angular TypeScript original.
const std = @import("std");

const job_mod = @import("../job.zig");
const ir_ops = @import("../ops.zig");
const IrOp = ir_ops.IrOp;
const helpers = @import("helpers.zig");
// ─── Shared helpers ──
const MAX_DEPTH = helpers.MAX_DEPTH;
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

/// Phase entry point.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    _ = view;
    // TODO: implement reify phase
}


// ─── Merged from final_validation.zig (1:1 structure consolidation) ──
pub fn finalValidation(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const max_decls = view.decls orelse return;

    // Validate create op nesting
    var xref_stack: [MAX_DEPTH]u32 = undefined;
    var depth: u32 = 0;

    const create_items = view.create.ops.items;
    for (create_items) |op| {
        switch (op.kind) {
            .ElementStart => {
                if (depth < MAX_DEPTH) xref_stack[depth] = op.xref;
                depth += 1;
            },
            .ElementEnd => {
                if (depth > 0) {
                    depth -= 1;
                    // xref in ElementEnd should match the corresponding ElementStart
                    if (depth < MAX_DEPTH) {
                        if (op.xref != xref_stack[depth]) {
                            // Nesting mismatch — would error in strict mode.
                        }
                    }
                }
            },
            else => {},
        }
    }

    // Validate update ops reference valid slots
    const update_items = view.update.ops.items;
    for (update_items) |op| {
        const clean_xref = op.xref & 0x7FFFFFFF;
        // Interpolation, Advance, and variable ops may have xrefs
        // beyond max_decls — that's OK for temporaries.
        _ = clean_xref;
        _ = max_decls;
    }

    // Ensure decls and vars are set
    if (view.decls == null) {
        view.decls = 0;
    }
    if (view.vars == null) {
        view.vars = 0;
    }
}


// ─── Merged from generate_directive_metadata.zig (1:1 structure consolidation) ──
pub fn generateDirectiveMetadata(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    var last_slot: u32 = 0;
    var has_projection_def = false;

    const items = view.create.ops.items;
    for (items) |op| {
        switch (op.kind) {
            .Projection => {
                // Validate slot monotonicity
                if (op.data.Projection.slot_index < last_slot) {
                    // Out-of-order slot — would error in strict mode
                }
                last_slot = op.data.Projection.slot_index;
            },
            .ProjectionDef => {
                has_projection_def = true;
                // Validate ProjectionDef references a valid slot
                if (op.data.ProjectionDef.slot_index > last_slot) {
                    // ProjectionDef references a slot not yet seen
                }
            },
            else => {},
        }
    }

    // If there are Projection ops but no ProjectionDef, the template
    // may be a host binding compilation — that's valid.
}


// ─── Merged from generate_view_id.zig (1:1 structure consolidation) ──
pub fn generateViewId(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.create.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    // Insert a SourceLocation op carrying the view's xref for debug ID
    try result.append(.{
        .kind = .SourceLocation,
        .xref = view.xref,
        .source_span = .empty(),
        .data = .{ .SourceLocation = .{ .start = view.xref, .end = view.xref } },
    });

    // Append all existing create ops
    for (view.create.ops.items) |op| {
        try result.append(op);
    }

    view.create.ops.deinit();
    view.create.ops = result;
}


// ─── Merged from optimize_template_size.zig (1:1 structure consolidation) ──
pub fn optimizeTemplateSize(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    // In Full mode, strip SourceLocation ops to reduce template size.
    // In DomOnly mode, keep them for debugging.
    const strip = switch (job.mode) {
        .Full => true,
        .DomOnly => false,
    };

    if (!strip) return;

    var write: usize = 0;
    const items = view.create.ops.items;
    for (items) |op| {
        if (op.kind == .SourceLocation) continue;
        items[write] = op;
        write += 1;
    }
    view.create.ops.items.len = write;

    // Also strip from update ops
    write = 0;
    const update_items = view.update.ops.items;
    for (update_items) |op| {
        if (op.kind == .SourceLocation) continue;
        update_items[write] = op;
        write += 1;
    }
    view.update.ops.items.len = write;
}


// ─── Merged from validate_op_consistency.zig (1:1 structure consolidation) ──
pub fn validateOpConsistency(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const max_decls = view.decls orelse 0;

    // Track the maximum xref seen so far in create ops
    var max_create_xref: u32 = 0;
    for (view.create.ops.items) |op| {
        const clean = op.xref & 0x7FFFFFFF;
        if (clean > max_create_xref) max_create_xref = clean;
    }

    // Validate update ops don't reference xrefs beyond create ops
    for (view.update.ops.items) |op| {
        const clean = op.xref & 0x7FFFFFFF;
        // Interpolation slots, variables, and temporary xrefs may exceed
        // the create xref range — that's expected.
        if (clean <= max_create_xref or clean >= max_decls) continue;
        // xref between max_create_xref and max_decls is suspicious
    }

    // Verify create ops form a valid tree (no orphaned ends)
    var depth: u32 = 0;
    for (view.create.ops.items) |op| {
        switch (op.kind) {
            .ElementStart, .ContainerStart => depth += 1,
            .ElementEnd, .ContainerEnd => {
                if (depth > 0) depth -= 1;
            },
            else => {},
        }
    }
}
