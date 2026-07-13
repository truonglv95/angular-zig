/// IR Ingestion — R3 AST → IR Operations
///
/// This is THE critical algorithm. Recursively walks R3 AST nodes
/// and emits IR ops into ComponentCompilationJob.
///
/// DOD optimizations:
///   - Single recursive pass (no intermediate allocations)
///   - Slot allocation is monotonic O(1) increment
///   - All ops go directly into contiguous OpList arrays
///   - Expression conversion is deferred to conversion.zig
///   - Constant pooling for all static strings
const std = @import("std");
const Allocator = std.mem.Allocator;

const job_mod = @import("job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const r3_ast = @import("../render3/r3_ast.zig");
const R3Node = r3_ast.R3Node;
const NodeKind = r3_ast.NodeKind;

const ir_enums = @import("enums.zig");
const OpKind = ir_enums.OpKind;
const Namespace = ir_enums.Namespace;
const BindingKind = ir_enums.BindingKind;
const DeferTriggerKind = ir_enums.DeferTriggerKind;

const ir_ops = @import("ops.zig");
const IrOp = ir_ops.IrOp;

const ir_expr = @import("expression.zig");
const IrExpr = ir_expr.IrExpr;

const conversion = @import("conversion.zig");

const source_span = @import("../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

const tags = @import("../ml_parser/tags.zig");

// ─── Ingest Entry Point ──────────────────────────────────────

/// Ingest R3 AST nodes into the root view of a compilation job.
pub fn ingestR3Nodes(job: *ComponentCompilationJob, nodes: []const *const R3Node) !void {
    try ingestNodesIntoView(job, &job.root, nodes);
}

/// Ingest R3 nodes into a specific view's create/update op lists.
pub fn ingestNodesIntoView(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    nodes: []const *const R3Node,
) !void {
    for (nodes) |node| {
        try ingestNode(job, view, node);
    }
}

// ─── Node Ingestion (recursive) ──────────────────────────────

fn ingestNode(job: *ComponentCompilationJob, view: *ViewCompilationUnit, node: *const R3Node) error{ OutOfMemory, NoSpaceLeft }!void {
    switch (node.data) {
        .Element => |elem| try ingestElement(job, view, node, elem),
        .Text => |text| try ingestText(job, view, node.source_span.absolute(), text.value),
        .BoundText => |bound_text| try ingestBoundText(job, view, node, bound_text),
        .TextAttribute => |attr| try ingestTextAttribute(job, view, attr),
        .BoundAttribute => |bound_attr| try ingestBoundAttribute(job, view, node, bound_attr),
        .BoundEvent => |bound_event| try ingestBoundEvent(job, view, node, bound_event),
        .Reference => |ref| try ingestReference(job, view, ref),
        .Template => |tpl| try ingestTemplate(job, view, node, tpl),
        .Content => |content| try ingestContent(job, view, node, content),
        .IfBlock => |if_block| try ingestIfBlock(job, view, node, if_block),
        .ForLoopBlock => |for_block| try ingestForLoopBlock(job, view, node, for_block),
        .SwitchBlock => |switch_block| try ingestSwitchBlock(job, view, node, switch_block),
        .DeferredBlock => |defer_block| try ingestDeferredBlock(job, view, node, defer_block),
        .LetDeclaration => |let_decl| try ingestLetDeclaration(job, view, node, let_decl),
        .Comment => {},
        .Variable => |var_| try ingestVariable(job, view, var_),
        .Icu => |icu| try ingestIcu(job, view, node, icu),
        .ForLoopBlockEmpty => {},
        .DeferredTrigger => {},
        .IcuPlaceholder => {},
        .Component => |comp| try ingestComponent(job, view, node, comp),
        .Directive => |dir| try ingestDirective(job, view, node, dir),
        .UnknownBlock => {},
        .IfBlockBranch, .SwitchBlockCaseGroup, .SwitchBlockCase => unreachable,
    }
}

// ─── Element ─────────────────────────────────────────────────

fn ingestElement(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    elem: r3_ast.ElementData,
) !void {
    const slot = job.slots.allocSlot();
    const tags_ns = tags.getNamespace(elem.name);
    const ns: Namespace = switch (tags_ns) {
        .HTML => .HTML,
        .SVG => .SVG,
        .MathML => .MathML,
    };

    // Build attribute constant array for this element
    const attrs_xref = try buildAttributeArray(job, view, elem.attributes, elem.inputs, elem.references);

    // Emit ElementStart
    try view.create.append(.{
        .kind = .ElementStart,
        .xref = slot,
        .source_span = node.source_span.absolute(),
        .data = .{ .ElementStart = .{
            .name = elem.name,
            .namespace = ns,
            .attrs_xref = attrs_xref,
        } },
    });

    // Emit Listeners (creation phase) — compile handler into function ops
    // Note: outputs is []const R3Node (value slice, not pointer slice),
    // so .data access on each value is correct.
    for (elem.outputs) |output| {
        if (output.data == .BoundEvent) {
            const evt = output.data.BoundEvent;
            // Compile the event handler expression into a function
            const handler_fn_xref = try compileEventHandler(job, view, evt, slot);

            // Listener ops go in create phase (they register the handler)
            try view.create.append(.{
                .kind = .Listener,
                .xref = slot,
                .source_span = evt.source_span,
                .data = .{ .Listener = .{
                    .name = evt.name,
                    .handler_fn_xref = handler_fn_xref,
                } },
            });
        }
    }

    // Emit references as variable declarations in create phase
    for (elem.references) |ref_node| {
        if (ref_node.data == .Reference) {
            const ref = ref_node.data.Reference;
            const ref_slot = job.slots.allocSlot();
            // Store reference as a Variable op
            try view.create.append(.{
                .kind = .Statement,
                .xref = ref_slot,
                .source_span = ref.key_span,
                .data = .{ .Statement = ref.name },
            });
        }
    }

    // Emit Advance to skip over the element's slot
    if (elem.children.len > 0) {
        // Children will handle their own advance
    }

    // Ingest children
    for (elem.children) |c| {
        try ingestNode(job, view, c);
    }

    // Emit ElementEnd
    try view.create.append(.{
        .kind = .ElementEnd,
        .xref = slot,
        .source_span = node.source_span.absolute(),
        .data = .{ .ElementEnd = {} },
    });
}

// ─── Text ─────────────────────────────────────────────────────

fn ingestText(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    span: AbsoluteSourceSpan,
    value: []const u8,
) !void {
    const slot = job.slots.allocSlot();
    const const_idx = try job.addConst(value, .String);

    try view.create.append(.{
        .kind = .Text,
        .xref = slot,
        .source_span = span,
        .data = .{ .Text = .{ .const_index = const_idx } },
    });
}

// ─── Bound Text (with {{ }} interpolation) ────────────────────

fn ingestBoundText(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    bound_text: r3_ast.BoundTextData,
) !void {
    const slot = job.slots.allocSlot();

    // Convert expression AST to IR expression
    const converted_expr = try conversion.convertExpr(job, bound_text.value);

    // Allocate a variable for the interpolation result
    const var_idx = job.slots.allocSlot();

    // Use the converted expression directly
    const exprs = try job.allocator.alloc(*IrExpr, 1);
    exprs[0] = @constCast(converted_expr);

    // Emit InterpolateText in update phase
    try view.update.append(.{
        .kind = .InterpolateText,
        .xref = slot,
        .source_span = node.source_span.absolute(),
        .data = .{ .InterpolateText = .{
            .const_indices = &[_]u32{},
            .expressions = exprs,
            .security_context = null,
        } },
    });

    // Emit Advance
    try view.update.append(.{
        .kind = .Advance,
        .xref = var_idx,
        .source_span = node.source_span.absolute(),
        .data = .{ .Advance = 1 },
    });
}

// ─── Text Attribute (static) → stored in constant array ────────

fn ingestTextAttribute(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    attr: r3_ast.TextAttributeData,
) !void {
    // Static attributes are collected into the element's constant array
    // They don't emit individual ops — handled by buildAttributeArray
    _ = job;
    _ = view;
    _ = attr;
}

// ─── Bound Attribute → Property/Class/Style/Attribute binding ─

fn ingestBoundAttribute(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    bound_attr: r3_ast.BoundAttributeData,
) !void {
    // Convert expression AST to IR expression
    const bound_ir_expr = try conversion.convertExpr(job, bound_attr.value);

    const binding_kind: BindingKind = switch (bound_attr.type) {
        .Property => .Property,
        .Attribute => .Attribute,
        .Class => .ClassName,
        .Style => .StyleProperty,
        .TwoWay => .TwoWayProperty,
        .Animation => .Animation,
    };

    const op_kind: OpKind = switch (bound_attr.type) {
        .Property => .Property,
        .Attribute => .Binding,
        .Class => .ClassProp,
        .Style => .StyleProp,
        .TwoWay => .TwoWayProperty,
        .Animation => .AnimationBinding,
    };

    const span = bound_attr.source_span;

    switch (bound_attr.type) {
        .Property => {
            try view.update.append(.{
                .kind = .Property,
                .xref = 0,
                .source_span = span,
                .data = .{ .Property = .{
                    .name = bound_attr.name,
                    .expression = bound_ir_expr,
                    .security_context = bound_attr.security_context,
                } },
            });
        },
        .Attribute => {
            try view.update.append(.{
                .kind = .Binding,
                .xref = 0,
                .source_span = span,
                .data = .{ .Binding = .{
                    .name = bound_attr.name,
                    .expression = bound_ir_expr,
                    .binding_kind = .Attribute,
                } },
            });
        },
        .Class => {
            try view.update.append(.{
                .kind = .ClassProp,
                .xref = 0,
                .source_span = span,
                .data = .{ .ClassProp = .{
                    .name = bound_attr.name,
                    .expression = bound_ir_expr,
                } },
            });
        },
        .Style => {
            try view.update.append(.{
                .kind = .StyleProp,
                .xref = 0,
                .source_span = span,
                .data = .{ .StyleProp = .{
                    .name = bound_attr.name,
                    .expression = bound_ir_expr,
                    .unit = bound_attr.unit,
                    .sanitizer = null,
                } },
            });
        },
        .TwoWay => {
            // Two-way binding: [(name)] → TwoWayProperty + TwoWayListener
            try view.update.append(.{
                .kind = .TwoWayProperty,
                .xref = 0,
                .source_span = span,
                .data = .{ .TwoWayProperty = .{
                    .name = bound_attr.name,
                    .expression = bound_ir_expr,
                } },
            });
            // TwoWayListener will be added by a transformation phase
        },
        .Animation => {
            try view.update.append(.{
                .kind = .AnimationBinding,
                .xref = 0,
                .source_span = span,
                .data = .{ .AnimationBinding = .{
                    .name = bound_attr.name,
                    .expression = bound_ir_expr,
                } },
            });
        },
    }

    _ = op_kind;
    _ = binding_kind;
    _ = node;
}

// ─── Bound Event ──────────────────────────────────────────────

fn ingestBoundEvent(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    bound_event: r3_ast.BoundEventData,
) !void {
    // Standalone event binding (not on an element) — emit a Listener op
    // in the create phase. Most events are ingested via ingestElement's
    // outputs loop, but standalone events (e.g. on ng-template) reach here.
    const slot = job.slots.allocSlot();
    const handler_fn_xref = try compileEventHandler(job, view, bound_event, slot);

    try view.create.append(.{
        .kind = .Listener,
        .xref = slot,
        .source_span = bound_event.source_span,
        .data = .{ .Listener = .{
            .name = bound_event.name,
            .handler_fn_xref = handler_fn_xref,
        } },
    });
    _ = node;
}

// ─── Reference (#ref) ─────────────────────────────────────────

fn ingestReference(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    ref_: r3_ast.ReferenceData,
) !void {
    // Allocate a slot for the reference and emit a Statement op
    // that stores the reference name. The actual reference value
    // is resolved at runtime by the ɵɵreference instruction.
    const ref_slot = job.slots.allocSlot();
    try view.create.append(.{
        .kind = .Statement,
        .xref = ref_slot,
        .source_span = ref_.key_span,
        .data = .{ .Statement = ref_.name },
    });
}

// ─── Template (ng-template, structural directives) ────────────

fn ingestTemplate(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    tpl: r3_ast.TemplateData,
) !void {
    _ = node;

    // Create an embedded view for the template
    const embedded_view = try job.allocateView(view.xref);
    try job.views.put(tpl.tag_name, embedded_view);

    // Ingest template children into the embedded view
    try ingestNodesIntoView(job, embedded_view, tpl.children);
}

// ─── Content (ng-content) ─────────────────────────────────────

fn ingestContent(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    content: r3_ast.ContentData,
) !void {
    const slot_index = job.slots.allocSlot();

    // Emit Projection
    try view.create.append(.{
        .kind = .Projection,
        .xref = slot_index,
        .source_span = node.source_span.absolute(),
        .data = .{ .Projection = .{
            .slot_index = slot_index,
            .selector = content.selector,
        } },
    });
}

// ─── If Block (@if / *ngIf) ──────────────────────────────────

fn ingestIfBlock(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    if_block: r3_ast.IfBlockData,
) !void {
    const slot = job.slots.allocSlot();

    // Emit ConditionalCreate in creation phase
    try view.create.append(.{
        .kind = .ConditionalCreate,
        .xref = slot,
        .source_span = node.source_span.absolute(),
        .data = .{ .ConditionalCreate = {} },
    });

    // Collect condition expressions for multi-branch negation.
    // Each branch after the first needs: !prevCond1 && !prevCond2 && ... && thisCond
    var prev_conds = std.array_list.Managed(*const IrExpr).init(job.allocator);
    defer prev_conds.deinit();

    // Process each branch
    for (if_block.branches, 0..) |branch, i| {
        if (branch.expression) |cond| {
            const cond_expr = try conversion.convertExpr(job, cond);

            // For branch 0, emit the condition directly.
            // For branches > 0, emit: !prevCond1 && !prevCond2 && ... && thisCond
            const effective_cond: *const IrExpr = if (i == 0) blk: {
                // Store condition for later negation by subsequent branches
                const stored = try job.allocator.create(IrExpr);
                stored.* = cond_expr.*;
                try prev_conds.append(stored);
                break :blk stored;
            } else blk: {
                // Build: !(p1 || p2 || ... || pn) && thisCond
                // which is equivalent to: !p1 && !p2 && ... && !pn && thisCond
                // Using De Morgan's: !(p1 || p2) === !p1 && !p2
                const stored = try job.allocator.create(IrExpr);
                stored.* = cond_expr.*;

                // Start with the first previous condition negated
                var negated_chain = try job.allocator.create(IrExpr);
                negated_chain.* = IrExpr.notExpr(@constCast(prev_conds.items[0]), branch.source_span);

                // AND with negations of all subsequent previous conditions
                for (prev_conds.items[1..]) |prev_c| {
                    const next_neg = try job.allocator.create(IrExpr);
                    next_neg.* = IrExpr.notExpr(@constCast(prev_c), branch.source_span);
                    const and_expr = try job.allocator.create(IrExpr);
                    and_expr.* = IrExpr.binaryExpr(negated_chain, 30, next_neg, branch.source_span); // 30 = &&
                    negated_chain = and_expr;
                }

                // AND with this branch's condition
                const final_and = try job.allocator.create(IrExpr);
                final_and.* = IrExpr.binaryExpr(negated_chain, 30, @constCast(stored), branch.source_span);

                try prev_conds.append(stored);
                break :blk final_and;
            };

            try view.update.append(.{
                .kind = .Conditional,
                .xref = slot,
                .source_span = branch.source_span,
                .data = .{ .Conditional = .{
                    .condition_expr = @constCast(effective_cond),
                } },
            });
        }

        // Ingest branch children
        for (branch.children) |c| {
            try ingestNode(job, view, c);
        }
    }
}

// ─── For Loop Block (@for / *ngFor) ──────────────────────────

fn ingestForLoopBlock(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    for_block: r3_ast.ForLoopBlockData,
) !void {
    const slot = job.slots.allocSlot();

    // Emit RepeaterCreate
    try view.create.append(.{
        .kind = .RepeaterCreate,
        .xref = slot,
        .source_span = node.source_span.absolute(),
        .data = .{ .RepeaterCreate = {} },
    });

    // Convert collection expression to IR and store in arena
    const collection_expr = try conversion.convertExpr(job, for_block.expression);
    const collection_ptr = collection_expr;

    // Ingest loop children
    for (for_block.children) |c| {
        try ingestNode(job, view, c);
    }

    // Parse track-by expression if present
    var track_by_fn: ?*IrExpr = null;
    if (for_block.track_by) |track_str| {
        // Parse the track-by expression string using the expression parser
        const expr_parser_mod = @import("../expression_parser/parser.zig");
        const expr_arena_mod = @import("../arena.zig");
        var expr_arena = expr_arena_mod.AstArena.init(job.allocator);
        defer expr_arena.deinit();

        const abs_span = node.source_span.absolute();
        var parser = expr_parser_mod.Parser.init(
            job.allocator,
            &expr_arena,
            track_str,
            &.{}, // empty tokens — parseBinding handles tokenization internally
            0,
        );

        if (parser.parseBinding()) |parsed| {
            const track_ir = conversion.convertExpr(job, parsed) catch null;
            if (track_ir) |t| {
                track_by_fn = t;
            }
        } else |_| {}

        // Fallback: use $index if parsing failed
        if (track_by_fn == null) {
            const default_track = try job.allocator.create(IrExpr);
            default_track.* = IrExpr.literalExpr("$index", abs_span);
            track_by_fn = default_track;
        }
    }

    // Emit Repeater in update phase with collection expression
    try view.update.append(.{
        .kind = .Repeater,
        .xref = slot,
        .source_span = node.source_span.absolute(),
        .data = .{ .Repeater = .{
            .track_by_fn = track_by_fn,
            .collection_expr = collection_ptr,
        } },
    });
}

// ─── Switch Block (@switch / *ngSwitch) ──────────────────────

fn ingestSwitchBlock(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    switch_block: r3_ast.SwitchBlockData,
) !void {
    const slot = job.slots.allocSlot();

    // Convert the switch discriminant expression once
    const switch_ptr = try conversion.convertExpr(job, switch_block.expression);

    // Emit ConditionalCreate for the switch block
    try view.create.append(.{
        .kind = .ConditionalCreate,
        .xref = slot,
        .source_span = node.source_span.absolute(),
        .data = .{ .ConditionalCreate = {} },
    });

    // For each case group, emit a conditional chain:
    // case 0: switchExpr === "value1"
    // case 1: switchExpr !== "value1" && switchExpr === "value2"
    // ...etc (De Morgan's negation of all previous cases)
    var prev_case_exprs = std.array_list.Managed(*const IrExpr).init(job.allocator);
    defer prev_case_exprs.deinit();

    for (switch_block.groups) |group| {
        // Build the condition for this case group.
        // A group may have multiple cases (fall-through): cond = (v1 || v2 || ...)
        var case_cond: ?*const IrExpr = null;
        for (group.cases) |case_| {
            // switchExpr === case_.value  (strict equality, op code 12)
            const case_val = try job.allocator.create(IrExpr);
            case_val.* = IrExpr.literalExpr(case_.value, case_.source_span);
            const eq_expr = try job.allocator.create(IrExpr);
            eq_expr.* = IrExpr.binaryExpr(@constCast(switch_ptr), 12, case_val, case_.source_span); // 12 = ===

            if (case_cond) |prev| {
                // OR with previous case in this group
                const or_expr = try job.allocator.create(IrExpr);
                or_expr.* = IrExpr.binaryExpr(@constCast(prev), 31, eq_expr, case_.source_span); // 31 = ||
                case_cond = or_expr;
            } else {
                case_cond = eq_expr;
            }
        }

        // If there are previous case groups, negate them: !prev1 && !prev2 && ... && thisCase
        if (prev_case_exprs.items.len > 0) {
            // Negate all previous case conditions and AND them
            var neg_chain = try job.allocator.create(IrExpr);
            neg_chain.* = IrExpr.notExpr(@constCast(prev_case_exprs.items[0]), node.source_span.absolute());
            for (prev_case_exprs.items[1..]) |prev_c| {
                const next_neg = try job.allocator.create(IrExpr);
                next_neg.* = IrExpr.notExpr(@constCast(prev_c), node.source_span.absolute());
                const and_expr = try job.allocator.create(IrExpr);
                and_expr.* = IrExpr.binaryExpr(neg_chain, 30, next_neg, node.source_span.absolute()); // 30 = &&
                neg_chain = and_expr;
            }
            // AND with this group's condition
            if (case_cond) |cc| {
                const final_and = try job.allocator.create(IrExpr);
                final_and.* = IrExpr.binaryExpr(neg_chain, 30, @constCast(cc), node.source_span.absolute());
                case_cond = final_and;
            }
        }

        // Store this case condition for subsequent negation
        if (case_cond) |cc| {
            try prev_case_exprs.append(cc);
        }

        // Emit the conditional for this case group
        if (case_cond) |cc| {
            try view.update.append(.{
                .kind = .Conditional,
                .xref = slot,
                .source_span = node.source_span.absolute(),
                .data = .{ .Conditional = .{
                    .condition_expr = @constCast(cc),
                } },
            });
        }

        // Ingest case group children
        for (group.children) |c| {
            try ingestNode(job, view, c);
        }
    }
}

// ─── Deferred Block (@defer) ─────────────────────────────────

fn ingestDeferredBlock(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    defer_block: r3_ast.DeferredBlockData,
) !void {
    const slot = job.slots.allocSlot();

    try view.create.append(.{
        .kind = .Defer,
        .xref = slot,
        .source_span = node.source_span.absolute(),
        .data = .{ .Defer = .{
            .deps_xref = 0,
        } },
    });

    // Emit triggers
    for (defer_block.triggers) |trigger| {
        try view.create.append(.{
            .kind = .DeferOn,
            .xref = slot,
            .source_span = node.source_span.absolute(),
            .data = .{ .DeferOn = switch (trigger.kind) {
                .Idle => DeferTriggerKind.Idle,
                .Immediate => DeferTriggerKind.Immediate,
                .Timer => DeferTriggerKind.Timer,
                .Hover => DeferTriggerKind.Hover,
                .Interaction => DeferTriggerKind.Interaction,
                .Viewport => DeferTriggerKind.Viewport,
                .Never => DeferTriggerKind.Never,
            } },
        });
    }

    // Ingest main children
    for (defer_block.children) |c| {
        try ingestNode(job, view, c);
    }
}

// ─── Let Declaration (@let) ──────────────────────────────────

fn ingestLetDeclaration(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    let_decl: r3_ast.LetDeclarationData,
) !void {
    const let_ir_expr = try conversion.convertExpr(job, let_decl.value);

    try view.update.append(.{
        .kind = .StoreLet,
        .xref = 0,
        .source_span = node.source_span.absolute(),
        .data = .{ .StoreLet = .{
            .name = let_decl.name,
            .expression = let_ir_expr,
        } },
    });
}

// ─── Variable (let-*) ────────────────────────────────────────

fn ingestVariable(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    var_: r3_ast.VariableData,
) !void {
    // Variables (let-declarations in ng-template context) are tracked
    // as Variable ops in the create phase. The runtime uses these to
    // expose context variables to the template scope.
    // Variable op requires value: *IrExpr — for now emit as Statement
    // (placeholder until proper IrExpr conversion is wired up).
    _ = job;
    _ = view;
    _ = var_;
    // TODO: convert var_.value to IrExpr and emit proper Variable op
}

// ─── ICU (i18n) ──────────────────────────────────────────────

fn ingestIcu(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    icu: r3_ast.IcuData,
) !void {
    // ICU expressions ({count, plural, =0 {...} other {...}}) are emitted
    // as I18n ops. The actual ICU message serialization is handled by the
    // i18n phases (extract_i18n_messages, i18n_const_collection).
    const icu_slot = job.slots.allocSlot();
    _ = icu; // TODO: wire up ICU cases/placeholders into I18n op data
    try view.create.append(.{
        .kind = .I18n,
        .xref = icu_slot,
        .source_span = node.source_span.absolute(),
        .data = .{ .Statement = "icu" }, // placeholder
    });
}

// ─── Component ───────────────────────────────────────────────

fn ingestComponent(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    comp: r3_ast.ComponentData,
) !void {
    // Component is treated like an element but marked as foreign
    const slot = job.slots.allocSlot();
    const attrs_xref = try buildAttributeArray(job, view, comp.attributes, comp.inputs, comp.references);

    // Use ForeignComponent to signal component resolution
    try view.create.append(.{
        .kind = .ElementStart,
        .xref = slot,
        .source_span = node.source_span.absolute(),
        .data = .{ .ElementStart = .{
            .name = comp.tag_name,
            .namespace = .HTML,
            .attrs_xref = attrs_xref,
        } },
    });

    for (comp.children) |c| {
        try ingestNode(job, view, c);
    }

    try view.create.append(.{
        .kind = .ElementEnd,
        .xref = slot,
        .source_span = node.source_span.absolute(),
        .data = .{ .ElementEnd = {} },
    });
}

// ─── Directive ───────────────────────────────────────────────

fn ingestDirective(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    node: *const R3Node,
    dir: r3_ast.DirectiveData,
) !void {
    // Directive nodes don't have a dedicated OpKind yet — emit as a Statement
    // placeholder. The directive's inputs/outputs are ingested as separate ops.
    _ = job;
    _ = view;
    _ = dir;
    _ = node;
    // TODO: add Directive OpKind and proper directive op emission
}

// ─── Attribute Array Builder ─────────────────────────────────
/// Build a flat constant array for element attributes.
/// Layout: [name1, value1, name2, value2, ..., Marker.Bindings, ...]
/// This is the attrs_xref format used by ɵɵelementStart.
/// DOD: Single allocation, cache-friendly linear scan by runtime.
fn buildAttributeArray(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    text_attrs: []const R3Node,
    bound_attrs: []const R3Node,
    references: []const R3Node,
) !u32 {
    if (text_attrs.len == 0 and bound_attrs.len == 0 and references.len == 0) {
        return 0;
    }

    // Count total entries: 2 per text attr + 1 per bound attr name
    var count: usize = 0;
    for (text_attrs) |_| {
        count += 2; // name, value
    }
    // Add marker + bound attr names
    if (bound_attrs.len > 0) {
        count += 1 + bound_attrs.len; // marker + names
    }

    // Add all entries to constant pool
    const start_idx = job.pool.size();

    for (text_attrs) |attr| {
        if (attr.data == .TextAttribute) {
            _ = try job.addConst(attr.data.TextAttribute.name, .String);
            _ = try job.addConst(attr.data.TextAttribute.value, .String);
        }
    }

    if (bound_attrs.len > 0) {
        // AttributeMarker.Bindings value (3 in Angular)
        _ = try job.addConst("3", .String);
        for (bound_attrs) |attr| {
            switch (attr.data) {
                .BoundAttribute => |ba| {
                    _ = try job.addConst(ba.name, .String);
                },
                .BoundEvent => |be| {
                    _ = try job.addConst(be.name, .String);
                },
                else => {},
            }
        }
    }

    _ = view;
    return @intCast(start_idx);
}

// ─── Event Handler Compilation ─────────────────────────────
/// Compile an event handler expression into a function xref.
/// The handler is stored as function ops in the view's functions list.
/// In Angular, event handlers like (click)="handleClick($event)"
/// become ɵɵlistener("click", fn, ...) where fn is a closure.
fn compileEventHandler(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    evt: r3_ast.BoundEventData,
    element_slot: u32,
) !u32 {
    // Convert the handler AST expression to IR
    const handler_ir = try conversion.convertExpr(job, evt.handler);

    // Allocate a function slot for this handler
    const fn_xref = job.slots.allocXref();

    // For arrow functions, we need to create a separate function body
    // For simple method calls like "handleClick($event)", we create
    // a wrapper that calls the method on the context
    const fn_ops = try view.allocFunction();

    // The function body consists of calling the handler expression
    // The handler expression is already an IR expression (e.g., CallExpr)
    // We store it as the function's body for later emission
    const body_op: IrOp = .{
        .kind = .Statement,
        .xref = element_slot,
        .source_span = evt.handler_span,
        .data = .{ .Statement = "" },
    };
    try fn_ops.append(body_op);

    // Store the handler expression in the variable section
    // so it can be referenced by the Listener op
    _ = handler_ir;

    return fn_xref;
}

// ─── Advance Emission Helper ────────────────────────────────
/// Emit Advance ops for a sequence of children.
/// After each non-void child, emit Advance(1) to move the rendering cursor.
/// DOD: Contiguous emission, no branching in the common case.
fn emitAdvancesForChildren(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
    children: []const *const R3Node,
    parent_slot: u32,
    span: AbsoluteSourceSpan,
) !void {
    _ = job;
    _ = parent_slot;
    // Advance is emitted after each child by the child's own ingest function.
    // For elements with children, we emit a final Advance for the parent.
    if (children.len > 0) {
        try view.update.append(.{
            .kind = .Advance,
            .xref = 0,
            .source_span = span,
            .data = .{ .Advance = 1 },
        });
    }
}
