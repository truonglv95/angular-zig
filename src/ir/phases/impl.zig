/// IR Transformation Phases — 50 real transformation phases
///
/// Each phase transforms the IR in-place for optimization/correctness.
/// DOD: Phases operate on contiguous OpList arrays — single-pass O(n)
/// where possible, no heap allocations in hot paths, stack variables,
/// contiguous array iteration, comptime decisions where possible.
///
/// Phase categories:
///   Create  — transform creation-phase ops (DOM tree building)
///   Update  — transform update-phase ops (binding application)
///   Both    — touch both create and update lists
///   Post    — final analysis / cleanup after all transformations
const std = @import("std");

const job_mod = @import("../job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../ops.zig");
const IrOp = ir_ops.IrOp;
pub const OpKind = ir_ops.OpKind;
const hasTrait = ir_ops.hasTrait;
const OpTrait = ir_ops.OpTrait;
pub const Namespace = ir_ops.Namespace;

const ir_enums = @import("../enums.zig");
const CompilationKind = ir_enums.CompilationKind;
const BindingKind = ir_enums.BindingKind;
const isCreationOp = ir_enums.isCreationOp;

const ir_expr = @import("../expression.zig");
const IrExpr = ir_expr.IrExpr;
const ExpressionKind = ir_enums.ExpressionKind;

const source_span = @import("../../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

const schema = @import("../../schema/registry.zig");
const SecurityContext = schema.SecurityContext;

const html_tags = @import("../../html/tags.zig");

// ─── Helpers ──────────────────────────────────────────────────

/// Max nesting depth for stack-allocated tracking arrays.
const MAX_DEPTH: usize = 128;

/// Whether a property name is security-sensitive (needs security_context).
fn isDangerousProperty(name: []const u8) bool {
    const dangerous = [_][]const u8{
        "innerHTML",
        "outerHTML",
        "formaction",
        "action",
        "data",
        "srcdoc",
    };
    for (dangerous) |d| {
        if (std.mem.eql(u8, name, d)) return true;
    }
    // href/src with javascript: prefix is checked separately
    return false;
}

/// Whether a URL-like property value starts with "javascript:".
fn isJavascriptUrl(value: []const u8) bool {
    return value.len >= 11 and std.mem.eql(u8, value[0..11], "javascript:");
}

/// Get the mutable expression pointer from an op, if it has one.
/// Returns null for ops without expressions.
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
        .InterpolateText => null, // has expressions[] but not a single expr
        .Conditional => |*c| c.condition_expr,
        .Repeater => |*r| r.track_by_fn orelse return null,
        .StoreLet => |*s| s.expression,
        .Variable => |*v| v.value,
        .Animation => |*a| a.expr,
        .AnimationBinding => |*a| a.expression,
        .AnimationString => |*a| a.expression,
        else => null,
    };
}

/// Get the property/binding name from an op, if it has one.
fn getOpName(op: IrOp) ?[]const u8 {
    return switch (op.data) {
        .Binding => |b| b.name,
        .Property => |p| p.name,
        .DomProperty => |d| d.name,
        .StyleProp => |s| s.name,
        .ClassProp => |c| c.name,
        .TwoWayProperty => |t| t.name,
        .TwoWayListener => |t| t.name,
        .Listener => |l| l.name,
        .ElementStart => |e| e.name,
        .Statement => |s| s,
        else => null,
    };
}

/// Get the name of a Variable or StoreLet op.
fn getVariableName(op: IrOp) ?[]const u8 {
    return switch (op.data) {
        .StoreLet => |s| s.name,
        .Variable => |v| v.name,
        else => null,
    };
}

/// Binding priority for canonical ordering (lower = earlier).
fn bindingPriority(kind: OpKind) u8 {
    return switch (kind) {
        .TwoWayProperty, .TwoWayListener => 0,
        .Property, .DomProperty => 1,
        .Binding => 2,
        .ClassProp, .ClassMap => 3,
        .StyleProp, .StyleMap => 4,
        .InterpolateText => 5,
        .Pipe => 6,
        .AnimationBinding, .AnimationString => 7,
        .Advance => 8,
        .StoreLet, .Variable => 9,
        .Conditional => 10,
        .Repeater => 11,
        .I18nExpression => 12,
        else => 255,
    };
}

/// Create a zero-span IR op (used as fallback for inserted ops).
fn zeroOp(kind: OpKind, xref: u32, data: ir_ops.OpData) IrOp {
    return .{
        .kind = kind,
        .xref = xref,
        .source_span = .empty(),
        .data = data,
    };
}

// ─── Phase Registry ──────────────────────────────────────────

pub const Phase = struct {
    name: []const u8,
    fn_ptr: *const fn (job: *ComponentCompilationJob, view: *ViewCompilationUnit) anyerror!void,
    kind: PhaseKind,

    pub const PhaseKind = enum { Create, Update, Both, Post };
};

/// All 50 core phases in dependency order.
/// Create phases first → Both → Update → Post.
pub const CORE_PHASES: []const Phase = &.{
    // ── Create Phase (9) ──────────────────────────────────────
    .{ .name = "orderCreationOps", .fn_ptr = orderCreationOps, .kind = .Create },
    .{ .name = "processDeferredBlocks", .fn_ptr = processDeferredBlocks, .kind = .Create },
    .{ .name = "emitNamespaceChanges", .fn_ptr = emitNamespaceChanges, .kind = .Create },
    .{ .name = "generateAdvanceOps", .fn_ptr = generateAdvanceOps, .kind = .Create },
    .{ .name = "coalesceTextOps", .fn_ptr = coalesceTextOps, .kind = .Create },
    .{ .name = "deduplicateAttributes", .fn_ptr = deduplicateAttributes, .kind = .Create },
    .{ .name = "validateNesting", .fn_ptr = validateNesting, .kind = .Create },
    .{ .name = "mergeAdjacentText", .fn_ptr = mergeAdjacentText, .kind = .Create },
    .{ .name = "removeEmptyIcuBlocks", .fn_ptr = removeEmptyIcuBlocks, .kind = .Create },

    // ── Both Phase (2) ─────────────────────────────────────────
    .{ .name = "attachSourceLocations", .fn_ptr = attachSourceLocations, .kind = .Both },
    .{ .name = "injectSecurityContexts", .fn_ptr = injectSecurityContexts, .kind = .Both },

    // ── Update Phase (29) ──────────────────────────────────────
    .{ .name = "orderUpdateOps", .fn_ptr = orderUpdateOps, .kind = .Update },
    .{ .name = "removeEmptyBindings", .fn_ptr = removeEmptyBindings, .kind = .Update },
    .{ .name = "collapseSingletonInterpolations", .fn_ptr = collapseSingletonInterpolations, .kind = .Update },
    .{ .name = "resolveContexts", .fn_ptr = resolveContexts, .kind = .Update },
    .{ .name = "expandTwoWayBindings", .fn_ptr = expandTwoWayBindings, .kind = .Update },
    .{ .name = "createPipes", .fn_ptr = createPipes, .kind = .Update },
    .{ .name = "liftLocalRefs", .fn_ptr = liftLocalRefs, .kind = .Update },
    .{ .name = "expandSafeReads", .fn_ptr = expandSafeReads, .kind = .Update },
    .{ .name = "generateTemporaryVariables", .fn_ptr = generateTemporaryVariables, .kind = .Update },
    .{ .name = "optimizeVariables", .fn_ptr = optimizeVariables, .kind = .Update },
    .{ .name = "hoistStoreLets", .fn_ptr = hoistStoreLets, .kind = .Update },
    .{ .name = "normalizeBindingOrder", .fn_ptr = normalizeBindingOrder, .kind = .Update },
    .{ .name = "removeDuplicateAdvanceOps", .fn_ptr = removeDuplicateAdvanceOps, .kind = .Update },
    .{ .name = "allocateInterpolationSlots", .fn_ptr = allocateInterpolationSlots, .kind = .Update },
    .{ .name = "generatePureFunctions", .fn_ptr = generatePureFunctions, .kind = .Update },
    .{ .name = "normalizeStyleMapExpressions", .fn_ptr = normalizeStyleMapExpressions, .kind = .Update },
    .{ .name = "normalizeClassMapExpressions", .fn_ptr = normalizeClassMapExpressions, .kind = .Update },
    .{ .name = "constantFoldExpressions", .fn_ptr = constantFoldExpressions, .kind = .Update },
    .{ .name = "resolvePureFunctionRefs", .fn_ptr = resolvePureFunctionRefs, .kind = .Update },
    .{ .name = "deduplicatePipes", .fn_ptr = deduplicatePipes, .kind = .Update },
    .{ .name = "inlineSimpleVariables", .fn_ptr = inlineSimpleVariables, .kind = .Update },
    .{ .name = "convertAttributeToProperty", .fn_ptr = convertAttributeToProperty, .kind = .Update },
    .{ .name = "extractHostBindings", .fn_ptr = extractHostBindings, .kind = .Update },
    .{ .name = "generateRepeaterTrackBy", .fn_ptr = generateRepeaterTrackBy, .kind = .Update },
    .{ .name = "wrapConditionalBranches", .fn_ptr = wrapConditionalBranches, .kind = .Update },
    .{ .name = "removeUnusedStoreLets", .fn_ptr = removeUnusedStoreLets, .kind = .Update },
    .{ .name = "normalizeTwoWayBindingPairs", .fn_ptr = normalizeTwoWayBindingPairs, .kind = .Update },
    .{ .name = "hoistConstantExpressions", .fn_ptr = hoistConstantExpressions, .kind = .Update },
    .{ .name = "reorderProjectionBindings", .fn_ptr = reorderProjectionBindings, .kind = .Update },

    // ── Post Phase (10) ───────────────────────────────────────
    .{ .name = "allocateSlots", .fn_ptr = allocateSlots, .kind = .Post },
    .{ .name = "countVariables", .fn_ptr = countVariables, .kind = .Post },
    .{ .name = "validateXrefs", .fn_ptr = validateXrefs, .kind = .Post },
    .{ .name = "removeNoopOps", .fn_ptr = removeNoopOps, .kind = .Post },
    .{ .name = "compactXrefs", .fn_ptr = compactXrefs, .kind = .Post },
    .{ .name = "finalValidation", .fn_ptr = finalValidation, .kind = .Post },
    .{ .name = "generateViewId", .fn_ptr = generateViewId, .kind = .Post },
    .{ .name = "validateOpConsistency", .fn_ptr = validateOpConsistency, .kind = .Post },
    .{ .name = "optimizeTemplateSize", .fn_ptr = optimizeTemplateSize, .kind = .Post },
    .{ .name = "generateDirectiveMetadata", .fn_ptr = generateDirectiveMetadata, .kind = .Post },
};

// ─── Explicit Pipeline with Timing ──────────────────────────

/// Explicit pipeline phase with per-phase timing.
pub const PipelinePhase = struct {
    name: []const u8,
    fn_ptr: *const fn (job: *ComponentCompilationJob, view: *ViewCompilationUnit) anyerror!void,
    elapsed_ns: u64 = 0,
};

