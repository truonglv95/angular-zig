/// IR → Output AST Emission
///
/// Converts IR ops into the Output AST (output/ast.zig)
/// which the JavaScript emitter then renders to source code.
///
/// DOD: Two-pass approach:
///   Pass 1: Scan ops to collect all functions needed
///   Pass 2: Generate Output AST for create + update blocks
///   All output nodes allocated from job's allocator (arena-style)
///
/// Heap allocation strategy:
///   - callRuntime() allocates one Expr for fn_expr pointer (unavoidable:
///     InvokeFunction stores *Expr, not Expr)
///   - Args arrays are always stack-allocated (&[_]Expr{...})
///   - irExprToOutputExpr allocates only for pointer-requiring nodes
///     (Conditional, BinaryOperator, ReadProp, etc.)
const std = @import("std");
const Allocator = std.mem.Allocator;

const job_mod = @import("job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("ops.zig");
const IrOp = ir_ops.IrOp;

const ir_expr = @import("expression.zig");
const IrExpr = ir_expr.IrExpr;

const ir_enums = @import("enums.zig");
const Namespace = ir_enums.Namespace;

const oast = @import("../output/ast.zig");
const Expr = oast.Expr;
const Stmt = oast.Stmt;
const ExprKind = oast.ExprKind;
const StmtKind = oast.StmtKind;
const LiteralValue = oast.LiteralValue;
const FnParam = oast.FnParam;

const source_span = @import("../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

// ─── Emission Result ───────────────────────────────────────

pub const EmittedTemplate = struct {
    /// Template function name (e.g., "MyComponent_Template")
    fn_name: []const u8,
    /// Create-phase statements
    create_stmts: []const Stmt,
    /// Update-phase statements
    update_stmts: []const Stmt,
    /// All helper functions (event handlers, pipe factories, etc.)
    functions: []const Stmt,
};

// ─── Runtime Instruction References ─────────────────────────
/// Names of Angular runtime instructions used in emitted code.
const RUNTIME = struct {
    pub const elementStart = "ɵɵelementStart";
    pub const elementEnd = "ɵɵelementEnd";
    pub const text = "ɵɵtext";
    pub const textInterpolate = "ɵɵtextInterpolate";
    pub const textInterpolate1 = "ɵɵtextInterpolate1";
    pub const textInterpolate2 = "ɵɵtextInterpolate2";
    pub const textInterpolate3 = "ɵɵtextInterpolate3";
    pub const textInterpolate4 = "ɵɵtextInterpolate4";
    pub const textInterpolate5 = "ɵɵtextInterpolate5";
    pub const textInterpolate6 = "ɵɵtextInterpolate6";
    pub const textInterpolate7 = "ɵɵtextInterpolate7";
    pub const textInterpolate8 = "ɵɵtextInterpolate8";
    pub const textInterpolateV = "ɵɵtextInterpolateV";
    pub const property = "ɵɵproperty";
    pub const attribute = "ɵɵattribute";
    pub const classProp = "ɵɵclassProp";
    pub const styleProp = "ɵɵstyleProp";
    pub const styleMap = "ɵɵstyleMap";
    pub const classMap = "ɵɵclassMap";
    pub const listener = "ɵɵlistener";
    pub const advance = "ɵɵadvance";
    pub const pipe = "ɵɵpipe";
    pub const pipeBind1 = "ɵɵpipeBind1";
    pub const pipeBind2 = "ɵɵpipeBind2";
    pub const pipeBind3 = "ɵɵpipeBind3";
    pub const pipeBind4 = "ɵɵpipeBind4";
    pub const twoWayProperty = "ɵɵtwoWayProperty";
    pub const twoWayListener = "ɵɵtwoWayListener";
    pub const projection = "ɵɵprojection";
    pub const projectionDef = "ɵɵprojectionDef";
    pub const containerStart = "ɵɵcontainer";
    pub const containerEnd = "ɵɵcontainerEnd";
    pub const template = "ɵɵtemplate";
    pub const repeater = "ɵɵrepeater";
    pub const repeaterCreate = "ɵɵrepeaterCreate";
    pub const conditional = "ɵɵconditional";
    pub const conditionalCreate = "ɵɵconditionalCreate";
    pub const defer_fn = "ɵɵdefer";
    pub const namespaceDeclare = "ɵɵnamespaceDeclare";
    pub const storeLet = "ɵɵstoreLet";
    pub const reference = "ɵɵreference";
    pub const declareLet = "ɵɵdeclareLet";
    pub const nextContext = "ɵɵnextContext";
    pub const restoreView = "ɵɵrestoreView";
    pub const resetView = "ɵɵresetView";
    pub const getCurrentView = "ɵɵgetCurrentView";
    pub const disableBindings = "ɵɵdisableBindings";
    pub const enableBindings = "ɵɵenableBindings";
    pub const i18nStart = "ɵɵi18nStart";
    pub const i18nEnd = "ɵɵi18nEnd";
    pub const animation = "ɵɵanimation";
    pub const animationListener = "ɵɵanimationListener";

    /// Get the textInterpolateN function name for N expressions
    pub fn textInterpolateN(n: usize) []const u8 {
        return switch (n) {
            0 => textInterpolate,
            1 => textInterpolate1,
            2 => textInterpolate2,
            3 => textInterpolate3,
            4 => textInterpolate4,
            5 => textInterpolate5,
            6 => textInterpolate6,
            7 => textInterpolate7,
            8 => textInterpolate8,
            else => textInterpolateV,
        };
    }
};

// ─── Binary Operator Mapping ────────────────────────────────
/// Maps binary operator u8 codes to JS operator strings.
/// The u8 codes correspond to the operator encoding used in the IR
/// (typically aligned with Angular's Binary.operator enum values).
pub fn binaryOpToString(op: u8) []const u8 {
    return switch (op) {
        // Arithmetic
        0 => "+",
        1 => "-",
        2 => "*",
        3 => "/",
        4 => "%",
        5 => "**",
        // Comparison
        10 => "==",
        11 => "!=",
        12 => "===",
        13 => "!==",
        14 => "<",
        15 => ">",
        16 => "<=",
        17 => ">=",
        // Bitwise
        20 => "&",
        21 => "|",
        22 => "^",
        23 => "<<",
        24 => ">>",
        25 => ">>>",
        // Logical
        30 => "&&",
        31 => "||",
        32 => "??",
        // Nullish coalescing assignment, logical assignment
        33 => "&&=",
        34 => "||=",
        35 => "??=",
        // Comma (rare in templates)
        40 => ",",
        // Instanceof / in (rare but possible)
        50 => "instanceof",
        51 => "in",
        else => "+", // fallback
    };
}

// ─── callRuntime Helper ─────────────────────────────────────
/// Creates an InvokeFunction Expr for a runtime instruction call.
/// Single heap allocation for the fn_expr pointer (unavoidable:
/// InvokeFunction.data stores fn_expr as ?*Expr, not Expr).
/// Args are passed as a stack-allocated slice.
fn callRuntime(allocator: Allocator, fn_name: []const u8, args: []const Expr) !Expr {
    const fn_expr = Expr.readVar(fn_name);
    const fn_ptr = try allocator.create(Expr);
    fn_ptr.* = fn_expr;
    return .{
        .kind = .InvokeFunction,
        .span = null,
        .data = .{ .InvokeFunction = .{ .fn_expr = fn_ptr, .args = args } },
    };
}

/// Like callRuntime but wraps the result in an expression statement.
fn callRuntimeStmt(allocator: Allocator, fn_name: []const u8, args: []const Expr) !?Stmt {
    return Stmt.expressionStmt(try callRuntime(allocator, fn_name, args));
}

/// Heap-allocate an array of Expr values (replaces stack-allocated &[_]Expr{...}).
fn allocArgs(allocator: Allocator, args: []const Expr) ![]const Expr {
    const result = try allocator.alloc(Expr, args.len);
    @memcpy(result, args);
    return result;
}

/// Heap-allocate 2 Expr values.
fn allocArgs2(allocator: Allocator, a: Expr, b: Expr) ![]const Expr {
    const result = try allocator.alloc(Expr, 2);
    result[0] = a;
    result[1] = b;
    return result;
}

/// Heap-allocate 3 Expr values.
fn allocArgs3(allocator: Allocator, a: Expr, b: Expr, c: Expr) ![]const Expr {
    const result = try allocator.alloc(Expr, 3);
    result[0] = a;
    result[1] = b;
    result[2] = c;
    return result;
}


// ─── Main Emit Entry Point ──────────────────────────────────

/// Emit IR ops from a view into an Output AST template function.
pub fn emitView(
    job: *ComponentCompilationJob,
    view: *ViewCompilationUnit,
) !EmittedTemplate {
    // Generate create-phase statements
    var create_stmts = std.array_list.Managed(Stmt).initCapacity(job.allocator, view.create.len()) catch unreachable;

    for (view.create.items()) |op| {
        if (try emitCreateOp(job.allocator, op)) |stmt| {
            try create_stmts.append(stmt);
        }
    }

    // Generate update-phase statements
    var update_stmts = std.array_list.Managed(Stmt).initCapacity(job.allocator, view.update.len()) catch unreachable;

    for (view.update.items()) |op| {
        if (try emitUpdateOp(job.allocator, op)) |stmt| {
            try update_stmts.append(stmt);
        }
    }

    // Generate function statements
    var functions = std.array_list.Managed(Stmt).initCapacity(job.allocator, view.functions.items.len) catch unreachable;

    for (view.functions.items) |fn_ops| {
        if (fn_ops.items.len > 0) {
            // Each function op list becomes a DeclareFunctionStmt
            const fn_stmt = try emitFunctionOps(job.allocator, fn_ops.items);
            try functions.append(fn_stmt);
        }
    }

    const fn_name = if (view.fn_name) |n| n else job.component_name;

    return .{
        .fn_name = fn_name,
        .create_stmts = try create_stmts.toOwnedSlice(),
        .update_stmts = try update_stmts.toOwnedSlice(),
        .functions = try functions.toOwnedSlice(),
    };
}

// ─── Create Op Emission ─────────────────────────────────────

fn emitCreateOp(allocator: Allocator, op: IrOp) !?Stmt {
    return switch (op.data) {
        .ElementStart => |d| emitElementStart(allocator, op.xref, d.name, d.namespace, d.attrs_xref),
        .ElementEnd => emitElementEnd(allocator, op.xref),
        .ContainerStart => |d| emitContainerStart(allocator, op.xref, d.attrs_xref),
        .ContainerEnd => emitContainerEnd(allocator, op.xref),
        .Text => |d| emitText(allocator, op.xref, d.const_index),
        .Attribute => |d| emitAttribute(allocator, op.xref, d.name, d.value),
        .Listener => |d| emitListener(allocator, op.xref, d.name, d.handler_fn_xref),
        .Projection => |d| emitProjection(allocator, op.xref, d.slot_index, d.selector),
        .ProjectionDef => |d| emitProjectionDef(allocator, op.xref, d.slot_index, d.attrs_xref),
        .RepeaterCreate => emitRepeaterCreate(allocator, op.xref),
        .ConditionalCreate => emitConditionalCreate(allocator, op.xref),
        .NamespaceDeclare => |ns| emitNamespaceDeclare(allocator, ns),
        .Defer => |d| emitDefer(allocator, op.xref, d.deps_xref),
        .DeferOn => |trigger| emitDeferOn(allocator, op.xref, trigger),
        .DeferWhen => |d| emitDeferWhen(allocator, op.xref, d.condition_fn_xref),
        .I18nStart => |d| emitI18nStart(allocator, d.xref),
        .I18n => |d| emitI18n(allocator, d.message),
        .I18nEnd => emitI18nEnd(allocator),
        .Animation => |d| emitAnimation(allocator, d.name, d.expr),
        .AnimationListener => |d| emitAnimationListener(allocator, d.name, d.handler_fn_xref, d.phase),
        .ControlFlowBlock => emitControlFlowBlock(allocator),
        .Statement => |s| emitStatement(allocator, s),
        .DisableBindings => emitDisableBindings(allocator),
        .EnableBindings => emitEnableBindings(allocator),
        .SourceLocation => |span| emitSourceLocation(span),
        .ListEnd, .Content => null,
        // Update-only ops: no create-phase emission
        .InterpolateText, .Binding, .Property, .StyleProp, .ClassProp, .StyleMap, .ClassMap, .DomProperty, .TwoWayProperty, .TwoWayListener, .Pipe, .StoreLet, .Advance, .Conditional, .Repeater, .Variable, .I18nExpression, .AnimationBinding, .AnimationString => null,
    };
}

fn emitElementStart(allocator: Allocator, slot: u32, name: []const u8, namespace: Namespace, attrs_xref: u32) !?Stmt {
    _ = namespace;
    // ɵɵelementStart(slot, "name"[, attrs])
    const slot_arg = Expr.literalNum(@floatFromInt(slot));
    const name_arg = Expr.literalStr(name);

    if (attrs_xref > 0) {
        const attrs_arg = Expr.readVar("_c0");
        return callRuntimeStmt(allocator, RUNTIME.elementStart, try allocArgs(allocator, &[_]Expr{ slot_arg, name_arg, attrs_arg }));
    }
    return callRuntimeStmt(allocator, RUNTIME.elementStart, try allocArgs(allocator, &[_]Expr{ slot_arg, name_arg }));
}

fn emitElementEnd(allocator: Allocator, slot: u32) !?Stmt {
    return callRuntimeStmt(allocator, RUNTIME.elementEnd, try allocArgs(allocator, &[_]Expr{
        Expr.literalNum(@floatFromInt(slot)),
    }));
}

fn emitContainerStart(allocator: Allocator, slot: u32, attrs_xref: u32) !?Stmt {
    _ = attrs_xref;
    return callRuntimeStmt(allocator, RUNTIME.containerStart, try allocArgs(allocator, &[_]Expr{
        Expr.literalNum(@floatFromInt(slot)),
    }));
}

fn emitContainerEnd(allocator: Allocator, slot: u32) !?Stmt {
    return callRuntimeStmt(allocator, RUNTIME.containerEnd, try allocArgs(allocator, &[_]Expr{
        Expr.literalNum(@floatFromInt(slot)),
    }));
}

fn emitText(allocator: Allocator, slot: u32, const_index: u32) !?Stmt {
    _ = const_index;
    // ɵɵtext(slot)
    return callRuntimeStmt(allocator, RUNTIME.text, try allocArgs(allocator, &[_]Expr{
        Expr.literalNum(@floatFromInt(slot)),
    }));
}

fn emitListener(allocator: Allocator, slot: u32, name: []const u8, handler_xref: u32) !?Stmt {
    _ = slot;
    _ = handler_xref;
    // ɵɵlistener("click", handlerFn, false)
    return callRuntimeStmt(allocator, RUNTIME.listener, try allocArgs(allocator, &[_]Expr{
        Expr.literalStr(name),
        Expr.readVar("handler"),
        Expr.literalNum(0),
    }));
}

fn emitProjection(allocator: Allocator, slot: u32, slot_index: u32, selector: ?[]const u8) !?Stmt {
    _ = slot;
    if (selector) |sel| {
        return callRuntimeStmt(allocator, RUNTIME.projection, try allocArgs(allocator, &[_]Expr{
            Expr.literalNum(@floatFromInt(slot_index)),
            Expr.literalStr(sel),
        }));
    }
    return callRuntimeStmt(allocator, RUNTIME.projection, try allocArgs(allocator, &[_]Expr{
        Expr.literalNum(@floatFromInt(slot_index)),
    }));
}

fn emitProjectionDef(allocator: Allocator, slot: u32, slot_index: u32, attrs_xref: u32) !?Stmt {
    _ = slot;
    _ = attrs_xref;
    return callRuntimeStmt(allocator, RUNTIME.projectionDef, try allocArgs(allocator, &[_]Expr{
        Expr.literalNum(@floatFromInt(slot_index)),
    }));
}

fn emitRepeaterCreate(allocator: Allocator, slot: u32) !?Stmt {
    return callRuntimeStmt(allocator, RUNTIME.repeaterCreate, try allocArgs(allocator, &[_]Expr{
        Expr.literalNum(@floatFromInt(slot)),
    }));
}

fn emitConditionalCreate(allocator: Allocator, slot: u32) !?Stmt {
    return callRuntimeStmt(allocator, RUNTIME.conditionalCreate, try allocArgs(allocator, &[_]Expr{
        Expr.literalNum(@floatFromInt(slot)),
    }));
}

/// Fixed: uses @intFromEnum directly instead of string roundtrip.
fn emitNamespaceDeclare(allocator: Allocator, ns: Namespace) !?Stmt {
    const ns_val = @intFromEnum(ns);
    return callRuntimeStmt(allocator, RUNTIME.namespaceDeclare, try allocArgs(allocator, &[_]Expr{
        Expr.literalNum(@floatFromInt(ns_val)),
    }));
}

fn emitDefer(allocator: Allocator, slot: u32, deps_xref: u32) !?Stmt {
    _ = deps_xref;
    return callRuntimeStmt(allocator, RUNTIME.defer_fn, try allocArgs(allocator, &[_]Expr{
        Expr.literalNum(@floatFromInt(slot)),
    }));
}

fn emitDeferOn(allocator: Allocator, slot: u32, trigger: ir_enums.DeferTriggerKind) !?Stmt {
    const trigger_val: u8 = @intFromEnum(trigger);
    return callRuntimeStmt(allocator, RUNTIME.defer_fn, try allocArgs(allocator, &[_]Expr{
        Expr.literalNum(@floatFromInt(slot)),
        Expr.literalNum(@floatFromInt(trigger_val)),
    }));
}

fn emitDisableBindings(allocator: Allocator) !?Stmt {
    return callRuntimeStmt(allocator, RUNTIME.disableBindings, try allocArgs(allocator, &[_]Expr{}));
}

fn emitEnableBindings(allocator: Allocator) !?Stmt {
    return callRuntimeStmt(allocator, RUNTIME.enableBindings, try allocArgs(allocator, &[_]Expr{}));
}

fn emitSourceLocation(span: AbsoluteSourceSpan) !?Stmt {
    _ = span;
    return null;
}

// ─── Update Op Emission ─────────────────────────────────────

fn emitUpdateOp(allocator: Allocator, op: IrOp) !?Stmt {
    return switch (op.data) {
        .InterpolateText => |d| emitInterpolateText(allocator, op.xref, d.const_indices, d.expressions),
        .Property => |d| emitProperty(allocator, d.name, d.expression),
        .Binding => |d| emitBinding(allocator, d.name, d.expression),
        .ClassProp => |d| emitClassProp(allocator, d.name, d.expression),
        .StyleProp => |d| emitStyleProp(allocator, d.name, d.expression, d.unit),
        .StyleMap => |d| emitStyleMap(allocator, d.expression),
        .ClassMap => |d| emitClassMap(allocator, d.expression),
        .DomProperty => |d| emitDomProperty(allocator, d.name, d.expression),
        .TwoWayProperty => |d| emitTwoWayProperty(allocator, d.name, d.expression),
        .TwoWayListener => |d| emitTwoWayListener(allocator, d.name, d.handler_fn_xref),
        .Pipe => |d| emitPipe(allocator, d.name, d.args, d.pure),
        .StoreLet => |d| emitStoreLet(allocator, d.name, d.expression),
        .Advance => |d| emitAdvance(allocator, d),
        .Conditional => |d| emitConditional(allocator, op.xref, d.condition_expr),
        .Repeater => |d| emitRepeater(allocator, op.xref, d.track_by_fn, d.collection_expr),
        .Variable => |d| emitVariable(allocator, d.name, d.value),
        .AnimationBinding => |d| emitAnimationBinding(allocator, d.name, d.expression),
        .AnimationString => |d| emitAnimationString(allocator, d.name, d.expression),
        .I18nExpression => |d| emitI18nExpression(allocator, d.expressions),
        else => null,
    };
}

fn emitInterpolateText(allocator: Allocator, slot: u32, const_indices: []const u32, expressions: []const *const IrExpr) !?Stmt {
    const n = expressions.len;
    const fn_name = RUNTIME.textInterpolateN(n);

    const slot_arg = Expr.literalNum(@floatFromInt(slot));

    // Build args: slot, [constStart, ...expressions]
    // Use a fixed buffer for up to 8 expressions (covers textInterpolate1..8)
    // For larger counts, fall back to a stack-allocated var-length approach
    // by building the array directly.
    const total_args: usize = 1 + (if (const_indices.len > 0) @as(usize, 1) else @as(usize, 0)) + n;

    if (total_args <= 10) {
        // Stack-allocated fixed array
        const args_buf = try allocator.alloc(Expr, 10);
        var args_len: usize = 0;
        args_buf[args_len] = slot_arg;
        args_len += 1;

        if (const_indices.len > 0) {
            args_buf[args_len] = Expr.literalNum(@floatFromInt(const_indices[0]));
            args_len += 1;
        }

        for (expressions) |ir_e| {
            args_buf[args_len] = irExprToOutputExpr(allocator, ir_e.*);
            args_len += 1;
        }

        return callRuntimeStmt(allocator, fn_name, args_buf[0..args_len]);
    }

    // Fallback: heap-allocated args for very large interpolation counts
    const args_slice = try allocator.alloc(Expr, total_args);
    var i: usize = 0;
    args_slice[i] = slot_arg;
    i += 1;

    if (const_indices.len > 0) {
        args_slice[i] = Expr.literalNum(@floatFromInt(const_indices[0]));
        i += 1;
    }

    for (expressions) |ir_e| {
        args_slice[i] = irExprToOutputExpr(allocator, ir_e.*);
        i += 1;
    }

    return callRuntimeStmt(allocator, fn_name, args_slice);
}

fn emitProperty(allocator: Allocator, name: []const u8, expression: *const IrExpr) !?Stmt {
    const value_arg = irExprToOutputExpr(allocator, expression.*);
    return callRuntimeStmt(allocator, RUNTIME.property, try allocArgs(allocator, &[_]Expr{
        Expr.literalStr(name),
        value_arg,
    }));
}

fn emitBinding(allocator: Allocator, name: []const u8, expression: *const IrExpr) !?Stmt {
    const value_arg = irExprToOutputExpr(allocator, expression.*);
    return callRuntimeStmt(allocator, RUNTIME.attribute, try allocArgs(allocator, &[_]Expr{
        Expr.literalStr(name),
        value_arg,
    }));
}

fn emitClassProp(allocator: Allocator, name: []const u8, expression: *const IrExpr) !?Stmt {
    const value_arg = irExprToOutputExpr(allocator, expression.*);
    return callRuntimeStmt(allocator, RUNTIME.classProp, try allocArgs(allocator, &[_]Expr{
        Expr.literalStr(name),
        value_arg,
    }));
}

fn emitStyleProp(allocator: Allocator, name: []const u8, expression: *const IrExpr, unit: ?[]const u8) !?Stmt {
    const value_arg = irExprToOutputExpr(allocator, expression.*);
    if (unit) |u| {
        return callRuntimeStmt(allocator, RUNTIME.styleProp, try allocArgs(allocator, &[_]Expr{
            Expr.literalStr(name),
            value_arg,
            Expr.literalStr(u),
        }));
    }
    return callRuntimeStmt(allocator, RUNTIME.styleProp, try allocArgs(allocator, &[_]Expr{
        Expr.literalStr(name),
        value_arg,
    }));
}

fn emitStyleMap(allocator: Allocator, expression: *const IrExpr) !?Stmt {
    const value_arg = irExprToOutputExpr(allocator, expression.*);
    return callRuntimeStmt(allocator, RUNTIME.styleMap, try allocArgs(allocator, &[_]Expr{value_arg}));
}

fn emitClassMap(allocator: Allocator, expression: *const IrExpr) !?Stmt {
    const value_arg = irExprToOutputExpr(allocator, expression.*);
    return callRuntimeStmt(allocator, RUNTIME.classMap, try allocArgs(allocator, &[_]Expr{value_arg}));
}

fn emitDomProperty(allocator: Allocator, name: []const u8, expression: *const IrExpr) !?Stmt {
    const value_arg = irExprToOutputExpr(allocator, expression.*);
    return callRuntimeStmt(allocator, RUNTIME.property, try allocArgs(allocator, &[_]Expr{
        Expr.literalStr(name),
        value_arg,
    }));
}

fn emitTwoWayProperty(allocator: Allocator, name: []const u8, expression: *const IrExpr) !?Stmt {
    const value_arg = irExprToOutputExpr(allocator, expression.*);
    return callRuntimeStmt(allocator, RUNTIME.twoWayProperty, try allocArgs(allocator, &[_]Expr{
        Expr.literalStr(name),
        value_arg,
    }));
}

fn emitTwoWayListener(allocator: Allocator, name: []const u8, handler_xref: u32) !?Stmt {
    _ = handler_xref;
    return callRuntimeStmt(allocator, RUNTIME.twoWayListener, try allocArgs(allocator, &[_]Expr{
        Expr.literalStr(name),
    }));
}

fn emitPipe(allocator: Allocator, name: []const u8, args: []const *const IrExpr, pure: bool) !?Stmt {
    _ = pure;
    // ɵɵpipe(pipeIndex, "pipeName", ...args)
    // Stack-allocate: 2 base args + up to 4 pipe args
    const total = 2 + args.len;
    if (total <= 6) {
        const args_buf = try allocator.alloc(Expr, 6);
        args_buf[0] = Expr.literalNum(0); // pipe index
        args_buf[1] = Expr.literalStr(name);
        for (args, 0..) |arg, i| {
            args_buf[2 + i] = irExprToOutputExpr(allocator, arg.*);
        }
        return callRuntimeStmt(allocator, RUNTIME.pipe, args_buf[0..total]);
    }

    // Fallback for many pipe args
    const pipe_args = try allocator.alloc(Expr, total);
    pipe_args[0] = Expr.literalNum(0);
    pipe_args[1] = Expr.literalStr(name);
    for (args, 0..) |arg, j| {
        pipe_args[2 + j] = irExprToOutputExpr(allocator, arg.*);
    }
    return callRuntimeStmt(allocator, RUNTIME.pipe, pipe_args);
}

fn emitStoreLet(allocator: Allocator, name: []const u8, expression: *const IrExpr) !?Stmt {
    const value_arg = irExprToOutputExpr(allocator, expression.*);
    return callRuntimeStmt(allocator, RUNTIME.storeLet, try allocArgs(allocator, &[_]Expr{
        Expr.literalStr(name),
        value_arg,
    }));
}

fn emitAdvance(allocator: Allocator, d: u32) !?Stmt {
    return callRuntimeStmt(allocator, RUNTIME.advance, try allocArgs(allocator, &[_]Expr{
        Expr.literalNum(@floatFromInt(d)),
    }));
}

fn emitConditional(allocator: Allocator, slot: u32, condition: *const IrExpr) !?Stmt {
    const cond_arg = irExprToOutputExpr(allocator, condition.*);
    return callRuntimeStmt(allocator, RUNTIME.conditional, try allocArgs(allocator, &[_]Expr{
        Expr.literalNum(@floatFromInt(slot)),
        cond_arg,
    }));
}

fn emitRepeater(allocator: Allocator, slot: u32, track_by_fn: ?*const IrExpr, collection_expr: ?*const IrExpr) !?Stmt {
    // ɵɵrepeater(slot, trackByOrCollection)
    // Prefer collection expression over track_by_fn for the primary arg.
    const expr_arg = if (collection_expr) |ce|
        irExprToOutputExpr(allocator, ce.*)
    else if (track_by_fn) |tf|
        irExprToOutputExpr(allocator, tf.*)
    else
        Expr.literal(.Null);

    return callRuntimeStmt(allocator, RUNTIME.repeater, try allocArgs(allocator, &[_]Expr{
        Expr.literalNum(@floatFromInt(slot)),
        expr_arg,
    }));
}

fn emitVariable(allocator: Allocator, name: []const u8, value: *const IrExpr) !?Stmt {
    const value_arg = irExprToOutputExpr(allocator, value.*);
    return Stmt.declareVar(name, value_arg);
}

fn emitAnimationBinding(allocator: Allocator, name: []const u8, expression: *const IrExpr) !?Stmt {
    const value_arg = irExprToOutputExpr(allocator, expression.*);
    return callRuntimeStmt(allocator, RUNTIME.animation, try allocArgs(allocator, &[_]Expr{
        Expr.literalStr(name),
        value_arg,
    }));
}

fn emitAnimationString(allocator: Allocator, name: []const u8, expression: *const IrExpr) !?Stmt {
    const value_arg = irExprToOutputExpr(allocator, expression.*);
    // ɵɵanimation is also used for animation string bindings
    return callRuntimeStmt(allocator, RUNTIME.animation, try allocArgs(allocator, &[_]Expr{
        Expr.literalStr(name),
        value_arg,
    }));
}

// ─── Missing Create Op Emitters ───────────────────────────────

fn emitAttribute(allocator: Allocator, slot: u32, name: []const u8, value: []const u8) !?Stmt {
    _ = slot;
    return callRuntimeStmt(allocator, RUNTIME.attribute, try allocArgs(allocator, &[_]Expr{
        Expr.literalStr(name),
        Expr.literalStr(value),
    }));
}

fn emitDeferWhen(allocator: Allocator, slot: u32, condition_fn_xref: u32) !?Stmt {
    _ = condition_fn_xref;
    // ɵɵdefer(slot, 6, conditionFn) — 6 = DeferTriggerKind.When
    return callRuntimeStmt(allocator, RUNTIME.defer_fn, try allocArgs(allocator, &[_]Expr{
        Expr.literalNum(@floatFromInt(slot)),
        Expr.literalNum(6), // When trigger
    }));
}

fn emitI18nStart(allocator: Allocator, xref: u32) !?Stmt {
    return callRuntimeStmt(allocator, RUNTIME.i18nStart, try allocArgs(allocator, &[_]Expr{
        Expr.literalNum(@floatFromInt(xref)),
    }));
}

fn emitI18n(_: Allocator, message: []const u8) !?Stmt {
    _ = message;
    // i18n message ops are typically handled in the constant pool;
    // this is a placeholder that emits the start marker.
    return null;
}

fn emitI18nEnd(allocator: Allocator) !?Stmt {
    return callRuntimeStmt(allocator, RUNTIME.i18nEnd, try allocArgs(allocator, &[_]Expr{}));
}

fn emitAnimation(allocator: Allocator, name: []const u8, expr: *const IrExpr) !?Stmt {
    const value_arg = irExprToOutputExpr(allocator, expr.*);
    return callRuntimeStmt(allocator, RUNTIME.animation, try allocArgs(allocator, &[_]Expr{
        Expr.literalStr(name),
        value_arg,
    }));
}

fn emitAnimationListener(allocator: Allocator, name: []const u8, handler_fn_xref: u32, phase: ?[]const u8) !?Stmt {
    _ = handler_fn_xref;
    _ = phase;
    return callRuntimeStmt(allocator, RUNTIME.animationListener, try allocArgs(allocator, &[_]Expr{
        Expr.literalStr(name),
    }));
}

fn emitControlFlowBlock(allocator: Allocator) !?Stmt {
    // ControlFlowBlock is a container marker — no runtime call needed
    _ = allocator;
    return null;
}

fn emitStatement(allocator: Allocator, s: []const u8) !?Stmt {
    _ = allocator;
    if (s.len == 0) return null;
    return Stmt.expressionStmt(Expr.readVar(s));
}

// ─── Missing Update Op Emitters ───────────────────────────────

fn emitI18nExpression(allocator: Allocator, expressions: []const *const IrExpr) !?Stmt {
    // i18n expressions are emitted as ɵɵtextInterpolate with the
    // substitution expressions from the ICU message.
    if (expressions.len == 0) return null;

    // Stack-allocate for up to 8 expressions
    if (expressions.len <= 8) {
        const args_buf = try allocator.alloc(Expr, 9);
        args_buf[0] = Expr.literalNum(0); // slot (placeholder)
        for (expressions, 0..) |ir_e, i| {
            args_buf[1 + i] = irExprToOutputExpr(allocator, ir_e.*);
        }
        return callRuntimeStmt(allocator, RUNTIME.textInterpolate, args_buf[0 .. 1 + expressions.len]);
    }

    // Fallback for many expressions
    const args = try allocator.alloc(Expr, 1 + expressions.len);
    args[0] = Expr.literalNum(0);
    for (expressions, 0..) |ir_e, j| {
        args[1 + j] = irExprToOutputExpr(allocator, ir_e.*);
    }
    return callRuntimeStmt(allocator, RUNTIME.textInterpolate, args);
}

fn emitFunctionOps(allocator: Allocator, ops: []const IrOp) !Stmt {
    _ = ops;
    _ = allocator;
    return Stmt.expressionStmt(Expr.readVar("/* function */"));
}

// ─── IR Expression → Output Expression ─────────────────────
/// Converts an IrExpr into an output Expr.
///
/// This is the core translation from IR-level expressions to the output
/// AST that the JS emitter renders. Each IrExpr kind maps to the
/// appropriate output Expr kind.
///
/// Some output Expr kinds require heap-allocated pointers (Conditional,
/// BinaryOperator, ReadProp, Not, InvokeFunction). These allocations
/// are unavoidable due to the output AST's pointer-based design.
/// The allocator should be the job's arena allocator for bulk cleanup.
fn irExprToOutputExpr(allocator: Allocator, ir: IrExpr) Expr {
    return switch (ir.data) {
        // ── Context ────────────────────────────────────────────
        .Context => Expr.readVar("ctx"),

        // ── Variable Reads ────────────────────────────────────
        .ReadVariable => |rv| Expr.readVar(rv.name),

        // ── Empty / Null ─────────────────────────────────────
        .EmptyExpr => Expr.literal(.Null),

        // ── Constant Pool Reference ───────────────────────────
        // Produces: _c0[index]  (ReadProp on the constant array)
        .ConstCollected => |idx| blk: {
            const receiver = Expr.readVar("_c0");
            // Convert index to string for property name.
            // The emitter renders ReadProp as `receiver.name`.
            // For numeric indices, bracket access (_c0[5]) is more correct,
            // but the output AST uses ReadProp. The emitter should handle
            // numeric names by using bracket notation.
            const idx_str = std.fmt.allocPrint(allocator, "{d}", .{idx}) catch "0";
            const recv_ptr = allocator.create(Expr) catch unreachable;
            recv_ptr.* = receiver;
            break :blk .{
                .kind = .ReadProp,
                .span = null,
                .data = .{ .ReadProp = .{ .receiver = recv_ptr, .name = idx_str } },
            };
        },

        // ── Safe Property Read ────────────────────────────────
        // Produces: receiver.name (null-checked at IR level)
        .SafePropertyRead => |spr| blk: {
            const receiver = irExprToOutputExpr(allocator, spr.receiver.*);
            const recv_ptr = allocator.create(Expr) catch unreachable;
            recv_ptr.* = receiver;
            break :blk .{
                .kind = .ReadProp,
                .span = null,
                .data = .{ .ReadProp = .{ .receiver = recv_ptr, .name = spr.name } },
            };
        },

        // ── Safe Keyed Read ───────────────────────────────────
        // Produces: receiver[key]
        .SafeKeyedRead => |skr| blk: {
            const receiver = irExprToOutputExpr(allocator, skr.receiver.*);
            const key = irExprToOutputExpr(allocator, skr.key.*);
            const recv_ptr = allocator.create(Expr) catch unreachable;
            recv_ptr.* = receiver;
            const key_ptr = allocator.create(Expr) catch unreachable;
            key_ptr.* = key;
            break :blk .{
                .kind = .ReadKey,
                .span = null,
                .data = .{ .ReadKey = .{ .receiver = recv_ptr, .index = key_ptr } },
            };
        },

        // ── Conditional Case ──────────────────────────────────
        // Produces: condition ? value : null
        .ConditionalCase => |cc| blk: {
            const condition = irExprToOutputExpr(allocator, cc.condition.*);
            const value = irExprToOutputExpr(allocator, cc.value.*);
            const cond_ptr = allocator.create(Expr) catch unreachable;
            cond_ptr.* = condition;
            const true_ptr = allocator.create(Expr) catch unreachable;
            true_ptr.* = value;
            const false_ptr = allocator.create(Expr) catch unreachable;
            false_ptr.* = Expr.literal(.Null);
            break :blk .{
                .kind = .Conditional,
                .span = null,
                .data = .{ .Conditional = .{
                    .condition = cond_ptr,
                    .true_case = true_ptr,
                    .false_case = false_ptr,
                } },
            };
        },

        // ── Pipe Binding ──────────────────────────────────────
        // Produces: ɵɵpipeBindN(pipeIdx, ctx, ...args)
        .PipeBinding => |pb| blk: {
            const n = pb.args.len;
            const bind_fn = switch (n) {
                0 => RUNTIME.pipeBind1,
                1 => RUNTIME.pipeBind1,
                2 => RUNTIME.pipeBind2,
                3 => RUNTIME.pipeBind3,
                else => RUNTIME.pipeBind4,
            };
            const fn_expr = Expr.readVar(bind_fn);
            const fn_ptr = allocator.create(Expr) catch unreachable;
            fn_ptr.* = fn_expr;

            // Build args: pipeIdx, ctx, ...converted_args
            // Always heap-allocate — the Expr outlives this function call.
            const total_args = 2 + n;
            const args_buf = allocator.alloc(Expr, total_args) catch unreachable;
            args_buf[0] = Expr.literalNum(0); // pipe index (placeholder)
            args_buf[1] = Expr.readVar("ctx");
            for (pb.args, 0..) |arg, i| {
                args_buf[2 + i] = irExprToOutputExpr(allocator, arg.*);
            }
            break :blk .{
                .kind = .InvokeFunction,
                .span = null,
                .data = .{ .InvokeFunction = .{ .fn_expr = fn_ptr, .args = args_buf } },
            };
        },

        // ── Variadic Pipe Binding ─────────────────────────────
        .PipeBindingVariadic => |pbv| blk: {
            const fn_expr = Expr.readVar(RUNTIME.pipe);
            const fn_ptr = allocator.create(Expr) catch unreachable;
            fn_ptr.* = fn_expr;

            const vb_args = allocator.alloc(Expr, 2 + pbv.args.len) catch unreachable;
            vb_args[0] = Expr.literalNum(0);
            vb_args[1] = Expr.literalStr(pbv.name);
            for (pbv.args, 0..) |arg, j| {
                vb_args[2 + j] = irExprToOutputExpr(allocator, arg.*);
            }
            break :blk .{
                .kind = .InvokeFunction,
                .span = null,
                .data = .{ .InvokeFunction = .{ .fn_expr = fn_ptr, .args = vb_args } },
            };
        },

        // ── Arrow Function ────────────────────────────────────
        // Produces: (param1, param2, ...) => bodyExpr
        .ArrowFunction => |af| blk: {
            // Convert param names to FnParam array
            const params = allocator.alloc(FnParam, af.param_names.len) catch unreachable;
            for (af.param_names, 0..) |name, i| {
                params[i] = .{ .name = name };
            }

            // Convert body expression
            const body_expr = irExprToOutputExpr(allocator, af.body.*);
            const body_ptr = allocator.create(Expr) catch unreachable;
            body_ptr.* = body_expr;

            break :blk .{
                .kind = .ArrowFunction,
                .span = null,
                .data = .{ .ArrowFunction = .{
                    .params = params,
                    .body = .{ .expression = body_ptr },
                } },
            };
        },

        // ── Next Context ──────────────────────────────────────
        // Produces: ɵɵnextContext() — navigates up one context level
        .NextContext => |levels| blk: {
            // For level 0, just return ctx
            if (levels == 0) {
                break :blk Expr.readVar("ctx");
            }
            // For higher levels, emit ɵɵnextContext() calls
            // For now, emit the appropriate number of nextContext calls
            // wrapped in a comma expression (simplified for level 1)
            const fn_expr = Expr.readVar(RUNTIME.nextContext);
            const fn_ptr = allocator.create(Expr) catch unreachable;
            fn_ptr.* = fn_expr;
            break :blk .{
                .kind = .InvokeFunction,
                .span = null,
                .data = .{ .InvokeFunction = .{ .fn_expr = fn_ptr, .args = &[_]Expr{} } },
            };
        },

        // ── Reference ─────────────────────────────────────────
        // Produces: ctx_rN (template reference variable)
        .Reference => |ref| blk: {
            // Template references are accessed as ctx_refName or _rN
            const ref_name = std.fmt.allocPrint(allocator, "_r{d}", .{ref.xref}) catch ref.name;
            break :blk Expr.readVar(ref_name);
        },

        // ── Pure Function Expression ──────────────────────────
        // Produces: __pureFnN(arg1, arg2, ...) — function call
        .PureFunctionExpr => |pfe| blk: {
            const fn_name = std.fmt.allocPrint(allocator, "__pureFn{d}", .{pfe.fn_ref}) catch "__pureFn";
            const fn_expr = Expr.readVar(fn_name);
            const fn_ptr = allocator.create(Expr) catch unreachable;
            fn_ptr.* = fn_expr;

            const args = allocator.alloc(Expr, pfe.params.len) catch unreachable;
            for (pfe.params, 0..) |arg, i| {
                args[i] = irExprToOutputExpr(allocator, arg.*);
            }

            break :blk .{
                .kind = .InvokeFunction,
                .span = null,
                .data = .{ .InvokeFunction = .{ .fn_expr = fn_ptr, .args = args } },
            };
        },

        // ── Pure Function Parameter ───────────────────────────
        // Produces: __param_N
        .PureFunctionParameterExpr => |pfpe| blk: {
            const param_name = std.fmt.allocPrint(allocator, "__param_{d}", .{pfpe.index}) catch "__param_0";
            break :blk Expr.readVar(param_name);
        },

        // ── Two-Way Binding Set ───────────────────────────────
        // Produces: ctx.name = rhsExpr (via a comma expression or direct assignment)
        .TwoWayBindingSet => |twb| blk: {
            const lhs = irExprToOutputExpr(allocator, twb.lhs.*);
            const rhs = irExprToOutputExpr(allocator, twb.rhs.*);
            const lhs_ptr = allocator.create(Expr) catch unreachable;
            lhs_ptr.* = lhs;
            const rhs_ptr = allocator.create(Expr) catch unreachable;
            rhs_ptr.* = rhs;
            break :blk .{
                .kind = .BinaryOperator,
                .span = null,
                .data = .{ .BinaryOperator = .{
                    .operator = "=",
                    .lhs = lhs_ptr,
                    .rhs = rhs_ptr,
                } },
            };
        },

        // ── Slot Literal ──────────────────────────────────────
        // Produces: a numeric literal (slot index)
        .SlotLiteralExpr => |slot| Expr.literalNum(@floatFromInt(slot)),

        // ── Binary Expression ──────────────────────────────────
        // Produces: lhs op rhs
        .BinaryExpr => |be| blk: {
            const lhs = irExprToOutputExpr(allocator, be.left.*);
            const rhs = irExprToOutputExpr(allocator, be.right.*);
            const lhs_ptr = allocator.create(Expr) catch unreachable;
            lhs_ptr.* = lhs;
            const rhs_ptr = allocator.create(Expr) catch unreachable;
            rhs_ptr.* = rhs;
            const op_str = binaryOpToString(be.op);
            break :blk .{
                .kind = .BinaryOperator,
                .span = null,
                .data = .{ .BinaryOperator = .{
                    .operator = op_str,
                    .lhs = lhs_ptr,
                    .rhs = rhs_ptr,
                } },
            };
        },

        // ── Call Expression ────────────────────────────────────
        // Produces: receiver(arg1, arg2, ...)
        .CallExpr => |ce| blk: {
            const receiver = irExprToOutputExpr(allocator, ce.receiver.*);
            const recv_ptr = allocator.create(Expr) catch unreachable;
            recv_ptr.* = receiver;

            const args = allocator.alloc(Expr, ce.args.len) catch unreachable;
            for (ce.args, 0..) |arg, i| {
                args[i] = irExprToOutputExpr(allocator, arg.*);
            }

            break :blk .{
                .kind = .InvokeFunction,
                .span = null,
                .data = .{ .InvokeFunction = .{ .fn_expr = recv_ptr, .args = args } },
            };
        },

        // ── Literal Expression ─────────────────────────────────
        // Produces: a literal value from the IR
        .LiteralExpr => |le| blk: {
            // Try to parse as number first, fall back to string literal
            const trimmed = std.mem.trim(u8, le.value, " \t\n\r");
            const val = std.fmt.parseFloat(f64, trimmed) catch {
                break :blk Expr.literalStr(le.value);
            };
            break :blk Expr.literalNum(val);
        },

        // ── Read Property Expression ────────────────────────────
        // Produces: receiver.name
        .ReadPropExpr => |rpe| blk: {
            const receiver = irExprToOutputExpr(allocator, rpe.receiver.*);
            const recv_ptr = allocator.create(Expr) catch unreachable;
            recv_ptr.* = receiver;
            break :blk .{
                .kind = .ReadProp,
                .span = null,
                .data = .{ .ReadProp = .{ .receiver = recv_ptr, .name = rpe.name } },
            };
        },

        // ── Conditional Expression ─────────────────────────────
        // Produces: condition ? trueExpr : falseExpr
        .ConditionalExpr => |cexpr| blk: {
            const condition = irExprToOutputExpr(allocator, cexpr.condition.*);
            const true_expr = irExprToOutputExpr(allocator, cexpr.true_expr.*);
            const false_expr = irExprToOutputExpr(allocator, cexpr.false_expr.*);
            const cond_ptr = allocator.create(Expr) catch unreachable;
            cond_ptr.* = condition;
            const true_ptr = allocator.create(Expr) catch unreachable;
            true_ptr.* = true_expr;
            const false_ptr = allocator.create(Expr) catch unreachable;
            false_ptr.* = false_expr;
            break :blk .{
                .kind = .Conditional,
                .span = null,
                .data = .{ .Conditional = .{
                    .condition = cond_ptr,
                    .true_case = true_ptr,
                    .false_case = false_ptr,
                } },
            };
        },

        // ── Not Expression ─────────────────────────────────────
        // Produces: !expr
        .NotExpr => |ne| blk: {
            const operand = irExprToOutputExpr(allocator, ne.expression.*);
            const op_ptr = allocator.create(Expr) catch unreachable;
            op_ptr.* = operand;
            break :blk .{
                .kind = .Not,
                .span = null,
                .data = .{ .Not = .{ .condition = op_ptr } },
            };
        },
    };
}

// ─── Tests ────────────────────────────────────────────────────

test "binaryOpToString maps operators" {
    try std.testing.expectEqualStrings("+", binaryOpToString(0));
    try std.testing.expectEqualStrings("-", binaryOpToString(1));
    try std.testing.expectEqualStrings("*", binaryOpToString(2));
    try std.testing.expectEqualStrings("/", binaryOpToString(3));
    try std.testing.expectEqualStrings("===", binaryOpToString(12));
    try std.testing.expectEqualStrings("!==", binaryOpToString(13));
    try std.testing.expectEqualStrings(">", binaryOpToString(15));
    try std.testing.expectEqualStrings("<", binaryOpToString(14));
    try std.testing.expectEqualStrings(">=", binaryOpToString(17));
    try std.testing.expectEqualStrings("<=", binaryOpToString(16));
    try std.testing.expectEqualStrings("&&", binaryOpToString(30));
    try std.testing.expectEqualStrings("||", binaryOpToString(31));
    try std.testing.expectEqualStrings("??", binaryOpToString(32));
    try std.testing.expectEqualStrings("%", binaryOpToString(4));
    try std.testing.expectEqualStrings("**", binaryOpToString(5));
}

test "irExprToOutputExpr — Context" {
    const allocator = std.testing.allocator;
    const span = AbsoluteSourceSpan{ .start = 0, .end = 0 };
    const ir = IrExpr.context(span);
    const out = irExprToOutputExpr(allocator, ir);
    try std.testing.expectEqual(ExprKind.ReadVar, out.kind);
    try std.testing.expectEqualStrings("ctx", out.data.ReadVar.name);
}

test "irExprToOutputExpr — ReadVariable" {
    const allocator = std.testing.allocator;
    const span = AbsoluteSourceSpan{ .start = 0, .end = 5 };
    const ir = IrExpr.readVariable("items", 3, span);
    const out = irExprToOutputExpr(allocator, ir);
    try std.testing.expectEqual(ExprKind.ReadVar, out.kind);
    try std.testing.expectEqualStrings("items", out.data.ReadVar.name);
}

test "irExprToOutputExpr — EmptyExpr produces Null" {
    const allocator = std.testing.allocator;
    const span = AbsoluteSourceSpan{ .start = 0, .end = 0 };
    const ir = IrExpr.empty(span);
    const out = irExprToOutputExpr(allocator, ir);
    try std.testing.expectEqual(ExprKind.Literal, out.kind);
    try std.testing.expectEqual(LiteralValue.Null, out.data.Literal);
}

test "irExprToOutputExpr — ConstCollected produces ReadProp" {
    const allocator = std.testing.allocator;
    const span = AbsoluteSourceSpan{ .start = 0, .end = 0 };
    const ir = IrExpr.constCollected(5, span);
    const out = irExprToOutputExpr(allocator, ir);
    try std.testing.expectEqual(ExprKind.ReadProp, out.kind);
    try std.testing.expectEqualStrings("5", out.data.ReadProp.name);
}

test "irExprToOutputExpr — SlotLiteralExpr" {
    const allocator = std.testing.allocator;
    const ir: IrExpr = .{
        .kind = .SlotLiteralExpr,
        .span = .{ .start = 0, .end = 0 },
        .data = .{ .SlotLiteralExpr = 42 },
    };
    const out = irExprToOutputExpr(allocator, ir);
    try std.testing.expectEqual(ExprKind.Literal, out.kind);
    try std.testing.expectEqual(42.0, out.data.Literal.Number);
}

test "emitNamespaceDeclare uses intFromEnum directly" {
    const allocator = std.testing.allocator;

    const result_html = try emitNamespaceDeclare(allocator, .HTML);
    try std.testing.expect(result_html != null);

    const result_svg = try emitNamespaceDeclare(allocator, .SVG);
    try std.testing.expect(result_svg != null);

    const result_math = try emitNamespaceDeclare(allocator, .MathML);
    try std.testing.expect(result_math != null);
}

test "emitElementStart without attrs" {
    const allocator = std.testing.allocator;
    const result = try emitElementStart(allocator, 0, "div", .HTML, 0);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(StmtKind.Expression, result.?.kind);
}

test "emitElementStart with attrs" {
    const allocator = std.testing.allocator;
    const result = try emitElementStart(allocator, 2, "span", .HTML, 5);
    try std.testing.expect(result != null);
}

test "callRuntime produces InvokeFunction" {
    const allocator = std.testing.allocator;
    const expr = try callRuntime(allocator, "ɵɵadvance", try allocArgs(allocator, &[_]Expr{
        Expr.literalNum(1),
    }));
    try std.testing.expectEqual(ExprKind.InvokeFunction, expr.kind);
    try std.testing.expect(expr.data.InvokeFunction.fn_expr != null);
    try std.testing.expectEqual(@as(usize, 1), expr.data.InvokeFunction.args.len);
}
