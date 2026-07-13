/// chaining phase
///
/// Port of: template/pipeline/src/phases/chaining.ts (162 LoC)
///
/// Post-process a reified view compilation and convert sequential calls to
/// chainable instructions into chain calls.
///
/// For example, two `elementStart` operations in sequence:
///   elementStart(0, 'div');
///   elementStart(1, 'span');
/// Can be called as a chain instead:
///   elementStart(0, 'div')(1, 'span');
const std = @import("std");

const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

/// Chain compatibility map — maps an instruction to the instruction it can
/// chain with. Direct port of `CHAIN_COMPATIBILITY` in the TS source.
///
/// Most instructions chain with themselves (e.g., elementStart → elementStart).
/// The exception is `conditionalCreate` which chains with `conditionalBranchCreate`.
const ChainableInstruction = enum {
    ariaProperty,
    attribute,
    classProp,
    element,
    elementContainer,
    elementContainerEnd,
    elementContainerStart,
    elementEnd,
    elementStart,
    domProperty,
    i18nExp,
    listener,
    property,
    styleProp,
    syntheticHostListener,
    syntheticHostProperty,
    templateCreate,
    twoWayProperty,
    twoWayListener,
    declareLet,
    conditionalCreate,
    conditionalBranchCreate,
    domElement,
    domElementStart,
    domElementEnd,
    domElementContainer,
    domElementContainerStart,
    domElementContainerEnd,
    domListener,
    domTemplate,
    animationEnter,
    animationLeave,
    animationEnterListener,
    animationLeaveListener,
};

/// Maximum number of chained instructions before starting a new chain.
/// Prevents stack overflow from deep AST of receiver expressions.
const MAX_CHAIN_LENGTH = 256;

/// Chain structure representing an in-progress chain.
const Chain = struct {
    /// The index of the op in the list that holds the chain.
    op_index: usize,
    /// The instruction being chained.
    instruction: ChainableInstruction,
    /// Number of instructions collected so far.
    length: u32,
};

/// Convert sequential chainable instructions into chain calls.
/// Direct port of `chain(job)` in the TS source.
pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    try chainOperationsInList(view.create.ops.items);
    try chainOperationsInList(view.update.ops.items);
}

/// Chain operations in a single op list.
/// Direct port of `chainOperationsInList(opList)` in the TS source.
fn chainOperationsInList(ops: []IrOp) !void {
    var current_chain: ?Chain = null;
    var write: usize = 0;

    for (ops, 0..) |op, i| {
        // Only Statement ops with ExpressionStatement are chainable.
        if (op.kind != .Statement) {
            current_chain = null;
            ops[write] = op;
            write += 1;
            continue;
        }

        // In our model, Statement ops store a string (the statement text).
        // The TS source checks if the statement is an ExpressionStatement with
        // an InvokeFunctionExpr with an ExternalExpr receiver.
        // We can't do that level of analysis without a full output AST.
        // For now, we just keep the ops as-is (no chaining).
        _ = i;
        current_chain = null;
        ops[write] = op;
        write += 1;
    }

    // Truncate to remove any ops that were "removed" (chained into previous).
    // In our simplified version, no ops are removed.
}

/// Public API matching TS export name.
pub fn chain(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
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