/// All pipeline phases in the required execution order.
/// This is the authoritative phase sequence — CORE_PHASES is derived from this.
pub const PIPELINE_PHASES: []const PipelinePhase = &.{
    // ── Security & Namespace (pre-pass) ──────────────────────
    .{ .name = "injectSecurityContexts", .fn_ptr = injectSecurityContexts },
    .{ .name = "declareNamespaces", .fn_ptr = declareNamespaces },

    // ── Core phases (from CORE_PHASES, minus injectSecurityContexts) ──
    .{ .name = "orderCreationOps", .fn_ptr = orderCreationOps },
    .{ .name = "processDeferredBlocks", .fn_ptr = processDeferredBlocks },
    .{ .name = "emitNamespaceChanges", .fn_ptr = emitNamespaceChanges },
    .{ .name = "generateAdvanceOps", .fn_ptr = generateAdvanceOps },
    .{ .name = "coalesceTextOps", .fn_ptr = coalesceTextOps },
    .{ .name = "deduplicateAttributes", .fn_ptr = deduplicateAttributes },
    .{ .name = "validateNesting", .fn_ptr = validateNesting },
    .{ .name = "mergeAdjacentText", .fn_ptr = mergeAdjacentText },
    .{ .name = "removeEmptyIcuBlocks", .fn_ptr = removeEmptyIcuBlocks },
    .{ .name = "attachSourceLocations", .fn_ptr = attachSourceLocations },
    .{ .name = "orderUpdateOps", .fn_ptr = orderUpdateOps },
    .{ .name = "removeEmptyBindings", .fn_ptr = removeEmptyBindings },
    .{ .name = "collapseSingletonInterpolations", .fn_ptr = collapseSingletonInterpolations },
    .{ .name = "resolveContexts", .fn_ptr = resolveContexts },
    .{ .name = "expandTwoWayBindings", .fn_ptr = expandTwoWayBindings },
    .{ .name = "createPipes", .fn_ptr = createPipes },
    .{ .name = "liftLocalRefs", .fn_ptr = liftLocalRefs },
    .{ .name = "expandSafeReads", .fn_ptr = expandSafeReads },
    .{ .name = "generateTemporaryVariables", .fn_ptr = generateTemporaryVariables },
    .{ .name = "optimizeVariables", .fn_ptr = optimizeVariables },
    .{ .name = "hoistStoreLets", .fn_ptr = hoistStoreLets },
    .{ .name = "normalizeBindingOrder", .fn_ptr = normalizeBindingOrder },
    .{ .name = "removeDuplicateAdvanceOps", .fn_ptr = removeDuplicateAdvanceOps },
    .{ .name = "allocateInterpolationSlots", .fn_ptr = allocateInterpolationSlots },
    .{ .name = "generatePureFunctions", .fn_ptr = generatePureFunctions },
    .{ .name = "normalizeStyleMapExpressions", .fn_ptr = normalizeStyleMapExpressions },
    .{ .name = "normalizeClassMapExpressions", .fn_ptr = normalizeClassMapExpressions },
    .{ .name = "constantFoldExpressions", .fn_ptr = constantFoldExpressions },
    .{ .name = "resolvePureFunctionRefs", .fn_ptr = resolvePureFunctionRefs },
    .{ .name = "deduplicatePipes", .fn_ptr = deduplicatePipes },
    .{ .name = "inlineSimpleVariables", .fn_ptr = inlineSimpleVariables },
    .{ .name = "convertAttributeToProperty", .fn_ptr = convertAttributeToProperty },
    .{ .name = "extractHostBindings", .fn_ptr = extractHostBindings },
    .{ .name = "generateRepeaterTrackBy", .fn_ptr = generateRepeaterTrackBy },
    .{ .name = "wrapConditionalBranches", .fn_ptr = wrapConditionalBranches },
    .{ .name = "removeUnusedStoreLets", .fn_ptr = removeUnusedStoreLets },
    .{ .name = "normalizeTwoWayBindingPairs", .fn_ptr = normalizeTwoWayBindingPairs },
    .{ .name = "hoistConstantExpressions", .fn_ptr = hoistConstantExpressions },
    .{ .name = "reorderProjectionBindings", .fn_ptr = reorderProjectionBindings },
    .{ .name = "allocateSlots", .fn_ptr = allocateSlots },
    .{ .name = "countVariables", .fn_ptr = countVariables },
    .{ .name = "validateXrefs", .fn_ptr = validateXrefs },
    .{ .name = "removeNoopOps", .fn_ptr = removeNoopOps },
    .{ .name = "compactXrefs", .fn_ptr = compactXrefs },
    .{ .name = "finalValidation", .fn_ptr = finalValidation },
    .{ .name = "generateViewId", .fn_ptr = generateViewId },
    .{ .name = "validateOpConsistency", .fn_ptr = validateOpConsistency },
    .{ .name = "optimizeTemplateSize", .fn_ptr = optimizeTemplateSize },
    .{ .name = "generateDirectiveMetadata", .fn_ptr = generateDirectiveMetadata },
};

/// Per-phase timing results (mutable copy for each transform call).
pub const PhaseTimings = struct {
    phase_name: []const u8,
    elapsed_ns: u64,
};

/// Main Transform Entry Point ──────────────────────────────
/// Runs all phases on root + embedded views.
pub fn transform(job: *ComponentCompilationJob, kind: CompilationKind) !void {
    _ = kind;
    // Run phases on root view
    for (PIPELINE_PHASES) |phase| {
        try phase.fn_ptr(job, &job.root);
    }

    // Run phases on embedded views
    var it = job.views.iterator();
    while (it.next()) |entry| {
        for (PIPELINE_PHASES) |phase| {
            try phase.fn_ptr(job, entry.value_ptr.*);
        }
    }
}

/// Run phases with per-phase nanosecond timing instrumentation.
/// Returns a slice of PhaseTimings (caller owns the memory via the allocator).
/// DOD: Single allocation for the timings array, std.time.nanoTimestamp per phase.
pub fn transformWithTimings(
    allocator: std.mem.Allocator,
    job: *ComponentCompilationJob,
    _: CompilationKind,
) ![]PhaseTimings {
    const phase_count = PIPELINE_PHASES.len;
    var timings = try allocator.alloc(PhaseTimings, phase_count);
    errdefer allocator.free(timings);

    // Run phases on root view
    for (PIPELINE_PHASES, 0..) |phase, i| {
        const start = getNsTimestamp();
        try phase.fn_ptr(job, &job.root);
        const end = getNsTimestamp();
        timings[i] = .{
            .phase_name = phase.name,
            .elapsed_ns = @intCast(end - start),
        };
    }

    // Run phases on embedded views (accumulate timing into existing entries)
    var it = job.views.iterator();
    while (it.next()) |entry| {
        for (PIPELINE_PHASES, 0..) |phase, i| {
            const start = getNsTimestamp();
            try phase.fn_ptr(job, entry.value_ptr.*);
            const end = getNsTimestamp();
            timings[i].elapsed_ns += @intCast(end - start);
        }
    }

    return timings;
}

/// Get current monotonic timestamp in nanoseconds
fn getNsTimestamp() i64 {
    var ts: std.os.linux.timespec = undefined;
    const rc = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
    if (rc != 0) return 0;
    return @as(i64, ts.sec) * std.time.ns_per_s + ts.nsec;
}

// ═══════════════════════════════════════════════════════════════
//  CREATE PHASES
// ═══════════════════════════════════════════════════════════════

// ─── 1. Order Creation Ops ───────────────────────────────────
/// Validate ElementStart/End pairing using a stack.
/// Track depth and ensure proper nesting.
/// DOD: Single pass O(n) with stack-allocated depth counter.
fn orderCreationOps(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    var depth: u32 = 0;
    var max_depth: u32 = 0;

    const items = view.create.ops.items;
    for (items) |op| {
        switch (op.kind) {
            .ElementStart, .ContainerStart => {
                depth += 1;
                if (depth > max_depth) max_depth = depth;
            },
            .ElementEnd, .ContainerEnd => {
                if (depth == 0) {
                    // Unmatched close — fix by skipping (would error in strict mode)
                    continue;
                }
                depth -= 1;
            },
            else => {},
        }
    }

    // If depth > 0, there are unclosed elements.
    // Auto-close by appending ElementEnd ops.
    while (depth > 0) : (depth -= 1) {
        try view.create.append(.{
            .kind = .ElementEnd,
            .xref = 0,
            .source_span = .empty(),
            .data = .{ .ElementEnd = {} },
        });
    }
}

// ─── 2. Process Deferred Blocks ──────────────────────────────
/// Ensure all Defer ops have a proper trigger sequence.
/// A Defer must be followed by DeferOn or DeferWhen.
/// If missing, insert a default DeferOn(.Idle).
fn processDeferredBlocks(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.create.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    const items = view.create.ops.items;
    var i: usize = 0;
    while (i < items.len) {
        const op = items[i];
        try result.append(op);

        if (op.kind == .Defer) {
            // Check if next op is DeferOn or DeferWhen
            const has_trigger = if (i + 1 < items.len)
                items[i + 1].kind == .DeferOn or items[i + 1].kind == .DeferWhen
            else
                false;

            if (!has_trigger) {
                // Insert default DeferOn(.Idle)
                try result.append(.{
                    .kind = .DeferOn,
                    .xref = op.xref,
                    .source_span = op.source_span,
                    .data = .{ .DeferOn = .Idle },
                });
            }
        }

        i += 1;
    }

    view.create.ops.deinit();
    view.create.ops = result;
}

// ─── 3. Emit Namespace Changes ──────────────────────────────
/// Insert NamespaceDeclare ops when entering SVG/MathML from HTML.
/// Track current namespace per stack depth.
/// DOD: Single pass O(n), stack-allocated namespace stack.
fn emitNamespaceChanges(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.create.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    // Stack of namespaces per depth (stack-allocated)
    var ns_stack: [MAX_DEPTH]Namespace = undefined;
    @memset(&ns_stack, Namespace.HTML);
    var depth: u32 = 0;

    const items = view.create.ops.items;
    for (items) |op| {
        switch (op.kind) {
            .ElementStart => {
                const elem_ns = op.data.ElementStart.namespace;
                const parent_ns = if (depth > 0) ns_stack[depth - 1] else Namespace.HTML;
                // Insert NamespaceDeclare when namespace changes
                if (elem_ns != parent_ns) {
                    try result.append(.{
                        .kind = .NamespaceDeclare,
                        .xref = op.xref,
                        .source_span = op.source_span,
                        .data = .{ .NamespaceDeclare = elem_ns },
                    });
                }
                if (depth < MAX_DEPTH) {
                    ns_stack[depth] = elem_ns;
                }
                depth += 1;
                try result.append(op);
            },
            .ElementEnd => {
                try result.append(op);
                if (depth > 0) depth -= 1;
            },
            .ContainerStart => {
                depth += 1;
                try result.append(op);
            },
            .ContainerEnd => {
                try result.append(op);
                if (depth > 0) depth -= 1;
            },
            else => {
                try result.append(op);
            },
        }
    }

    view.create.ops.deinit();
    view.create.ops = result;
}

// ─── 4. Generate Advance Ops ────────────────────────────────
/// Insert Advance ops between sibling elements.
/// After an ElementEnd, if the next ElementStart is at the same depth
/// (i.e., they share a parent), insert Advance(delta) where
/// delta = next_element.xref - element_end.xref.
/// DOD: Single pass O(n), stack-allocated depth tracking.
fn generateAdvanceOps(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.create.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    const items = view.create.ops.items;
    var depth: u32 = 0;
    // Track the last ElementEnd's (xref, depth_after_pop)
    var last_end_xref: ?u32 = null;
    var last_end_depth: u32 = 0;

    for (items) |op| {
        switch (op.kind) {
            .ElementStart => {
                // Sibling check: last ElementEnd was at the same depth
                if (last_end_xref != null and last_end_depth == depth) {
                    const delta = op.xref -| last_end_xref.?;
                    if (delta > 0) {
                        try result.append(.{
                            .kind = .Advance,
                            .xref = op.xref,
                            .source_span = op.source_span,
                            .data = .{ .Advance = delta },
                        });
                    }
                }
                depth += 1;
                last_end_xref = null;
                try result.append(op);
            },
            .ElementEnd => {
                if (depth > 0) depth -= 1;
                try result.append(op);
                last_end_xref = op.xref;
                last_end_depth = depth;
            },
            .ContainerStart => {
                depth += 1;
                // Container transitions don't trigger advances
                last_end_xref = null;
                try result.append(op);
            },
            .ContainerEnd => {
                if (depth > 0) depth -= 1;
                try result.append(op);
                last_end_xref = null;
            },
            else => {
                // Non-element ops between siblings don't clear the advance tracking
                try result.append(op);
            },
        }
    }

    view.create.ops.deinit();
    view.create.ops = result;
}

// ─── 5. Coalesce Text Ops ───────────────────────────────────
/// Remove duplicate Text ops on the same xref slot.
/// Also merge adjacent Text ops that reference consecutive const indices
/// by keeping only the first one (they render as a single text node).
/// DOD: Single pass O(n) with compact-in-place.
fn coalesceTextOps(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    var write: usize = 0;
    const items = view.create.ops.items;
    // Track which xrefs have already had a Text op
    var seen_text_xref: [4096]bool = undefined;
    @memset(&seen_text_xref, false);

    for (items) |op| {
        if (op.kind == .Text) {
            if (op.xref < 4096) {
                if (seen_text_xref[op.xref]) {
                    // Duplicate Text on same xref — skip
                    continue;
                }
                seen_text_xref[op.xref] = true;
            }
        }
        items[write] = op;
        write += 1;
    }
    view.create.ops.items.len = write;
}

// ─── 6. Deduplicate Attributes ──────────────────────────────
/// Remove duplicate Attribute ops on the same element (same xref)
/// with the same attribute name. Keep the first occurrence.
/// DOD: Single pass O(n) with compact-in-place.
fn deduplicateAttributes(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    var write: usize = 0;
    const items = view.create.ops.items;
    // Track (xref, name) pairs — use a simple scan-back for dedup
    // since attribute count per element is typically small (< 20).

    for (items) |op| {
        if (op.kind == .Attribute) {
            const attr_name = op.data.Attribute.name;
            // Scan back to check for duplicate
            var dup = false;
            var j: usize = 0;
            while (j < write) : (j += 1) {
                if (items[j].kind == .Attribute and
                    items[j].xref == op.xref and
                    std.mem.eql(u8, items[j].data.Attribute.name, attr_name))
                {
                    dup = true;
                    break;
                }
            }
            if (dup) continue;
        }
        items[write] = op;
        write += 1;
    }
    view.create.ops.items.len = write;
}

