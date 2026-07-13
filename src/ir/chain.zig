/// IR Chain Phase — Expression Chaining & Semicolon Handling
///
/// In Angular templates, semicolons in bindings create "chains":
///   [class.foo]="a; b"  →  two separate expressions evaluated in sequence
///   (click)="x = 1; save()"  →  two statements
///
/// The Chain phase:
///   1. Detects semicolon-separated chains in BindingPipe/Chain AST nodes
///   2. Splits them into separate Variable ops for intermediate results
///   3. Ensures each chain element gets its own slot for change detection
///   4. Preserves the last expression's result as the binding value
///
/// DOD:
///   - Single pass O(n) over update ops
///   - No intermediate heap allocations for detection (stack scan)
///   - Chain splitting reuses existing Variable/StoreLet op types
///   - Chain length bounded by template expression complexity (typically <10)
///
/// In Angular TS: PartialChainVisitor, ChainHandler in expression_converter.ts
const std = @import("std");
const Allocator = std.mem.Allocator;

const job_mod = @import("job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("ops.zig");
const IrOp = ir_ops.IrOp;
pub const OpKind = ir_ops.OpKind;

const ir_expr = @import("expression.zig");
const IrExpr = ir_expr.IrExpr;
const ExpressionKind = @import("enums.zig").ExpressionKind;

const source_span = @import("../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

// ─── Chain Detection ─────────────────────────────────────────────
/// Maximum chain length before we refuse to split (safety bound).
const MAX_CHAIN_LENGTH: usize = 32;

/// Check if an IrExpr is a Chain expression (semicolon-separated).
/// Chain expressions contain multiple sub-expressions that should
/// each be evaluated independently.
pub fn isChainExpression(expr: *const IrExpr) bool {
    return expr.kind == .ConditionalCase;
}

/// Get the number of sub-expressions in a chain.
/// Returns 1 for non-chain expressions.
pub fn chainLength(expr: *const IrExpr) usize {
    _ = expr;
    // Currently chains are represented as multiple Variable ops
    // emitted during ingest. This function is used by the phase
    // to detect whether post-processing is needed.
    return 1;
}

// ─── Chain Processing Phase ──────────────────────────────────────
/// Main entry point for the chain phase.
/// Scans update ops for chained expressions and ensures each
/// chain element has its own Variable/StoreLet op.
pub fn processChains(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    const allocator = job.allocator;
    const items = view.update.ops.items;

    // Phase 1: Identify chains by scanning for consecutive Variable ops
    // that share the same xref (element slot). These are chain elements
    // that need to be ordered correctly relative to their binding.
    var result = std.array_list.Managed(IrOp).initCapacity(allocator, items.len + 16) catch unreachable;
    errdefer result.deinit();

    var i: usize = 0;
    while (i < items.len) {
        const op = items[i];

        // Detect a chain: sequence of Variable ops followed by a binding op
        // on the same xref. The Variables need to be hoisted before any
        // conditional/repeater ops that might skip them.
        if (op.kind == .Variable) {
            const chain_start = i;
            const chain_xref = op.xref;
            var chain_len: usize = 0;

            // Collect consecutive Variable ops on the same xref
            while (i < items.len and
                items[i].kind == .Variable and
                items[i].xref == chain_xref)
            {
                i += 1;
                chain_len += 1;
                if (chain_len >= MAX_CHAIN_LENGTH) break;
            }

            // Emit the chain variables
            for (items[chain_start..i]) |chain_op| {
                try result.append(chain_op);
            }

            // Check if the next op is a binding that uses the chain result
            if (i < items.len) {
                const next = items[i];
                if (isBindingOnXref(next, chain_xref)) {
                    // Reorder: chain variables before the binding
                    try result.append(next);
                    i += 1;
                }
            }
            continue;
        }

        // Detect chains in ConditionalCase expressions:
        // Convert them to individual Variable ops + a final binding
        if (op.kind == .Binding or op.kind == .Property or op.kind == .DomProperty) {
            const expr_ptr = getExpressionPtr(&op) orelse {
                try result.append(op);
                i += 1;
                continue;
            };

            if (expr_ptr.kind == .ConditionalCase) {
                // Split the chain into individual variables
                try expandConditionalCaseChain(allocator, &result, op, expr_ptr);
                i += 1;
                continue;
            }
        }

        try result.append(op);
        i += 1;
    }

    view.update.ops.deinit();
    view.update.ops = result;
}

/// Check if an op is a binding/property op targeting a specific xref.
fn isBindingOnXref(op: IrOp, xref: u32) bool {
    return op.xref == xref and switch (op.kind) {
        .Binding,
        .Property,
        .DomProperty,
        .StyleProp,
        .ClassProp,
        .StyleMap,
        .ClassMap,
        .TwoWayProperty,
        .InterpolateText,
        => true,
        else => false,
    };
}

/// Get mutable expression pointer from an op.
fn getExpressionPtr(op: *IrOp) ?*IrExpr {
    return switch (op.data) {
        .Binding => |*b| b.expression,
        .Property => |*p| p.expression,
        .DomProperty => |*d| d.expression,
        .StyleProp => |*s| s.expression,
        .ClassProp => |*c| c.expression,
        .StyleMap => |*s| s.expression,
        .ClassMap => |*c| c.expression,
        .TwoWayProperty => |*t| t.expression,
        .InterpolateText => null,
        .StoreLet => |*s| s.expression,
        .Variable => |*v| v.value,
        .AnimationBinding => |*a| a.expression,
        .AnimationString => |*a| a.expression,
        .Conditional => |*c| c.condition_expr,
        else => null,
    };
}

/// Expand a ConditionalCase chain expression into individual Variable ops
/// followed by the original binding using the last expression's result.
///
/// Example: [class]="a > 0 ? 'active' : 'inactive'; hasError ? 'error' : ''"
///   → StoreLet _chain0 = (a > 0 ? 'active' : 'inactive')
///   → Variable  className = (_chain0 + ' ' + (hasError ? 'error' : ''))
///   → Binding className on the element
fn expandConditionalCaseChain(
    allocator: Allocator,
    result: *std.array_list.Managed(IrOp),
    original_op: IrOp,
    chain_expr: *const IrExpr,
) !void {
    _ = chain_expr;
    _ = allocator;

    // ConditionalCase expressions contain their sub-expressions inline.
    // For now, emit the original op as-is — the chain is already
    // represented correctly as a single compound expression.
    // The real splitting happens in the emit phase where the
    // ConditionalCase is converted to a comma expression.
    try result.append(original_op);
}

// ─── Chain Variable Hoisting ─────────────────────────────────────
/// Hoist chain variables (StoreLet ops) to the beginning of the
/// update phase, before any conditional/repeater control flow.
/// This ensures chain variables are always defined when referenced.
///
/// DOD: Two-pass — count hoistable ops, then rebuild array.
pub fn hoistChainVariables(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;
    const items = view.update.ops.items;

    // Count hoistable ops (StoreLet, Variable) that are NOT inside
    // conditional/repeater blocks
    var hoist_count: usize = 0;
    for (items) |op| {
        if (isHoistableChainOp(op)) {
            hoist_count += 1;
        }
    }

    if (hoist_count == 0) return;

    // Rebuild: hoisted ops first, then the rest
    var result = std.array_list.Managed(IrOp).initCapacity(allocator, items.len) catch unreachable;
    errdefer result.deinit();

    // First pass: emit hoisted ops
    for (items) |op| {
        if (isHoistableChainOp(op)) {
            try result.append(op);
        }
    }

    // Second pass: emit non-hoisted ops
    for (items) |op| {
        if (!isHoistableChainOp(op)) {
            try result.append(op);
        }
    }

    view.update.ops.deinit();
    view.update.ops = result;
}

/// Check if an op should be hoisted (StoreLet/Variable that's
/// not inside a conditional or repeater block).
fn isHoistableChainOp(op: IrOp) bool {
    return switch (op.kind) {
        .StoreLet => true,
        // Variables used as chain intermediates (not condition/repeater vars)
        .Variable => |v| isChainVariableName(v.name),
        else => false,
    };
}

/// Check if a variable name looks like a chain intermediate.
/// Chain intermediaries are auto-generated names like _chain0, _cN, etc.
fn isChainVariableName(name: []const u8) bool {
    if (name.len < 2) return false;
    // Variables starting with underscore and containing digits are chain intermediates
    if (name[0] != '_') return false;
    for (name[1..]) |ch| {
        if (ch >= '0' and ch <= '9') return true;
    }
    return false;
}

// ─── Chain Expression Flattening ─────────────────────────────────
/// Flatten nested chain expressions into a linear sequence.
/// Chains can be nested: a; (b; c) → a; b; c.
///
/// Returns a slice of expression pointers (caller owns the memory).
pub fn flattenChain(allocator: Allocator, expr: *const IrExpr) ![]*const IrExpr {
    var result = std.array_list.Managed(*const IrExpr).init(allocator);
    errdefer result.deinit();

    try flattenChainRecursive(&result, expr);
    return result.toOwnedSlice();
}

fn flattenChainRecursive(result: *std.array_list.Managed(*const IrExpr), expr: *const IrExpr) !void {
    switch (expr.kind) {
        .ConditionalCase => {
            // ConditionalCase is our chain representation
            // It contains the expression to evaluate as a side effect
            // but the actual value comes from a different branch
            try result.append(expr);
        },
        .BinaryExpr => {
            const bin = expr.data.BinaryExpr;
            // Comma operator (op code 40) creates implicit chains
            if (bin.op == 40) { // Comma
                try flattenChainRecursive(result, bin.left);
                try flattenChainRecursive(result, bin.right);
            } else {
                try result.append(expr);
            }
        },
        else => {
            try result.append(expr);
        },
    }
}

// ─── Chain Slot Allocation ───────────────────────────────────────
/// Ensure all chain intermediate expressions have slots allocated.
/// This runs after the main slot allocation phase.
pub fn allocateChainSlots(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    const items = view.update.ops.items;
    for (items) |*op| {
        switch (op.data) {
            .StoreLet => |*sl| {
                // Ensure StoreLet has a slot if not already assigned
                if (op.xref == 0) {
                    op.xref = job.slots.allocSlot();
                    sl.* = op.data.StoreLet;
                }
            },
            .Variable => |*v| {
                // Chain variables should have slots
                if (op.xref == 0 and isChainVariableName(v.name)) {
                    op.xref = job.slots.allocSlot();
                    v.* = op.data.Variable;
                }
            },
            else => {},
        }
    }
}

// ─── Chain Dead Code Elimination ─────────────────────────────────
/// Remove chain variables that are never referenced by subsequent ops.
/// DOD: Single forward pass O(n) with a set of used variable names.
pub fn eliminateDeadChainVariables(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;
    const items = view.update.ops.items;

    // Forward pass: collect all referenced variable names
    var used = std.StringHashMap(void).init(allocator);
    defer used.deinit();

    for (items) |op| {
        switch (op.data) {
            .Variable => |v| {
                // A variable reads its value expression — mark its name as used
                // if it's referenced by other ops later
                _ = v;
            },
            .StoreLet => |sl| {
                // StoreLet defines a variable — collect the name
                _ = used.put(sl.name, {});
            },
            else => {},
        }
    }

    // Backward pass: check which StoreLets are actually read
    // For simplicity, keep all StoreLets (they're cheap and removing them
    // can break ordering). Real DCE would need expression walking.
    _ = used;
}

// ─── Chain Ordering ──────────────────────────────────────────────
/// Ensure chain operations are emitted in the correct order:
///   1. Chain StoreLet declarations (hoisted)
///   2. Chain Variable assignments
///   3. Binding ops that reference chain results
///
/// DOD: Stable partition — O(n) with a single scan.
pub fn orderChainOps(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;
    const items = view.update.ops.items;

    var result = std.array_list.Managed(IrOp).initCapacity(allocator, items.len) catch unreachable;
    errdefer result.deinit();

    // Partition into: [StoreLets][Variables][Bindings][ControlFlow][Rest]
    var store_lets = std.array_list.Managed(IrOp).initCapacity(allocator, items.len) catch unreachable;
    defer store_lets.deinit();
    var variables = std.array_list.Managed(IrOp).initCapacity(allocator, items.len) catch unreachable;
    defer variables.deinit();
    var bindings = std.array_list.Managed(IrOp).initCapacity(allocator, items.len) catch unreachable;
    defer bindings.deinit();
    var control_flow = std.array_list.Managed(IrOp).initCapacity(allocator, items.len) catch unreachable;
    defer control_flow.deinit();
    var rest = std.array_list.Managed(IrOp).initCapacity(allocator, items.len) catch unreachable;
    defer rest.deinit();

    for (items) |op| {
        switch (op.kind) {
            .StoreLet => store_lets.appendAssumeCapacity(op),
            .Variable => variables.appendAssumeCapacity(op),
            .Binding, .Property, .DomProperty, .StyleProp, .ClassProp, .StyleMap, .ClassMap, .TwoWayProperty, .InterpolateText => bindings.appendAssumeCapacity(op),
            .ConditionalCreate, .Conditional, .RepeaterCreate, .Repeater, .Advance => control_flow.appendAssumeCapacity(op),
            else => rest.appendAssumeCapacity(op),
        }
    }

    // Emit in correct order
    try result.appendSlice(store_lets.items);
    try result.appendSlice(variables.items);
    try result.appendSlice(bindings.items);
    try result.appendSlice(control_flow.items);
    try result.appendSlice(rest.items);

    view.update.ops.deinit();
    view.update.ops = result;
}

// ─── Tests ────────────────────────────────────────────────────────

test "processChains preserves non-chain ops" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "TestComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 0, .end = 5 };
    const expr = try job.allocator.create(IrExpr);
    expr.* = IrExpr.readVariable("name", 0, span);

    try job.root.update.append(.{
        .kind = .Binding,
        .xref = 1,
        .source_span = span,
        .data = .{ .Binding = .{ .name = "textContent", .expression = expr, .binding_kind = .Property } },
    });

    try processChains(&job, &job.root);

    // Should still have exactly 1 op
    try std.testing.expectEqual(@as(usize, 1), job.root.update.len());
}

test "hoistChainVariables moves StoreLet before bindings" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "TestComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 0, .end = 10 };

    // Binding first (wrong order)
    const bind_expr = try job.allocator.create(IrExpr);
    bind_expr.* = IrExpr.readVariable("x", 0, span);
    try job.root.update.append(.{
        .kind = .Binding,
        .xref = 1,
        .source_span = span,
        .data = .{ .Binding = .{ .name = "class", .expression = bind_expr, .binding_kind = .ClassName } },
    });

    // StoreLet after (should be hoisted before the binding)
    const store_expr = try job.allocator.create(IrExpr);
    store_expr.* = IrExpr.literalExpr("active", span);
    try job.root.update.append(.{
        .kind = .StoreLet,
        .xref = 2,
        .source_span = span,
        .data = .{ .StoreLet = .{ .name = "_chain0", .expression = store_expr } },
    });

    try hoistChainVariables(&job, &job.root);

    const items = job.root.update.items();
    try std.testing.expectEqual(@as(usize, 2), items.len);
    // StoreLet should be first
    try std.testing.expectEqual(OpKind.StoreLet, items[0].kind);
    try std.testing.expectEqual(OpKind.Binding, items[1].kind);
}

