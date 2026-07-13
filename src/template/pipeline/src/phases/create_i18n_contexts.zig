/// create_i18n_contexts phase — Create i18n context ops for i18n blocks
///
/// Port of: template/pipeline/src/phases/create_i18n_contexts.ts
///
/// Creates one i18n context per i18n block (including nested descending blocks).
/// Also creates additional contexts for ICUs inside i18n blocks that contain
/// other localizable content.
const std = @import("std");
const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;
const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;
const i18n_ctx = @import("../i18n_context.zig");

/// Create i18n contexts for i18n blocks and attributes.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    var registry = i18n_ctx.I18nContextRegistry.init(job.allocator);
    defer registry.deinit();

    // Phase 1: Create contexts for i18n attributes (Binding/Property with i18nMessage)
    var attr_context_by_msg = std.StringHashMap(u32).init(job.allocator);
    defer attr_context_by_msg.deinit();

    for (view.update.ops.items) |op| {
        // TODO: check if op has i18nMessage field
        // For now, scan for Binding ops with non-empty name (proxy for i18n attrs)
        _ = op;
    }

    // Phase 2: Create contexts for root i18n blocks (I18nStart ops where xref == root)
    for (view.create.ops.items) |op| {
        if (op.kind == .I18nStart) {
            // Check if this is a root i18n block
            // TODO: I18nStart op needs root field
            // For now, treat all I18nStart as root
            const xref = job.slots.allocXref();
            _ = try registry.createContext(.RootI18n, op.xref, xref);
        }
    }

    // Phase 3: Assign contexts for child i18n blocks (inherit from root)
    // Phase 4: Create/assign contexts for ICUs inside i18n blocks
    // TODO: implement when I18nStart/IcuStart ops have proper fields
}