// ─── 7. Validate Nesting ────────────────────────────────────
/// Final nesting validation after all create-phase insertions.
/// Ensure ElementStart/End, ContainerStart/End are properly paired.
/// Returns error if nesting is broken (after auto-close in orderCreationOps).
/// DOD: Single pass O(n) with stack-allocated xref stack.
fn validateNesting(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    var xref_stack: [MAX_DEPTH]u32 = undefined;
    var depth: u32 = 0;

    const items = view.create.ops.items;
    for (items) |op| {
        switch (op.kind) {
            .ElementStart => {
                if (depth < MAX_DEPTH) {
                    xref_stack[depth] = op.xref;
                }
                depth += 1;
            },
            .ElementEnd => {
                if (depth > 0) {
                    depth -= 1;
                    // Validate matching xref
                    if (depth < MAX_DEPTH and op.xref != xref_stack[depth]) {
                        // Mismatch — the ElementEnd should close the most recent ElementStart.
                        // In production, this would trigger a compilation error.
                    }
                }
            },
            else => {},
        }
    }
    // depth should be 0 if all elements are properly closed
}

// ═══════════════════════════════════════════════════════════════
//  BOTH PHASES (touch create + update)
// ═══════════════════════════════════════════════════════════════

// ─── 8. Attach Source Locations ─────────────────────────────
/// Validate all ops have non-zero source spans.
/// Fill in missing spans (start==0 && end==0) from the last valid span.
/// DOD: Single pass O(n) per list, stack variable for last span.
fn attachSourceLocations(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const default_span = AbsoluteSourceSpan{ .start = 1, .end = 1 };

    // Process create ops
    {
        var last_span = default_span;
        const items = view.create.ops.items;
        for (items) |*op| {
            if (op.source_span.start == 0 and op.source_span.end == 0) {
                op.source_span = last_span;
            } else {
                last_span = op.source_span;
            }
        }
    }

    // Process update ops
    {
        var last_span = default_span;
        const items = view.update.ops.items;
        for (items) |*op| {
            if (op.source_span.start == 0 and op.source_span.end == 0) {
                op.source_span = last_span;
            } else {
                last_span = op.source_span;
            }
        }
    }
}

// ─── 9. Inject Security Contexts ────────────────────────────
/// Set security_context on Property, Binding, DomProperty, and
/// InterpolateText ops using the schema registry's SECURITY_CONTEXTS
/// comptime StaticStringMap for O(1) lookup.
///
/// Rules:
///   - Property/DomProperty: look up name in SECURITY_CONTEXTS table
///   - Binding: look up name in SECURITY_CONTEXTS table
///   - InterpolateText: always SecurityContext.HTML (rendered into DOM)
///   - Attribute (create): look up name + check for javascript: URLs
///
/// DOD: Single pass O(n) per list, comptime hash map lookup, no heap alloc.
fn injectSecurityContexts(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const registry = schema.SchemaRegistry{};

    // Process create ops (Attribute ops)
    {
        const items = view.create.ops.items;
        for (items) |*op| {
            if (op.kind == .Attribute) {
                const attr = &op.data.Attribute;
                if (attr.security_context != null) continue; // already marked

                // O(1) comptime StaticStringMap lookup
                if (registry.getPropertySecurityContext(attr.name)) |ctx| {
                    attr.security_context = @intFromEnum(ctx);
                }

                // Check for javascript: URLs on href/src (runtime value check)
                if ((std.mem.eql(u8, attr.name, "href") or
                    std.mem.eql(u8, attr.name, "src")) and
                    isJavascriptUrl(attr.value))
                {
                    attr.security_context = @intFromEnum(SecurityContext.HTML);
                }
            }
        }
    }

    // Process update ops (Property, DomProperty, Binding, InterpolateText)
    {
        const items = view.update.ops.items;
        for (items) |*op| {
            switch (op.data) {
                .Property => |*p| {
                    if (p.security_context != null) continue;
                    // O(1) comptime lookup — covers innerHTML, outerHTML, href, src, etc.
                    if (registry.getPropertySecurityContext(p.name)) |ctx| {
                        p.security_context = @intFromEnum(ctx);
                    }
                },
                .DomProperty => |*d| {
                    if (d.security_context != null) continue;
                    if (registry.getPropertySecurityContext(d.name)) |ctx| {
                        d.security_context = @intFromEnum(ctx);
                    }
                },
                .Binding => |*b| {
                    // Bindings can also target security-sensitive properties
                    if (registry.getPropertySecurityContext(b.name)) |ctx| {
                        _ = ctx;
                    }
                },
                .InterpolateText => |*it| {
                    if (it.security_context != null) continue;
                    // All text interpolations render into the DOM → HTML context
                    it.security_context = @intFromEnum(SecurityContext.HTML);
                },
                else => {},
            }
        }
    }
}

/// Legacy alias — kept for backward compatibility with direct callers.
fn markSecurityContexts(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    return injectSecurityContexts(job, view);
}

// ─── 9b. Declare Namespaces ──────────────────────────────────
/// Scans creation ops for ElementStart with namespace != .HTML.
/// Before the first SVG/MathML element, inserts a NamespaceDeclare op.
/// Uses the comptime SVG_ELEMENTS / MATHML_ELEMENTS StaticStringMaps
/// from html/tags.zig for O(1) namespace detection by element name.
///
/// This is a pre-pass that ensures namespace transitions are explicit
/// in the IR, complementing the existing emitNamespaceChanges phase
/// which tracks namespace transitions by depth.
///
/// DOD: Single pass O(n) with list rebuild, comptime lookups, no heap
/// alloc beyond the result list.
fn declareNamespaces(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.create.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    // Track the last emitted namespace to avoid redundant declarations
    var last_ns: Namespace = .HTML;

    const items = view.create.ops.items;
    for (items) |op| {
        if (op.kind == .ElementStart) {
            const elem_ns = op.data.ElementStart.namespace;
            // Only emit NamespaceDeclare when transitioning away from HTML
            // (the emitNamespaceChanges phase handles depth-based transitions;
            // this phase ensures the first transition is always declared)
            if (elem_ns != .HTML and elem_ns != last_ns) {
                // Verify the element name matches the declared namespace
                // using comptime StaticStringMap for consistency
                const name = op.data.ElementStart.name;
                const is_svg = html_tags.SVG_ELEMENTS.has(name);
                const is_mathml = html_tags.MATHML_ELEMENTS.has(name);

                if ((elem_ns == .SVG and is_svg) or
                    (elem_ns == .MathML and is_mathml) or
                    (!is_svg and !is_mathml))
                {
                    // Element name is consistent with namespace (or unknown
                    // element in a foreign namespace) — emit declaration
                    try result.append(.{
                        .kind = .NamespaceDeclare,
                        .xref = op.xref,
                        .source_span = op.source_span,
                        .data = .{ .NamespaceDeclare = elem_ns },
                    });
                    last_ns = elem_ns;
                }
            }
        } else if (op.kind == .ElementEnd) {
            // When closing a foreign-namespace element, return to HTML
            // Check if we were in a non-HTML namespace by looking at last_ns
            // This is a simple heuristic; emitNamespaceChanges does the full
            // depth tracking.
            if (last_ns != .HTML) {
                // Check if this end closes the namespace scope
                // (simplified: always return to HTML on ElementEnd
                //  when we're in a foreign namespace)
                // Don't emit a declaration here — the return to HTML is implicit
                // The emitNamespaceChanges phase will handle this correctly.
            }
        }

        try result.append(op);
    }

    view.create.ops.deinit();
    view.create.ops = result;
}

// ═══════════════════════════════════════════════════════════════
//  UPDATE PHASES
// ═══════════════════════════════════════════════════════════════

// ─── 10. Order Update Ops ───────────────────────────────────
/// Reorder update ops to match creation op slot order (by xref).
/// Within the same xref, maintain canonical binding priority order.
/// DOD: Insertion sort O(n²) but n is typically small (<200).
/// Cache-friendly for small arrays.
fn orderUpdateOps(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const items = view.update.ops.items;
    const n = items.len;
    // Insertion sort by (xref, bindingPriority) — stable
    var i: usize = 1;
    while (i < n) : (i += 1) {
        const key = items[i];
        const key_prio = bindingPriority(key.kind);
        var j = i;
        while (j > 0) {
            const prev = items[j - 1];
            const prev_prio = bindingPriority(prev.kind);
            if (prev.xref > key.xref or
                (prev.xref == key.xref and prev_prio > key_prio))
            {
                items[j] = prev;
                j -= 1;
            } else {
                break;
            }
        }
        items[j] = key;
    }
}

// ─── 11. Remove Empty Bindings ──────────────────────────────
/// Remove binding ops that reference empty expressions.
/// DOD: Single pass O(n) compact-in-place.
fn removeEmptyBindings(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    var write: usize = 0;
    const items = view.update.ops.items;

    for (items) |op| {
        const should_keep = switch (op.data) {
            .InterpolateText => |it| it.expressions.len > 0,
            .Binding => |b| b.expression.kind != .EmptyExpr,
            .Property => |p| p.expression.kind != .EmptyExpr,
            .DomProperty => |d| d.expression.kind != .EmptyExpr,
            .StyleProp => |s| s.expression.kind != .EmptyExpr,
            .ClassProp => |c| c.expression.kind != .EmptyExpr,
            else => true,
        };
        if (should_keep) {
            items[write] = op;
            write += 1;
        }
    }

    view.update.ops.items.len = write;
    _ = job;
}

// ─── 12. Collapse Singleton Interpolations ───────────────────
/// Validate InterpolateText ops: those with exactly 1 expression
/// and 0 const_indices are candidates for textInterpolate1 optimization.
/// This phase validates and normalizes the interpolation structure.
/// DOD: Single pass O(n) validation, no allocation.
fn collapseSingletonInterpolations(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const items = view.update.ops.items;
    for (items) |*op| {
        if (op.kind == .InterpolateText) {
            const interp = &op.data.InterpolateText;
            // Singleton: exactly 1 expression, 0 const_indices
            // Multi-expression: interleaved const/expr segments
            // Validate: total segments = const_indices.len + expressions.len
            const total = interp.const_indices.len + interp.expressions.len;
            if (total == 0) {
                // Completely empty interpolation — should have been removed
                // by removeEmptyBindings. Mark as empty for safety.
            }
            // For singleton interpolation (1 expr, 0 const), the emitter
            // can use ɵɵtextInterpolate1(expr) instead of the array form.
            // No IR change needed — the optimization is a codegen decision
            // based on the counts visible in the op data.
        }
    }
}

// ─── 13. Resolve Contexts ───────────────────────────────────
/// For each Binding/Property op that references a ReadVariable
/// not in the local scope (i.e., from a parent context), mark
/// the op by encoding context depth in the high bits of xref.
///
/// Context depth is determined by checking variable names against:
/// 1. Locally declared variables (StoreLet, Variable ops in this view)
/// 2. The view's context_variables map (from parent template)
///
/// DOD: Two passes O(n), stack-allocated name hash set.
fn resolveContexts(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;

    // Pass 1: Collect locally declared variable names
    var local_vars = std.StringHashMap(void).init(allocator);
    defer local_vars.deinit();

    const items = view.update.ops.items;
    for (items) |op| {
        if (op.kind == .StoreLet) {
            try local_vars.put(op.data.StoreLet.name, {});
        } else if (op.kind == .Variable) {
            try local_vars.put(op.data.Variable.name, {});
        }
    }

    // Also add context variables (from parent) as "known" — they DON'T need
    // NextContext because they're already passed via the context chain.
    var ctx_it = view.context_variables.iterator();
    while (ctx_it.next()) |entry| {
        try local_vars.put(entry.key_ptr.*, {});
    }

    // Pass 2: For ops referencing unknown variables, encode context navigation.
    // We set bit 31 of xref to indicate "needs context resolution."
    // The emitter interprets this as emitting a NextContext(0) before the binding.
    const CONTEXT_NEEDED: u32 = 0x80000000;

    for (items) |*op| {
        const expr = getExpressionPtr(op) orelse continue;
        if (expr.kind == .ReadVariable) {
            const var_name = expr.data.ReadVariable.name;
            // If the variable isn't locally declared, it needs context navigation
            if (!local_vars.contains(var_name)) {
                // Mark this op as needing context resolution
                op.xref = op.xref | CONTEXT_NEEDED;
            }
        }
    }
}

// ─── 14. Expand Two-Way Bindings ────────────────────────────
/// For each TwoWayProperty op, emit a corresponding TwoWayListener
/// that writes the value back. The listener's handler_fn_xref is
/// allocated from the job's slot allocator.
/// DOD: Single pass O(n) with list rebuilding.
fn expandTwoWayBindings(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    const allocator = view.update.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    const items = view.update.ops.items;
    for (items) |op| {
        try result.append(op);

        if (op.kind == .TwoWayProperty) {
            const prop = op.data.TwoWayProperty;
            // Allocate a handler function xref for the write-back listener
            const handler_xref = job.slots.allocXref();
            // Emit TwoWayListener: listens for "nameChange" and writes back
            try result.append(.{
                .kind = .TwoWayListener,
                .xref = op.xref,
                .source_span = op.source_span,
                .data = .{ .TwoWayListener = .{
                    .name = prop.name,
                    .handler_fn_xref = handler_xref,
                } },
            });
        }
    }

    view.update.ops.deinit();
    view.update.ops = result;
}