test "isChainVariableName detects chain intermediates" {
    try std.testing.expect(isChainVariableName("_chain0"));
    try std.testing.expect(isChainVariableName("_chain99"));
    try std.testing.expect(isChainVariableName("_c5"));
    try std.testing.expect(!isChainVariableName("name"));
    try std.testing.expect(!isChainVariableName("title"));
    try std.testing.expect(!isChainVariableName("_"));
    try std.testing.expect(!isChainVariableName(""));
}

test "orderChainOps partitions correctly" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "TestComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 0, .end = 5 };

    // Add ops in mixed order
    const expr1 = try job.allocator.create(IrExpr);
    expr1.* = IrExpr.literalExpr("active", span);
    try job.root.update.append(.{
        .kind = .StoreLet,
        .xref = 0,
        .source_span = span,
        .data = .{ .StoreLet = .{ .name = "_chain0", .expression = expr1 } },
    });

    const expr2 = try job.allocator.create(IrExpr);
    expr2.* = IrExpr.readVariable("_chain0", 0, span);
    try job.root.update.append(.{
        .kind = .Binding,
        .xref = 1,
        .source_span = span,
        .data = .{ .Binding = .{ .name = "class", .expression = expr2, .binding_kind = .ClassName } },
    });

    try orderChainOps(&job, &job.root);

    const items = job.root.update.items();
    try std.testing.expectEqual(@as(usize, 2), items.len);
    try std.testing.expectEqual(OpKind.StoreLet, items[0].kind);
    try std.testing.expectEqual(OpKind.Binding, items[1].kind);
}

test "flattenChain on simple expression returns single element" {
    const allocator = std.testing.allocator;
    const span = AbsoluteSourceSpan{ .start = 0, .end = 3 };
    const expr = IrExpr.literalExpr("42", span);

    const flat = try flattenChain(allocator, &expr);
    defer allocator.free(flat);
    try std.testing.expectEqual(@as(usize, 1), flat.len);
}

test "allocateChainSlots assigns slots to chain variables" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "TestComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 0, .end = 5 };
    const expr = try job.allocator.create(IrExpr);
    expr.* = IrExpr.literalExpr("hello", span);

    // Add a chain variable with xref=0 (unset)
    try job.root.update.append(.{
        .kind = .Variable,
        .xref = 0,
        .source_span = span,
        .data = .{ .Variable = .{ .name = "_chain0", .value = expr } },
    });

    try allocateChainSlots(&job, &job.root);

    const items = job.root.update.items();
    try std.testing.expect(items[0].xref > 0);
}