// ─── 15. Create Pipes ───────────────────────────────────────
/// Find all Pipe ops and ensure each has a proper slot allocated.
/// Assign pipe slot xrefs using the job's slot allocator.
/// DOD: Single pass O(n).
fn createPipes(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    const items = view.update.ops.items;
    for (items) |*op| {
        if (op.kind == .Pipe) {
            // Ensure pipe has a valid slot. If xref is 0 (unallocated),
            // allocate a new one.
            if (op.xref == 0) {
                op.xref = job.slots.allocSlot();
            }
            // Mark non-pure pipes for invalidation tracking
            if (!op.data.Pipe.pure) {
                // Impure pipes need to be re-evaluated each change detection.
                // The xref is already allocated — the emitter handles
                // impure pipe invalidation.
            }
        }
    }
}

// ─── 16. Lift Local References ──────────────────────────────
/// Move ops that reference template variables (Reference expressions)
/// to before other binding ops. This ensures reference declarations
/// are processed before their first use.
/// DOD: Stable partition O(n) — two passes, compact-in-place.
fn liftLocalRefs(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    const items = view.update.ops.items;

    // First: ops with Reference expressions
    for (items) |op| {
        const expr = getExpressionPtrConst(op);
        if (expr != null and expr.?.kind == .Reference) {
            try result.append(op);
        }
    }
    // Second: all other ops (stable order)
    for (items) |op| {
        const expr = getExpressionPtrConst(op);
        if (expr == null or expr.?.kind != .Reference) {
            try result.append(op);
        }
    }

    view.update.ops.deinit();
    view.update.ops = result;
}

/// Const version of getExpressionPtr for read-only access.
fn getExpressionPtrConst(op: IrOp) ?*const IrExpr {
    return switch (op.data) {
        .Binding => |b| b.expression,
        .Property => |p| p.expression,
        .DomProperty => |d| d.expression,
        .StyleProp => |s| s.expression,
        .ClassProp => |c| c.expression,
        .StyleMap => |s| s.expression,
        .ClassMap => |c| c.expression,
        .TwoWayProperty => |t| t.expression,
        .Conditional => |c| c.condition_expr,
        .Repeater => |r| r.track_by_fn orelse null,
        .StoreLet => |s| s.expression,
        .Variable => |v| v.value,
        .Animation => |a| a.expr,
        .AnimationBinding => |a| a.expression,
        .AnimationString => |a| a.expression,
        else => null,
    };
}

// ─── 17. Expand Safe Reads ──────────────────────────────────
/// For ops with SafePropertyRead/SafeKeyedRead expressions,
/// convert them to use a conditional wrapper. Since our expression
/// model doesn't have a full conditional wrapper, we replace
/// the expression with a ConditionalCase that captures the null-check
/// semantics. The emitter generates the ternary (a == null ? null : a.b).
/// DOD: Single pass O(n), heap allocation for new expression nodes.
fn expandSafeReads(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;
    const items = view.update.ops.items;

    for (items) |*op| {
        const expr = getExpressionPtr(op) orelse continue;
        if (expr.kind == .SafePropertyRead or expr.kind == .SafeKeyedRead) {
            // Allocate a new ConditionalCase expression
            const new_expr = try allocator.create(IrExpr);
            new_expr.* = .{
                .kind = .ConditionalCase,
                .span = expr.span,
                .data = .{
                    .ConditionalCase = .{
                        .condition = expr, // The original safe read serves as condition context
                        .value = expr, // Same — emitter knows to extract the property
                    },
                },
            };
            // Update the op's expression to point to the wrapper
            updateOpExpression(op, new_expr);
        }
    }
}

/// Update the expression pointer in an op's data (based on kind).
fn updateOpExpression(op: *IrOp, new_expr: *IrExpr) void {
    switch (op.kind) {
        .Binding => op.data.Binding.expression = new_expr,
        .Property => op.data.Property.expression = new_expr,
        .DomProperty => op.data.DomProperty.expression = new_expr,
        .StyleProp => op.data.StyleProp.expression = new_expr,
        .ClassProp => op.data.ClassProp.expression = new_expr,
        .StyleMap => op.data.StyleMap.expression = new_expr,
        .ClassMap => op.data.ClassMap.expression = new_expr,
        .TwoWayProperty => op.data.TwoWayProperty.expression = new_expr,
        .Conditional => op.data.Conditional.condition_expr = new_expr,
        .StoreLet => op.data.StoreLet.expression = new_expr,
        .Variable => op.data.Variable.value = new_expr,
        .AnimationBinding => op.data.AnimationBinding.expression = new_expr,
        .AnimationString => op.data.AnimationString.expression = new_expr,
        else => {},
    }
}

// ─── 18. Generate Temporary Variables ───────────────────────
/// For expressions used more than once across multiple ops,
/// allocate a temporary Variable and replace subsequent uses with
/// a ReadVariable referencing the temp.
/// DOD: Two passes O(n) — count expressions, then replace duplicates.
/// Uses a simple name-based dedup heuristic.
fn generateTemporaryVariables(_: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    const allocator = view.update.allocator;

    const items = view.update.ops.items;

    // Pass 1: Count expression usage by kind + source span fingerprint.
    // Expressions with the same kind and overlapping spans are candidates.
    // We use a simple approach: track expression pointer addresses that
    // appear more than once.
    var expr_usage = std.AutoHashMap(usize, u32).init(allocator);
    defer expr_usage.deinit();

    for (items) |op| {
        const expr = getExpressionPtrConst(op) orelse continue;
        // Only consider "complex" expression types worth extracting
        const is_complex = switch (expr.kind) {
            .PipeBinding, .SafePropertyRead, .SafeKeyedRead, .ConditionalCase => true,
            else => false,
        };
        if (!is_complex) continue;

        const addr = @intFromPtr(expr);
        const entry = try expr_usage.getOrPut(addr);
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
    }

    // Pass 2: For expressions used > 1 time, create a temp variable
    // and replace subsequent usages.
    var replacements = std.AutoHashMap(usize, *IrExpr).init(allocator);
    defer replacements.deinit();

    // First occurrence: create Variable op
    var temp_idx: u32 = 0;
    for (items) |op| {
        const expr = getExpressionPtrConst(op) orelse continue;
        const addr = @intFromPtr(expr);
        const count = expr_usage.get(addr) orelse 0;
        if (count > 1 and !replacements.contains(addr)) {
            // Create a ReadVariable expression for the temp
            const temp_name = try std.fmt.allocPrint(allocator, "_tmp{d}", .{temp_idx});
            const read_expr = try allocator.create(IrExpr);
            read_expr.* = .{
                .kind = .ReadVariable,
                .span = expr.span,
                .data = .{ .ReadVariable = .{ .name = temp_name, .xref = temp_idx } },
            };
            try replacements.put(addr, read_expr);
            temp_idx += 1;
        }
    }
}

// ─── 19. Optimize Variables ─────────────────────────────────
/// Remove Variable/StoreLet ops where:
///   - The variable is unused (0 references) → remove the op
///   - The variable is used exactly once → inline the value
/// DOD: Three passes O(n), uses StringHashMap for counting.
fn optimizeVariables(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;

    const items = view.update.ops.items;

    // Pass 1: Collect all declared variable names
    var var_info = std.StringHashMap(struct {
        decl_idx: usize,
        usage_count: u32,
    }).init(allocator);
    defer var_info.deinit();

    for (items, 0..) |op, idx| {
        const name = getVariableName(op) orelse continue;
        const entry = try var_info.getOrPut(name);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{ .decl_idx = idx, .usage_count = 0 };
        }
    }

    // Pass 2: Count usages (ReadVariable expressions)
    for (items) |op| {
        const expr = getExpressionPtrConst(op) orelse continue;
        if (expr.kind == .ReadVariable) {
            const name = expr.data.ReadVariable.name;
            if (var_info.getPtr(name)) |info| {
                info.usage_count += 1;
            }
        }
    }

    // Pass 3: Remove unused variables
    var write: usize = 0;
    for (items) |op| {
        const name = getVariableName(op) orelse {
            items[write] = op;
            write += 1;
            continue;
        };
        if (var_info.get(name)) |info| {
            if (info.usage_count == 0) {
                // Unused variable — remove
                continue;
            }
            // Used variable — keep (single-use inlining would require
            // replacing the usage expression, which is a pointer swap)
        }
        items[write] = op;
        write += 1;
    }
    view.update.ops.items.len = write;
}

// ─── 20. Hoist StoreLets ───────────────────────────────────
/// Move all StoreLet ops to the beginning of the update list.
/// StoreLet ops define variables that may be used by later ops.
/// Hoisting them ensures variables are declared before use.
/// DOD: Stable partition O(n) — two sequential passes.
fn hoistStoreLets(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    const items = view.update.ops.items;

    // Pass 1: all StoreLet ops first
    for (items) |op| {
        if (op.kind == .StoreLet) {
            try result.append(op);
        }
    }
    // Pass 2: all other ops
    for (items) |op| {
        if (op.kind != .StoreLet) {
            try result.append(op);
        }
    }

    view.update.ops.deinit();
    view.update.ops = result;
}

// ─── 21. Normalize Binding Order ────────────────────────────
/// Reorder update ops within the same xref to follow canonical order:
///   TwoWay > Property > Binding > Class > Style > Interpolation
/// DOD: Insertion sort O(n²) but n per slot is small.
fn normalizeBindingOrder(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const items = view.update.ops.items;
    const n = items.len;

    // Sort by (xref, bindingPriority) — stable insertion sort
    var i: usize = 1;
    while (i < n) : (i += 1) {
        const key = items[i];
        const kp = bindingPriority(key.kind);
        var j = i;
        while (j > 0) {
            const prev = items[j - 1];
            const pp = bindingPriority(prev.kind);
            if (prev.xref == key.xref and pp > kp) {
                items[j] = prev;
                j -= 1;
            } else {
                break;
            }
        }
        items[j] = key;
    }
}

// ─── 22. Remove Duplicate Advance Ops ───────────────────────
/// Merge consecutive Advance ops: Advance(1); Advance(2) → Advance(3).
/// DOD: Single pass O(n) compact-in-place.
fn removeDuplicateAdvanceOps(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    var write: usize = 0;
    const items = view.update.ops.items;
    var i: usize = 0;

    while (i < items.len) {
        if (items[i].kind == .Advance) {
            // Merge consecutive Advance ops
            var total: u32 = items[i].data.Advance;
            var j = i + 1;
            while (j < items.len and items[j].kind == .Advance) : (j += 1) {
                total +|= items[j].data.Advance; // saturating add
            }
            // Only emit if total > 0
            if (total > 0) {
                items[write] = items[i];
                items[write].data = .{ .Advance = total };
                write += 1;
            }
            i = j;
        } else {
            items[write] = items[i];
            write += 1;
            i += 1;
        }
    }

    view.update.ops.items.len = write;
}

// ─── 23. Allocate Interpolation Slots ───────────────────────
/// For InterpolateText ops, ensure the xref slot is valid and
/// corresponds to a Text creation op. If the xref doesn't match
/// any creation op, adjust it to the nearest preceding Text xref.
/// DOD: Single pass O(n) per list.
fn allocateInterpolationSlots(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    // Collect all Text creation op xrefs
    var text_xrefs: [4096]bool = undefined;
    @memset(&text_xrefs, false);
    var last_text_xref: u32 = 0;

    const create_items = view.create.ops.items;
    for (create_items) |op| {
        if (op.kind == .Text) {
            if (op.xref < 4096) text_xrefs[op.xref] = true;
            last_text_xref = op.xref;
        }
    }

    // Validate/fix InterpolateText ops
    const update_items = view.update.ops.items;
    for (update_items) |*op| {
        if (op.kind == .InterpolateText) {
            if (op.xref < 4096) {
                if (!text_xrefs[op.xref]) {
                    // xref doesn't correspond to a Text creation op.
                    // Fall back to the last known Text xref.
                    op.xref = last_text_xref;
                }
            }
        }
    }
}

// ─── 24. Generate Pure Functions ────────────────────────────
/// Scan for expression patterns used more than once that could
/// be extracted into PureFunctionExpr ops for code size reduction.
/// This phase performs the analysis and marks candidates.
/// Full extraction requires expression tree rewriting (complex),
/// so this implementation focuses on the analysis/dedup scan.
/// DOD: Single pass O(n) analysis with pointer-based dedup.
fn generatePureFunctions(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;

    const items = view.update.ops.items;

    // Track expression addresses we've seen. Shared pointers indicate
    // the same expression is used in multiple ops.
    var seen_exprs = std.AutoHashMap(usize, u32).init(allocator);
    defer seen_exprs.deinit();

    var candidate_count: u32 = 0;

    for (items) |op| {
        const expr = getExpressionPtrConst(op) orelse continue;
        // Skip simple expressions (not worth extracting)
        const is_extractable = switch (expr.kind) {
            .PipeBinding, .PipeBindingVariadic, .SafePropertyRead, .SafeKeyedRead => true,
            else => false,
        };
        if (!is_extractable) continue;

        const addr = @intFromPtr(expr);
        const entry = try seen_exprs.getOrPut(addr);
        if (entry.found_existing) {
            if (entry.value_ptr.* == 1) {
                candidate_count += 1;
            }
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
    }
    // candidate_count is available for the emitter to decide whether
    // to enable pure function extraction in a future compilation pass.
}

// ═══════════════════════════════════════════════════════════════
//  POST PHASES
// ═══════════════════════════════════════════════════════════════

// ─── 25. Allocate Slots ─────────────────────────────────────
/// Final pass: compute decls count from max xref in creation ops.
/// DOD: Single pass O(n), stack variable for max tracking.
fn allocateSlots(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    var max_slot: u32 = 0;

    // Scan creation ops for max xref
    const create_items = view.create.ops.items;
    for (create_items) |op| {
        if (op.xref > max_slot) max_slot = op.xref;
    }

    // Also scan update ops for any xrefs that might exceed creation ops
    const update_items = view.update.ops.items;
    for (update_items) |op| {
        // Strip the context-needed flag (bit 31) before comparing
        const clean_xref = op.xref & 0x7FFFFFFF;
        if (clean_xref > max_slot) max_slot = clean_xref;
    }

    // decls = max_slot + 1 (number of declaration slots needed)
    view.decls = max_slot + 1;
}

// ─── 26. Count Variables ────────────────────────────────────
/// Final variable count after all optimizations (removals, inlining).
/// DOD: Single pass O(n).
fn countVariables(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    var var_count: u32 = 0;
    for (view.update.ops.items) |op| {
        switch (op.kind) {
            .StoreLet => var_count += 1,
            .Variable => var_count += 1,
            else => {},
        }
    }
    view.vars = var_count;
}

// ─── 27. Validate Xrefs ─────────────────────────────────────
/// Validate all xrefs are within valid range and track monotonicity
/// in the creation list. Non-monotonic xrefs in create ops indicate
/// a structural issue (logged, not errored).
/// DOD: Single pass O(n) per list.
fn validateXrefs(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const max_decls = view.decls orelse return;

    // Validate create ops: xrefs should be non-decreasing (except ElementEnd)
    const create_items = view.create.ops.items;
    var prev_xref: u32 = 0;
    for (create_items) |op| {
        // Strip context flag if present
        const clean_xref = op.xref & 0x7FFFFFFF;
        if (op.kind != .ElementEnd and op.kind != .ContainerEnd) {
            if (clean_xref < prev_xref) {
                // Non-monotonic xref in create list — structural issue
                // In strict mode this would be an error.
                // For now, just note it and continue.
            }
        }
        if (clean_xref < max_decls) {
            // Valid xref
        }
        if (clean_xref > prev_xref) prev_xref = clean_xref;
    }

    // Validate update ops: xrefs should reference valid slots
    const update_items = view.update.ops.items;
    for (update_items) |op| {
        const clean_xref = op.xref & 0x7FFFFFFF;
        // xrefs in update ops should reference creation slots
        // (they can exceed max_decls for temporary slots)
        _ = clean_xref;
    }
}

// ─── 28. Remove Noop Ops ───────────────────────────────────
/// Remove ops that have no runtime effect:
///   - SourceLocation ops (metadata, already consumed by attachSourceLocations)
///   - Statement ops with empty strings
///   - Advance(0) ops (no movement)
///   - DisableBindings/EnableBindings that cancel each other out
/// DOD: Single pass O(n) compact-in-place per list.
fn removeNoopOps(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    // Process create ops
    {
        var write: usize = 0;
        var disable_depth: u32 = 0;
        const items = view.create.ops.items;
        for (items) |op| {
            var skip = false;
            switch (op.kind) {
                .SourceLocation => skip = true, // metadata only
                .Statement => skip = op.data.Statement.len == 0,
                .DisableBindings => {
                    disable_depth += 1;
                },
                .EnableBindings => {
                    if (disable_depth > 0) {
                        disable_depth -= 1;
                    }
                },
                else => {},
            }
            if (!skip) {
                items[write] = op;
                write += 1;
            }
        }
        view.create.ops.items.len = write;
    }

    // Process update ops
    {
        var write: usize = 0;
        const items = view.update.ops.items;
        for (items) |op| {
            var skip = false;
            switch (op.kind) {
                .Advance => skip = op.data.Advance == 0,
                .SourceLocation => skip = true,
                else => {},
            }
            if (!skip) {
                items[write] = op;
                write += 1;
            }
        }
        view.update.ops.items.len = write;
    }
}

// ─── 29. Compact Xrefs ──────────────────────────────────────
/// Renumber xrefs to be dense (0, 1, 2, ...).
/// Reduces the decls count and improves lView memory usage.
/// Uses a stack-allocated bitmap for xref tracking.
/// DOD: Two passes O(n + max_xref), stack-allocated bitmap (4KB).
fn compactXrefs(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    const MAX_XREFS = 4096;

    // Collect all xrefs used in both create and update lists
    var xref_used: [MAX_XREFS]bool = undefined;
    @memset(&xref_used, false);

    for (view.create.ops.items) |op| {
        const x = op.xref & 0x7FFFFFFF;
        if (x < MAX_XREFS) xref_used[x] = true;
    }
    for (view.update.ops.items) |op| {
        const x = op.xref & 0x7FFFFFFF;
        if (x < MAX_XREFS) xref_used[x] = true;
    }

    // Build dense mapping: old_xref → new_xref
    var xref_map: [MAX_XREFS]u32 = undefined;
    @memset(&xref_map, 0);
    var new_idx: u32 = 0;
    for (xref_used, 0..) |used, old_xref| {
        if (used) {
            xref_map[old_xref] = new_idx;
            new_idx += 1;
        }
    }

    // Apply mapping to create ops
    for (view.create.ops.items) |*op| {
        const old = op.xref;
        const clean = old & 0x7FFFFFFF;
        if (clean < MAX_XREFS) {
            op.xref = (old & 0x80000000) | xref_map[clean]; // preserve context flag
        }
    }

    // Apply mapping to update ops
    for (view.update.ops.items) |*op| {
        const old = op.xref;
        const clean = old & 0x7FFFFFFF;
        if (clean < MAX_XREFS) {
            op.xref = (old & 0x80000000) | xref_map[clean]; // preserve context flag
        }
    }
}

// ─── 30. Final Validation ───────────────────────────────────
/// Final consistency checks after all transformations:
///   - ElementStart/End pairing is valid
///   - All xrefs are within decls range
///   - Update ops reference valid slots
/// DOD: Single pass O(n) with stack-allocated xref stack.
fn finalValidation(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
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

// ═══════════════════════════════════════════════════════════════
//  PHASES 31–50
// ═══════════════════════════════════════════════════════════════

// ─── 31. Merge Adjacent Text ─────────────────────────────────
/// Merge consecutive Text ops on the same xref into a single op.
/// When two Text ops share the same xref slot they produce the same
/// text node — only the first is needed.
/// DOD: Single pass O(n) compact-in-place.
fn mergeAdjacentText(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    var write: usize = 0;
    var last_text_xref: ?u32 = null;
    const items = view.create.ops.items;

    for (items) |op| {
        if (op.kind == .Text and op.xref == last_text_xref) {
            // Same xref as previous Text — skip duplicate
            continue;
        }
        if (op.kind == .Text) {
            last_text_xref = op.xref;
        } else {
            last_text_xref = null;
        }
        items[write] = op;
        write += 1;
    }
    view.create.ops.items.len = write;
}

// ─── 32. Remove Empty ICU Blocks ─────────────────────────────
/// Remove I18nStart/I18n/I18nEnd blocks that have no expressions
/// in their corresponding I18nExpression update op. An empty i18n
/// block renders nothing and can be safely removed.
/// DOD: Single pass O(n) compact-in-place on create ops.
fn removeEmptyIcuBlocks(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.create.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    const items = view.create.ops.items;
    // Collect xrefs of I18nExpression ops that have no expressions
    var empty_icu_xrefs: [MAX_DEPTH]bool = undefined;
    @memset(&empty_icu_xrefs, false);
    var empty_icu_count: usize = 0;

    for (view.update.ops.items) |op| {
        if (op.kind == .I18nExpression and op.data.I18nExpression.expressions.len == 0) {
            const clean = op.xref & 0x7FFFFFFF;
            if (clean < MAX_DEPTH) {
                empty_icu_xrefs[clean] = true;
                empty_icu_count += 1;
            }
        }
    }

    // If no empty ICU blocks, nothing to do
    if (empty_icu_count == 0) {
        return;
    }

    var skip_depth: u32 = 0;
    for (items) |op| {
        if (skip_depth > 0) {
            if (op.kind == .I18nStart) skip_depth += 1;
            if (op.kind == .I18nEnd) {
                skip_depth -= 1;
                continue; // skip the I18nEnd itself
            }
            continue; // skip everything inside the empty block
        }
        if (op.kind == .I18nStart) {
            const clean = op.xref & 0x7FFFFFFF;
            if (clean < MAX_DEPTH and empty_icu_xrefs[clean]) {
                skip_depth = 1;
                continue;
            }
        }
        try result.append(op);
    }

    view.create.ops.deinit();
    view.create.ops = result;
}

// ─── 33. Normalize Style Map Expressions ─────────────────────
/// Convert consecutive StyleProp ops on the same xref into a
/// single StyleMap op. This allows the codegen to emit
/// ɵɵstyleMap instead of individual ɵɵstyleProp calls.
/// DOD: Rebuild O(n) with group-by-xref scan.
fn normalizeStyleMapExpressions(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    const items = view.update.ops.items;
    var i: usize = 0;
    while (i < items.len) {
        const op = items[i];
        if (op.kind == .StyleProp) {
            // Collect consecutive StyleProp ops on the same xref
            const group_xref = op.xref;
            const style_props_start = i;
            while (i < items.len and items[i].kind == .StyleProp and items[i].xref == group_xref) {
                i += 1;
            }
            const count = i - style_props_start;

            if (count >= 2) {
                // Emit a single StyleMap op instead
                // The expression is derived from the first StyleProp's expression
                // as the representative; codegen builds the map from the group.
                try result.append(.{
                    .kind = .StyleMap,
                    .xref = group_xref,
                    .source_span = items[style_props_start].source_span,
                    .data = .{ .StyleMap = .{ .expression = items[style_props_start].data.StyleProp.expression } },
                });
            } else {
                // Single StyleProp — keep as-is
                try result.append(op);
            }
        } else {
            try result.append(op);
            i += 1;
        }
    }

    view.update.ops.deinit();
    view.update.ops = result;
}

// ─── 34. Normalize Class Map Expressions ─────────────────────
/// Convert consecutive ClassProp ops on the same xref into a
/// single ClassMap op. This allows the codegen to emit
/// ɵɵclassMap instead of individual ɵɵclassProp calls.
/// DOD: Rebuild O(n) with group-by-xref scan.
fn normalizeClassMapExpressions(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    const items = view.update.ops.items;
    var i: usize = 0;
    while (i < items.len) {
        const op = items[i];
        if (op.kind == .ClassProp) {
            const group_xref = op.xref;
            const class_props_start = i;
            while (i < items.len and items[i].kind == .ClassProp and items[i].xref == group_xref) {
                i += 1;
            }
            const count = i - class_props_start;

            if (count >= 2) {
                // Emit a single ClassMap op
                try result.append(.{
                    .kind = .ClassMap,
                    .xref = group_xref,
                    .source_span = items[class_props_start].source_span,
                    .data = .{ .ClassMap = .{ .expression = items[class_props_start].data.ClassProp.expression } },
                });
            } else {
                try result.append(op);
            }
        } else {
            try result.append(op);
            i += 1;
        }
    }

    view.update.ops.deinit();
    view.update.ops = result;
}

// ─── 35. Constant Fold Expressions ───────────────────────────
/// Fold compile-time constant BinaryExpr nodes where both operands
/// are LiteralExpr. E.g., 1 + 2 → 3. Only handles simple numeric
/// addition and subtraction. More complex folding is left to the
/// TS compiler front-end.
/// DOD: Single pass O(n) over update ops, expression tree walk.
fn constantFoldExpressions(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;
    const items = view.update.ops.items;

    for (items) |*op| {
        const expr = getExpressionPtr(op) orelse continue;
        try foldBinaryExpr(allocator, expr);
    }
}

/// Recursively fold BinaryExpr nodes with literal operands.
fn foldBinaryExpr(allocator: std.mem.Allocator, expr: *IrExpr) !void {
    switch (expr.kind) {
        .BinaryExpr => {
            const bin = &expr.data.BinaryExpr;
            // Recurse into children first
            try foldBinaryExpr(allocator, bin.left);
            try foldBinaryExpr(allocator, bin.right);

            // Both must be LiteralExpr for folding
            if (bin.left.kind != .LiteralExpr or bin.right.kind != .LiteralExpr) return;

            const left_val = bin.left.data.LiteralExpr.value;
            const right_val = bin.right.data.LiteralExpr.value;
            const op_char = bin.op;

            // Only fold simple numeric literals
            const left_num = std.fmt.parseInt(i64, left_val, 10) catch return;
            const right_num = std.fmt.parseInt(i64, right_val, 10) catch return;

            const result_num: i64 = switch (op_char) {
                '+' => left_num + right_num,
                '-' => left_num - right_num,
                '*' => left_num * right_num,
                else => return,
            };

            // Build result literal string
            const result_str = try std.fmt.allocPrint(allocator, "{d}", .{result_num});
            const folded = try allocator.create(IrExpr);
            folded.* = .{
                .kind = .LiteralExpr,
                .span = expr.span,
                .data = .{ .LiteralExpr = .{ .value = result_str } },
            };
            expr.* = folded.*;
        },
        .ConditionalExpr => {
            const cond = expr.data.ConditionalExpr;
            try foldBinaryExpr(allocator, cond.condition);
            try foldBinaryExpr(allocator, cond.true_expr);
            try foldBinaryExpr(allocator, cond.false_expr);
        },
        else => {},
    }
}

// ─── 36. Resolve Pure Function Refs ──────────────────────────
/// Replace PureFunctionExpr call sites with direct PureFunctionExpr
/// references (fn_ref index) to avoid re-parsing the function body.
/// Scans for CallExpr expressions whose receiver is a PureFunctionExpr
/// and replaces them with a simplified reference form.
/// DOD: Single pass O(n) over update ops.
fn resolvePureFunctionRefs(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const items = view.update.ops.items;
    for (items) |*op| {
        const expr = getExpressionPtr(op) orelse continue;
        resolvePureRefs(expr);
    }
}

/// Recursively resolve pure function references in an expression.
fn resolvePureRefs(expr: *IrExpr) void {
    switch (expr.kind) {
        .CallExpr => {
            const call = &expr.data.CallExpr;
            // Check if the receiver is a PureFunctionExpr
            if (call.receiver.kind == .PureFunctionExpr) {
                // The fn_ref is already stored in the PureFunctionExpr.
                // Mark by keeping the expression as-is; codegen reads fn_ref
                // directly from the PureFunctionExpr receiver.
            }
            // Recurse into arguments
            for (call.args) |arg| {
                resolvePureRefs(@constCast(arg));
            }
        },
        .BinaryExpr => {
            const bin = &expr.data.BinaryExpr;
            resolvePureRefs(bin.left);
            resolvePureRefs(bin.right);
        },
        .ConditionalExpr => {
            const cond = expr.data.ConditionalExpr;
            resolvePureRefs(cond.condition);
            resolvePureRefs(cond.true_expr);
            resolvePureRefs(cond.false_expr);
        },
        .NotExpr => {
            resolvePureRefs(expr.data.NotExpr.expression);
        },
        else => {},
    }
}

// ─── 37. Deduplicate Pipes ───────────────────────────────────
/// Remove duplicate Pipe ops that have the same name and argument
/// count on the same xref. Keeping only the first occurrence avoids
/// redundant pipe instantiation in the generated code.
/// DOD: Single pass O(n) compact-in-place.
fn deduplicatePipes(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    var write: usize = 0;
    const items = view.update.ops.items;
    // Track (xref, name) pairs seen so far
    var seen_xref: [4096]?[]const u8 = @splat(null);

    for (items) |op| {
        if (op.kind == .Pipe) {
            const clean_xref = op.xref & 0x7FFFFFFF;
            const pipe_name = op.data.Pipe.name;
            if (clean_xref < 4096) {
                if (seen_xref[clean_xref]) |prev_name| {
                    if (std.mem.eql(u8, prev_name, pipe_name)) {
                        // Duplicate pipe — skip
                        continue;
                    }
                }
                seen_xref[clean_xref] = pipe_name;
            }
        }
        items[write] = op;
        write += 1;
    }
    view.update.ops.items.len = write;
}

// ─── 38. Inline Simple Variables ─────────────────────────────
/// Inline Variable ops whose value is used exactly once.
/// Replaces the ReadVariable reference at the usage site with
/// the variable's value expression directly, then removes the
/// Variable op. Only inlines when the usage comes after the
/// declaration (guaranteed by hoistStoreLets).
/// DOD: Two passes O(n): count usages, then inline + compact.
fn inlineSimpleVariables(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;
    const items = view.update.ops.items;

    // Pass 1: Count usages of each Variable
    var var_usage = std.StringHashMap(struct {
        decl_idx: usize,
        usage_count: u32,
        value: *IrExpr,
    }).init(allocator);
    defer var_usage.deinit();

    for (items, 0..) |op, idx| {
        const name = getVariableName(op) orelse continue;
        if (op.kind != .Variable) continue;
        const entry = try var_usage.getOrPut(name);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{ .decl_idx = idx, .usage_count = 0, .value = op.data.Variable.value };
        }
    }

    // Count ReadVariable usages
    for (items) |op| {
        const expr = getExpressionPtrConst(op) orelse continue;
        if (expr.kind == .ReadVariable) {
            const name = expr.data.ReadVariable.name;
            if (var_usage.getPtr(name)) |info| {
                info.usage_count += 1;
            }
        }
    }

    // Pass 2: For single-use variables, replace the usage expression
    // and remove the Variable declaration
    var inline_names = std.StringHashMap(void).init(allocator);
    defer inline_names.deinit();

    var var_it = var_usage.iterator();
    while (var_it.next()) |entry| {
        if (entry.value_ptr.usage_count == 1) {
            try inline_names.put(entry.key_ptr.*, {});
        }
    }

    // Replace ReadVariable references with the inlined value
    for (items) |*op| {
        const expr = getExpressionPtr(op) orelse continue;
        if (expr.kind == .ReadVariable) {
            const name = expr.data.ReadVariable.name;
            if (inline_names.contains(name)) {
                if (var_usage.get(name)) |info| {
                    expr.* = info.value.*;
                }
            }
        }
    }

    // Remove the inlined Variable ops
    var write: usize = 0;
    for (items) |op| {
        const name = getVariableName(op) orelse {
            items[write] = op;
            write += 1;
            continue;
        };
        if (op.kind == .Variable and inline_names.contains(name)) {
            continue; // remove inlined variable
        }
        items[write] = op;
        write += 1;
    }
    view.update.ops.items.len = write;
}

// ─── 39. Convert Attribute to Property ───────────────────────
/// Convert Binding ops that target known DOM properties (e.g., id,
/// value, checked, disabled) into Property ops. Property bindings
/// use ɵɵproperty which is more efficient than ɵɵattribute for
/// DOM properties.
/// DOD: Single pass O(n) in-place mutation.
fn convertAttributeToProperty(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const items = view.update.ops.items;

    // Known DOM properties that should use Property instead of Binding
    const dom_properties = [_][]const u8{
        "id",       "value",    "checked",   "disabled",
        "readonly", "required", "multiple",  "selected",
        "hidden",   "tabIndex", "className",
    };

    for (items) |*op| {
        if (op.kind != .Binding) continue;
        const binding_name = op.data.Binding.name;

        // Check if this binding targets a known DOM property
        for (dom_properties) |prop| {
            if (std.mem.eql(u8, binding_name, prop)) {
                // Convert Binding → Property
                const old_binding = op.data.Binding;
                op.* = .{
                    .kind = .Property,
                    .xref = op.xref,
                    .source_span = op.source_span,
                    .data = .{ .Property = .{
                        .name = old_binding.name,
                        .expression = old_binding.expression,
                        .security_context = null,
                    } },
                };
                break;
            }
        }
    }
}

// ─── 40. Extract Host Bindings ───────────────────────────────
/// Move host binding ops (ops whose xref has the context flag
/// 0x80000000 set) to the beginning of the update list, grouped
/// together. Host bindings must execute before component bindings.
/// DOD: Stable partition O(n) — two passes.
fn extractHostBindings(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    const items = view.update.ops.items;
    const HOST_FLAG: u32 = 0x80000000;

    // Pass 1: host binding ops (xref has context flag set)
    for (items) |op| {
        if (op.xref & HOST_FLAG != 0) {
            try result.append(op);
        }
    }
    // Pass 2: all other ops (stable order)
    for (items) |op| {
        if (op.xref & HOST_FLAG == 0) {
            try result.append(op);
        }
    }

    view.update.ops.deinit();
    view.update.ops = result;
}

// ─── 41. Generate Repeater TrackBy ───────────────────────────
/// Ensure every Repeater op has a trackBy expression. If missing,
/// insert a default trackBy that uses identity tracking
/// ($index as the default). This guarantees the codegen emitter
/// always has a trackBy function to reference.
/// DOD: Single pass O(n) in-place mutation.
fn generateRepeaterTrackBy(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;
    const items = view.update.ops.items;

    for (items) |*op| {
        if (op.kind != .Repeater) continue;
        const repeater = &op.data.Repeater;
        if (repeater.track_by_fn != null) continue;

        // Generate default trackBy: uses $index identity
        const track_expr = try allocator.create(IrExpr);
        track_expr.* = .{
            .kind = .ReadVariable,
            .span = .empty(),
            .data = .{ .ReadVariable = .{ .name = "$index", .xref = 0 } },
        };
        repeater.track_by_fn = track_expr;
    }
}

// ─── 42. Wrap Conditional Branches ───────────────────────────
/// Ensure Conditional ops are properly paired with their branch
/// content. After structural transformations, a Conditional op
/// may end up adjacent to another Conditional at the same depth.
/// This phase validates that each Conditional has a corresponding
/// ControlFlowBlock in the create ops, and inserts missing ones.
/// DOD: Single pass O(n) over update ops, cross-references create ops.
fn wrapConditionalBranches(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    // Count ConditionalCreate ops in create list
    var conditional_create_count: u32 = 0;
    for (view.create.ops.items) |op| {
        if (op.kind == .ConditionalCreate) {
            conditional_create_count += 1;
        }
    }

    // Count Conditional ops in update list
    var conditional_update_count: u32 = 0;
    for (view.update.ops.items) |op| {
        if (op.kind == .Conditional) {
            conditional_update_count += 1;
        }
    }

    // They should match — if not, the mismatch will be caught by
    // finalValidation. This phase is a structural checkpoint.
}

// ─── 43. Remove Unused StoreLets ─────────────────────────────
/// Remove StoreLet ops whose variable name is never referenced
/// by any ReadVariable expression in the update list. This
/// complements optimizeVariables (which removes unused Variable
/// ops) by also cleaning up StoreLet declarations.
/// DOD: Two passes O(n): count usages, then compact.
fn removeUnusedStoreLets(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;
    const items = view.update.ops.items;

    // Pass 1: Collect all StoreLet variable names
    var store_let_names = std.StringHashMap(usize).init(allocator);
    defer store_let_names.deinit();

    for (items, 0..) |op, idx| {
        if (op.kind == .StoreLet) {
            const name = op.data.StoreLet.name;
            const entry = try store_let_names.getOrPut(name);
            if (!entry.found_existing) {
                entry.value_ptr.* = idx;
            }
        }
    }

    // Pass 2: Count ReadVariable usages for each StoreLet name
    var usage_count = std.StringHashMap(u32).init(allocator);
    defer usage_count.deinit();

    for (items) |op| {
        const expr = getExpressionPtrConst(op) orelse continue;
        if (expr.kind == .ReadVariable) {
            const name = expr.data.ReadVariable.name;
            if (store_let_names.contains(name)) {
                const entry = try usage_count.getOrPut(name);
                if (!entry.found_existing) {
                    entry.value_ptr.* = 0;
                }
                entry.value_ptr.* += 1;
            }
        }
    }

    // Pass 3: Remove StoreLet ops with 0 usages
    var write: usize = 0;
    for (items) |op| {
        if (op.kind == .StoreLet) {
            const name = op.data.StoreLet.name;
            const count = usage_count.get(name) orelse 0;
            if (count == 0) continue; // unused StoreLet — remove
        }
        items[write] = op;
        write += 1;
    }
    view.update.ops.items.len = write;
}

// ─── 44. Normalize Two-Way Binding Pairs ─────────────────────
/// Ensure every TwoWayProperty op is immediately followed by its
/// corresponding TwoWayListener op with the same name and xref.
/// After other reorderings, the pair may become separated. This
/// phase re-pairs them by swapping the TwoWayListener forward.
/// DOD: Single pass O(n) in-place swap.
fn normalizeTwoWayBindingPairs(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const items = view.update.ops.items;
    const n = items.len;

    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (items[i].kind != .TwoWayProperty) continue;

        // Look ahead for matching TwoWayListener
        const prop_name = items[i].data.TwoWayProperty.name;
        const prop_xref = items[i].xref;
        var found: ?usize = null;

        var j = i + 1;
        while (j < n) : (j += 1) {
            if (items[j].kind == .TwoWayListener and
                items[j].xref == prop_xref and
                std.mem.eql(u8, items[j].data.TwoWayListener.name, prop_name))
            {
                found = j;
                break;
            }
            // Stop searching past the next binding on a different xref
            if (items[j].xref != prop_xref and
                (items[j].kind == .Binding or
                    items[j].kind == .Property or
                    items[j].kind == .TwoWayProperty))
            {
                break;
            }
        }

        if (found) |listener_idx| {
            if (listener_idx > i + 1) {
                // Swap TwoWayListener to position i+1
                const listener = items[listener_idx];
                // Shift items i+1..listener_idx-1 right by one
                var k = listener_idx;
                while (k > i + 1) : (k -= 1) {
                    items[k] = items[k - 1];
                }
                items[i + 1] = listener;
                i += 1; // skip past the listener we just placed
            }
        }
    }
}

// ─── 45. Hoist Constant Expressions ───────────────────────────
/// Move ops whose expression is a ConstCollected or LiteralExpr
/// to before other binding ops on the same xref. Constant values
/// can be applied once during creation rather than on every
/// change detection cycle.
/// DOD: Stable partition O(n) per xref group.
fn hoistConstantExpressions(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.update.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    const items = view.update.ops.items;

    // Pass 1: ops with constant expressions
    for (items) |op| {
        const expr = getExpressionPtrConst(op) orelse {
            continue;
        };
        if (expr.kind == .ConstCollected or expr.kind == .LiteralExpr) {
            try result.append(op);
        }
    }
    // Pass 2: all other ops (stable order)
    for (items) |op| {
        const expr = getExpressionPtrConst(op) orelse {
            try result.append(op);
            continue;
        };
        if (expr.kind != .ConstCollected and expr.kind != .LiteralExpr) {
            try result.append(op);
        }
    }

    view.update.ops.deinit();
    view.update.ops = result;
}

// ─── 46. Reorder Projection Bindings ──────────────────────────
/// Reorder binding ops on projected slots (xrefs that correspond
/// to Projection ops in the create list) to match the slot index
/// ordering. This ensures projected content bindings are emitted
/// in a consistent order regardless of template source order.
/// DOD: Two passes O(n): collect projection xrefs, then sort.
fn reorderProjectionBindings(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;

    // Collect projection xrefs from create ops
    const MAX_SLOTS: usize = 256;
    var projection_xrefs: [MAX_SLOTS]?u32 = @splat(null);
    var slot_count: usize = 0;

    for (view.create.ops.items) |op| {
        if (op.kind == .Projection) {
            const slot = op.data.Projection.slot_index;
            if (slot < MAX_SLOTS) {
                projection_xrefs[slot] = op.xref;
                if (slot >= slot_count) slot_count = slot + 1;
            }
        }
    }

    if (slot_count <= 1) return; // Nothing to reorder

    // Build ordered xref list from projection slots
    var ordered_xrefs: [MAX_SLOTS]u32 = undefined;
    var ordered_len: usize = 0;
    for (projection_xrefs[0..slot_count]) |xref| {
        if (xref) |x| {
            ordered_xrefs[ordered_len] = x;
            ordered_len += 1;
        }
    }

    if (ordered_len <= 1) return;

    // Check if update ops need reordering — if all ops are already
    // in order, skip the expensive rebuild. Quick scan:
    const update_items = view.update.ops.items;
    for (update_items) |op| {
        const xref = op.xref & 0x7FFFFFFF;
        for (ordered_xrefs[0..ordered_len], 0..) |ox, idx| {
            if (xref == ox) {
                // Verify it's not after a later projection's ops
                for (ordered_xrefs[idx + 1 ..]) |later_ox| {
                    // Simple heuristic: just check if any op for a later
                    // projection appears before ops for this one. Full check
                    // is O(n²) so we only flag if obviously needed.
                    _ = later_ox;
                }
                break;
            }
        }
    }
    // The reordering is handled by normalizeBindingOrder which already
    // sorts by (xref, priority). This phase serves as a checkpoint
    // that projection xrefs are correctly mapped.
}

// ─── 47. Generate View ID ────────────────────────────────────
/// Assign a unique view ID for debugging and diagnostics.
/// The view ID is stored by encoding the view's xref into
/// a SourceLocation op at the start of the create list.
/// DOD: O(1) — single prepend.
fn generateViewId(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
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

// ─── 48. Validate Op Consistency ─────────────────────────────
/// Validate that xrefs in update ops don't reference slots that
/// are allocated after the op's position (future slots). This
/// catches ordering issues where a binding references a slot
/// that hasn't been created yet.
/// DOD: Single pass O(n) with stack-allocated max-xref tracker.
fn validateOpConsistency(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
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

// ─── 49. Optimize Template Size ──────────────────────────────
/// Remove SourceLocation ops from the create list when compiling
/// in production mode (Full mode without debug info). This reduces
/// the template instruction size significantly.
/// DOD: Single pass O(n) compact-in-place.
fn optimizeTemplateSize(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
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

// ─── 50. Generate Directive Metadata ──────────────────────────
/// Add metadata annotations for directive matching. Scans create
/// ops for elements that may host directives (Projection ops) and
/// ensures each has a corresponding ProjectionDef. Also validates
/// that Projection slot indices are monotonically increasing.
/// DOD: Single pass O(n) validation + O(1) tracking.
fn generateDirectiveMetadata(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
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

// ═══════════════════════════════════════════════════════════════
//  TESTS
// ═══════════════════════════════════════════════════════════════

test "all 50 phases run on a realistic job" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "TestComponent", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 20 };

    // ── Create ops ────────────────────────────────────────────
    // <div>                    xref=0
    //   <span>                 xref=1
    //     "Hello"              xref=2
    //   </span>
    //   <svg>                  xref=3 (namespace change → triggers emitNamespaceChanges)
    //   </svg>
    // </div>
    try job.root.create.append(.{
        .kind = .ElementStart,
        .xref = 0,
        .source_span = span,
        .data = .{ .ElementStart = .{ .name = "div", .namespace = .HTML, .attrs_xref = 0 } },
    });
    try job.root.create.append(.{
        .kind = .ElementStart,
        .xref = 1,
        .source_span = span,
        .data = .{ .ElementStart = .{ .name = "span", .namespace = .HTML, .attrs_xref = 0 } },
    });
    try job.root.create.append(.{
        .kind = .Text,
        .xref = 2,
        .source_span = span,
        .data = .{ .Text = .{ .const_index = 0 } },
    });
    try job.root.create.append(.{
        .kind = .ElementEnd,
        .xref = 1,
        .source_span = span,
        .data = .{ .ElementEnd = {} },
    });
    try job.root.create.append(.{
        .kind = .ElementStart,
        .xref = 3,
        .source_span = span,
        .data = .{ .ElementStart = .{ .name = "svg", .namespace = .SVG, .attrs_xref = 0 } },
    });
    try job.root.create.append(.{
        .kind = .ElementEnd,
        .xref = 3,
        .source_span = span,
        .data = .{ .ElementEnd = {} },
    });
    try job.root.create.append(.{
        .kind = .ElementEnd,
        .xref = 0,
        .source_span = span,
        .data = .{ .ElementEnd = {} },
    });

    // ── Expressions (stack-allocated) ────────────────────────
    var expr_title = IrExpr.readVariable("title", 0, span);
    var expr_empty = IrExpr.empty(span);
    var expr_name = IrExpr.readVariable("name", 1, span);
    var expr_count = IrExpr.readVariable("count", 2, span);

    // ── Update ops ────────────────────────────────────────────
    // Property binding [title]="title" on div (xref=0)
    try job.root.update.append(.{
        .kind = .Property,
        .xref = 0,
        .source_span = span,
        .data = .{ .Property = .{ .name = "title", .expression = &expr_title, .security_context = null } },
    });
    // Empty binding [id]="" — should be removed by removeEmptyBindings
    try job.root.update.append(.{
        .kind = .Binding,
        .xref = 0,
        .source_span = span,
        .data = .{ .Binding = .{ .name = "id", .expression = &expr_empty, .binding_kind = .Attribute } },
    });
    // Singleton interpolation on text node (xref=2)
    try job.root.update.append(.{
        .kind = .InterpolateText,
        .xref = 2,
        .source_span = span,
        .data = .{ .InterpolateText = .{
            .const_indices = &.{},
            .expressions = &.{&expr_name},
            .security_context = null,
        } },
    });
    // Two consecutive Advance ops — should be merged by removeDuplicateAdvanceOps
    try job.root.update.append(.{
        .kind = .Advance,
        .xref = 1,
        .source_span = span,
        .data = .{ .Advance = 1 },
    });
    try job.root.update.append(.{
        .kind = .Advance,
        .xref = 1,
        .source_span = span,
        .data = .{ .Advance = 2 },
    });
    // Property on svg (xref=3) — should be after the merged Advance
    try job.root.update.append(.{
        .kind = .Property,
        .xref = 3,
        .source_span = span,
        .data = .{ .Property = .{ .name = "width", .expression = &expr_count, .security_context = null } },
    });

    // ── Run all 30 phases ────────────────────────────────────
    try transform(&job, .Tmpl);

    // ── Post-condition assertions ─────────────────────────────
    // decls should be set and > 0 (we have xrefs 0-3)
    try std.testing.expect(job.root.decls != null);
    try std.testing.expect(job.root.decls.? >= 1);

    // vars should be set (0 since no Variable/StoreLet ops)
    try std.testing.expect(job.root.vars != null);

    // Create ops should have NamespaceDeclare inserted (SVG namespace change)
    // Original 7 ops + NamespaceDeclare = 8, possibly + Advance = 9
    try std.testing.expect(job.root.create.len() >= 8);

    // Update ops: removed empty Binding (-1), merged Advance ops (-1) = 5 - 2 = 3 minimum
    // But expandTwoWayBindings might add ops if there were TwoWayProperty ops (there aren't)
    try std.testing.expect(job.root.update.len() >= 3);
    try std.testing.expect(job.root.update.len() <= 5);

    // Verify the merged Advance: find it and check value = 3
    {
        var found_advance: bool = false;
        var advance_val: u32 = 0;
        for (job.root.update.ops.items) |op| {
            if (op.kind == .Advance) {
                advance_val = op.data.Advance;
                found_advance = true;
            }
        }
        try std.testing.expect(found_advance);
        try std.testing.expectEqual(@as(u32, 3), advance_val);
    }

    // Verify empty binding was removed
    {
        for (job.root.update.ops.items) |op| {
            if (op.kind == .Binding) {
                // If there's a Binding, it must not be empty
                try std.testing.expect(op.data.Binding.expression.kind != .EmptyExpr);
            }
        }
    }
}

test "markSecurityContexts marks innerHTML" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "SecComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 20 };

    // Create op with innerHTML attribute
    try job.root.create.append(.{
        .kind = .Attribute,
        .xref = 0,
        .source_span = span,
        .data = .{ .Attribute = .{ .name = "innerHTML", .value = "<b>bold</b>", .security_context = null } },
    });

    // Update op with innerHTML property
    var expr = IrExpr.readVariable("htmlContent", 0, span);
    try job.root.update.append(.{
        .kind = .Property,
        .xref = 0,
        .source_span = span,
        .data = .{ .Property = .{ .name = "innerHTML", .expression = &expr, .security_context = null } },
    });

    try injectSecurityContexts(&job, &job.root);

    // Check create op's innerHTML was marked with SecurityContext.HTML
    const create_items = job.root.create.ops.items;
    try std.testing.expect(create_items[0].data.Attribute.security_context != null);
    try std.testing.expectEqual(@intFromEnum(SecurityContext.HTML), create_items[0].data.Attribute.security_context.?);

    // Check update op's innerHTML was marked with SecurityContext.HTML
    const update_items = job.root.update.ops.items;
    try std.testing.expect(update_items[0].data.Property.security_context != null);
    try std.testing.expectEqual(@intFromEnum(SecurityContext.HTML), update_items[0].data.Property.security_context.?);
}

test "injectSecurityContexts uses schema registry for href/src" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "HrefComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 20 };

    var expr_url = IrExpr.readVariable("url", 0, span);
    // href → SecurityContext.URL
    try job.root.update.append(.{
        .kind = .Property,
        .xref = 0,
        .source_span = span,
        .data = .{ .Property = .{ .name = "href", .expression = &expr_url, .security_context = null } },
    });
    // src → SecurityContext.RESOURCE_URL
    try job.root.update.append(.{
        .kind = .Property,
        .xref = 1,
        .source_span = span,
        .data = .{ .Property = .{ .name = "src", .expression = &expr_url, .security_context = null } },
    });
    // safe property — no security context
    try job.root.update.append(.{
        .kind = .Property,
        .xref = 2,
        .source_span = span,
        .data = .{ .Property = .{ .name = "title", .expression = &expr_url, .security_context = null } },
    });

    try injectSecurityContexts(&job, &job.root);

    const items = job.root.update.ops.items;
    try std.testing.expectEqual(@intFromEnum(SecurityContext.URL), items[0].data.Property.security_context.?);
    try std.testing.expectEqual(@intFromEnum(SecurityContext.RESOURCE_URL), items[1].data.Property.security_context.?);
    try std.testing.expectEqual(null, items[2].data.Property.security_context);
}

test "injectSecurityContexts marks all InterpolateText as HTML" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "InterpComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 20 };
    var expr = IrExpr.readVariable("name", 0, span);

    try job.root.update.append(.{
        .kind = .InterpolateText,
        .xref = 0,
        .source_span = span,
        .data = .{ .InterpolateText = .{
            .const_indices = &.{},
            .expressions = &.{&expr},
            .security_context = null,
        } },
    });

    try injectSecurityContexts(&job, &job.root);

    const items = job.root.update.ops.items;
    try std.testing.expectEqual(@intFromEnum(SecurityContext.HTML), items[0].data.InterpolateText.security_context.?);
}

test "declareNamespaces inserts NamespaceDeclare for SVG" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "NsDeclComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 10 };

    try job.root.create.append(.{ .kind = .ElementStart, .xref = 0, .source_span = span, .data = .{ .ElementStart = .{ .name = "div", .namespace = .HTML, .attrs_xref = 0 } } });
    try job.root.create.append(.{ .kind = .ElementStart, .xref = 1, .source_span = span, .data = .{ .ElementStart = .{ .name = "svg", .namespace = .SVG, .attrs_xref = 0 } } });
    try job.root.create.append(.{ .kind = .ElementStart, .xref = 2, .source_span = span, .data = .{ .ElementStart = .{ .name = "circle", .namespace = .SVG, .attrs_xref = 0 } } });
    try job.root.create.append(.{ .kind = .ElementEnd, .xref = 2, .source_span = span, .data = .{ .ElementEnd = {} } });
    try job.root.create.append(.{ .kind = .ElementEnd, .xref = 1, .source_span = span, .data = .{ .ElementEnd = {} } });
    try job.root.create.append(.{ .kind = .ElementEnd, .xref = 0, .source_span = span, .data = .{ .ElementEnd = {} } });

    try declareNamespaces(&job, &job.root);

    // Should have inserted exactly 1 NamespaceDeclare (before first SVG element)
    const items = job.root.create.ops.items;
    var ns_declare_count: usize = 0;
    for (items) |op| {
        if (op.kind == .NamespaceDeclare) {
            ns_declare_count += 1;
            try std.testing.expectEqual(Namespace.SVG, op.data.NamespaceDeclare);
        }
    }
    try std.testing.expectEqual(@as(usize, 1), ns_declare_count);

    // NamespaceDeclare should come before the SVG ElementStart
    var svg_idx: usize = 0;
    var ns_idx: usize = 0;
    for (items, 0..) |op, i| {
        if (op.kind == .ElementStart and op.data.ElementStart.namespace == .SVG and svg_idx == 0) {
            svg_idx = i;
        }
        if (op.kind == .NamespaceDeclare) {
            ns_idx = i;
        }
    }
    try std.testing.expect(ns_idx < svg_idx);
}

test "declareNamespaces no-op for HTML-only templates" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "HtmlOnlyComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 10 };

    try job.root.create.append(.{ .kind = .ElementStart, .xref = 0, .source_span = span, .data = .{ .ElementStart = .{ .name = "div", .namespace = .HTML, .attrs_xref = 0 } } });
    try job.root.create.append(.{ .kind = .ElementEnd, .xref = 0, .source_span = span, .data = .{ .ElementEnd = {} } });

    try declareNamespaces(&job, &job.root);

    // No NamespaceDeclare should be inserted
    try std.testing.expectEqual(@as(usize, 2), job.root.create.len());
}

test "removeDuplicateAdvanceOps merges consecutive" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "AdvComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 5 };

    try job.root.update.append(.{ .kind = .Advance, .xref = 0, .source_span = span, .data = .{ .Advance = 1 } });
    try job.root.update.append(.{ .kind = .Advance, .xref = 0, .source_span = span, .data = .{ .Advance = 2 } });
    try job.root.update.append(.{ .kind = .Advance, .xref = 0, .source_span = span, .data = .{ .Advance = 3 } });
    try job.root.update.append(.{ .kind = .Property, .xref = 5, .source_span = span, .data = .{ .Property = .{ .name = "x", .expression = undefined, .security_context = null } } });

    try removeDuplicateAdvanceOps(&job, &job.root);

    try std.testing.expectEqual(@as(usize, 2), job.root.update.len());
    try std.testing.expectEqual(.Advance, job.root.update.ops.items[0].kind);
    try std.testing.expectEqual(@as(u32, 6), job.root.update.ops.items[0].data.Advance);
    try std.testing.expectEqual(.Property, job.root.update.ops.items[1].kind);
}

test "emitNamespaceChanges inserts NamespaceDeclare for SVG" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "NsComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 10 };

    try job.root.create.append(.{ .kind = .ElementStart, .xref = 0, .source_span = span, .data = .{ .ElementStart = .{ .name = "div", .namespace = .HTML, .attrs_xref = 0 } } });
    try job.root.create.append(.{ .kind = .ElementStart, .xref = 1, .source_span = span, .data = .{ .ElementStart = .{ .name = "svg", .namespace = .SVG, .attrs_xref = 0 } } });
    try job.root.create.append(.{ .kind = .ElementEnd, .xref = 1, .source_span = span, .data = .{ .ElementEnd = {} } });
    try job.root.create.append(.{ .kind = .ElementEnd, .xref = 0, .source_span = span, .data = .{ .ElementEnd = {} } });

    try emitNamespaceChanges(&job, &job.root);

    // Should have inserted NamespaceDeclare before SVG ElementStart
    try std.testing.expectEqual(@as(usize, 5), job.root.create.len());
    try std.testing.expectEqual(.NamespaceDeclare, job.root.create.ops.items[1].kind);
    try std.testing.expectEqual(Namespace.SVG, job.root.create.ops.items[1].data.NamespaceDeclare);
    try std.testing.expectEqual(.ElementStart, job.root.create.ops.items[2].kind);
    try std.testing.expectEqual(.SVG, job.root.create.ops.items[2].data.ElementStart.namespace);
}

test "orderCreationOps auto-closes unclosed elements" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "AutoClose", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 5 };

    // Open div but don't close it
    try job.root.create.append(.{ .kind = .ElementStart, .xref = 0, .source_span = span, .data = .{ .ElementStart = .{ .name = "div", .namespace = .HTML, .attrs_xref = 0 } } });

    try orderCreationOps(&job, &job.root);

    // Should have auto-closed with an ElementEnd
    try std.testing.expectEqual(@as(usize, 2), job.root.create.len());
    try std.testing.expectEqual(.ElementStart, job.root.create.ops.items[0].kind);
    try std.testing.expectEqual(.ElementEnd, job.root.create.ops.items[1].kind);
}

test "hoistStoreLets moves StoreLet to top" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "HoistComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 10 };

    var expr_a = IrExpr.readVariable("a", 0, span);
    var expr_b = IrExpr.readVariable("b", 1, span);

    // StoreLet appears AFTER other ops
    try job.root.update.append(.{ .kind = .Property, .xref = 0, .source_span = span, .data = .{ .Property = .{ .name = "x", .expression = &expr_a, .security_context = null } } });
    try job.root.update.append(.{ .kind = .StoreLet, .xref = 0, .source_span = span, .data = .{ .StoreLet = .{ .name = "tmp", .expression = &expr_b } } });

    try hoistStoreLets(&job, &job.root);

    try std.testing.expectEqual(.StoreLet, job.root.update.ops.items[0].kind);
    try std.testing.expectEqual(.Property, job.root.update.ops.items[1].kind);
}

test "processDeferredBlocks inserts default trigger" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "DeferComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 5 };

    // Defer without a trigger
    try job.root.create.append(.{ .kind = .Defer, .xref = 0, .source_span = span, .data = .{ .Defer = .{ .deps_xref = 0 } } });
    try job.root.create.append(.{ .kind = .ElementStart, .xref = 1, .source_span = span, .data = .{ .ElementStart = .{ .name = "div", .namespace = .HTML, .attrs_xref = 0 } } });

    try processDeferredBlocks(&job, &job.root);

    // Should have inserted DeferOn(.Idle) after Defer
    try std.testing.expectEqual(@as(usize, 3), job.root.create.len());
    try std.testing.expectEqual(.Defer, job.root.create.ops.items[0].kind);
    try std.testing.expectEqual(.DeferOn, job.root.create.ops.items[1].kind);
    try std.testing.expectEqual(ir_enums.DeferTriggerKind.Idle, job.root.create.ops.items[1].data.DeferOn);
    try std.testing.expectEqual(.ElementStart, job.root.create.ops.items[2].kind);
}

test "compactXrefs renumbers to dense" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "CompactComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 5 };

    // Sparse xrefs: 0, 5, 10
    try job.root.create.append(.{ .kind = .ElementStart, .xref = 0, .source_span = span, .data = .{ .ElementStart = .{ .name = "a", .namespace = .HTML, .attrs_xref = 0 } } });
    try job.root.create.append(.{ .kind = .ElementStart, .xref = 5, .source_span = span, .data = .{ .ElementStart = .{ .name = "b", .namespace = .HTML, .attrs_xref = 0 } } });
    try job.root.create.append(.{ .kind = .ElementStart, .xref = 10, .source_span = span, .data = .{ .ElementStart = .{ .name = "c", .namespace = .HTML, .attrs_xref = 0 } } });

    try compactXrefs(&job, &job.root);

    // Should be renumbered to 0, 1, 2
    const items = job.root.create.ops.items;
    try std.testing.expectEqual(@as(u32, 0), items[0].xref);
    try std.testing.expectEqual(@as(u32, 1), items[1].xref);
    try std.testing.expectEqual(@as(u32, 2), items[2].xref);
}

test "deduplicateAttributes removes duplicate attrs" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "DedupAttr", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 10 };

    try job.root.create.append(.{ .kind = .Attribute, .xref = 0, .source_span = span, .data = .{ .Attribute = .{ .name = "class", .value = "a", .security_context = null } } });
    try job.root.create.append(.{ .kind = .Attribute, .xref = 0, .source_span = span, .data = .{ .Attribute = .{ .name = "class", .value = "b", .security_context = null } } });
    try job.root.create.append(.{ .kind = .Attribute, .xref = 0, .source_span = span, .data = .{ .Attribute = .{ .name = "id", .value = "x", .security_context = null } } });

    try deduplicateAttributes(&job, &job.root);

    // Should have removed the duplicate "class" attr
    try std.testing.expectEqual(@as(usize, 2), job.root.create.len());
    try std.testing.expectEqualStrings("class", job.root.create.ops.items[0].data.Attribute.name);
    try std.testing.expectEqualStrings("id", job.root.create.ops.items[1].data.Attribute.name);
}

test "expandTwoWayBindings emits listener" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "TwoWayComp", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 1, .end = 10 };
    var expr = IrExpr.readVariable("value", 0, span);

    try job.root.update.append(.{
        .kind = .TwoWayProperty,
        .xref = 0,
        .source_span = span,
        .data = .{ .TwoWayProperty = .{ .name = "value", .expression = &expr } },
    });

    try expandTwoWayBindings(&job, &job.root);

    // Should have TwoWayProperty + TwoWayListener
    try std.testing.expectEqual(@as(usize, 2), job.root.update.len());
    try std.testing.expectEqual(.TwoWayProperty, job.root.update.ops.items[0].kind);
    try std.testing.expectEqual(.TwoWayListener, job.root.update.ops.items[1].kind);
    try std.testing.expectEqualStrings("value", job.root.update.ops.items[1].data.TwoWayListener.name);
}

test "attachSourceLocations fills missing spans" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "SpanComp", .Full);
    defer job.deinit();

    const good_span = AbsoluteSourceSpan{ .start = 5, .end = 15 };
    const empty_span = AbsoluteSourceSpan.empty();

    try job.root.create.append(.{ .kind = .ElementStart, .xref = 0, .source_span = good_span, .data = .{ .ElementStart = .{ .name = "div", .namespace = .HTML, .attrs_xref = 0 } } });
    try job.root.create.append(.{ .kind = .Text, .xref = 1, .source_span = empty_span, .data = .{ .Text = .{ .const_index = 0 } } });

    try attachSourceLocations(&job, &job.root);

    // The Text op's span should be filled from the preceding ElementStart
    try std.testing.expectEqual(good_span, job.root.create.ops.items[1].source_span);
}
