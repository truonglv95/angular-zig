/// IR Instruction — Helpers for emitting Ivy instruction calls
///
/// Port of: compiler/src/template/pipeline/src/instruction.ts (1136 LoC)
///
/// DOD: All instruction helpers return output AST expression strings.
/// Arena-allocated, zero-copy where possible.
const std = @import("std");

/// Ivy runtime instruction names.
pub const Instruction = struct {
    pub const elementStart = "ɵɵelementStart";
    pub const elementEnd = "ɵɵelementEnd";
    pub const element = "ɵɵelement";
    pub const containerStart = "ɵɵcontainerStart";
    pub const containerEnd = "ɵɵcontainerEnd";
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
    pub const property = "ɵɵproperty";
    pub const propertyInterpolate = "ɵɵpropertyInterpolate";
    pub const classProp = "ɵɵclassProp";
    pub const styleProp = "ɵɵstyleProp";
    pub const styleMap = "ɵɵstyleMap";
    pub const classMap = "ɵɵclassMap";
    pub const listener = "ɵɵlistener";
    pub const twoWayListener = "ɵɵtwoWayListener";
    pub const advance = "ɵɵadvance";
    pub const template = "ɵɵtemplate";
    pub const templateRefExtractor = "ɵɵtemplateRefExtractor";
    pub const contentQuery = "ɵɵcontentQuery";
    pub const viewQuery = "ɵɵviewQuery";
    pub const pipe = "ɵɵpipe";
    pub const pipeBind1 = "ɵɵpipeBind1";
    pub const pipeBind2 = "ɵɵpipeBind2";
    pub const pipeBind3 = "ɵɵpipeBind3";
    pub const pipeBind4 = "ɵɵpipeBind4";
    pub const pipeBindV = "ɵɵpipeBindV";
    pub const foreignComponent = "ɵɵforeignComponent";
    pub const foreignContent = "ɵɵforeignContent";
    pub const pureFunction0 = "ɵɵpureFunction0";
    pub const pureFunction1 = "ɵɵpureFunction1";
    pub const pureFunction2 = "ɵɵpureFunction2";
    pub const pureFunction3 = "ɵɵpureFunction3";
    pub const pureFunction4 = "ɵɵpureFunction4";
    pub const pureFunction5 = "ɵɵpureFunction5";
    pub const pureFunction6 = "ɵɵpureFunction6";
    pub const pureFunction7 = "ɵɵpureFunction7";
    pub const pureFunction8 = "ɵɵpureFunction8";
    pub const pureFunctionV = "ɵɵpureFunctionV";
    pub const restoreView = "ɵɵrestoreView";
    pub const nextContext = "ɵɵnextContext";
    pub const getCurrentView = "ɵɵgetCurrentView";
    pub const namespaceDeclare = "ɵɵnamespaceDeclare";
    pub const projection = "ɵɵprojection";
    pub const projectionDef = "ɵɵprojectionDef";
    pub const deferOp = "ɵɵdefer";
    pub const deferOnIdle = "ɵɵdeferOnIdle";
    pub const deferOnViewport = "ɵɵdeferOnViewport";
    pub const deferOnInteraction = "ɵɵdeferOnInteraction";
    pub const deferOnHover = "ɵɵdeferOnHover";
    pub const deferOnTimer = "ɵɵdeferOnTimer";
    pub const deferWhen = "ɵɵdeferWhen";
    pub const deferPrefetchOnIdle = "ɵɵdeferPrefetchOnIdle";
    pub const deferPrefetchOnViewport = "ɵɵdeferPrefetchOnViewport";
    pub const deferPrefetchOnInteraction = "ɵɵdeferPrefetchOnInteraction";
    pub const deferPrefetchOnHover = "ɵɵdeferPrefetchOnHover";
    pub const deferPrefetchOnTimer = "ɵɵdeferPrefetchOnTimer";
    pub const deferPrefetchWhen = "ɵɵdeferPrefetchWhen";
    pub const deferBlockPlaceholder = "ɵɵdeferBlockPlaceholder";
    pub const deferBlockLoading = "ɵɵdeferBlockLoading";
    pub const deferBlockError = "ɵɵdeferBlockError";
    pub const disableBindings = "ɵɵdisableBindings";
    pub const enableBindings = "ɵɵenableBindings";
    pub const saveView = "ɵɵsaveView";
    pub const reference = "ɵɵreference";
    pub const conditionalCreate = "ɵɵconditionalCreate";
    pub const conditional = "ɵɵconditional";
    pub const repeaterCreate = "ɵɵrepeaterCreate";
    pub const repeater = "ɵɵrepeater";
    pub const storeLet = "ɵɵstoreLet";
    pub const i18n = "ɵɵi18n";
    pub const i18nAttributes = "ɵɵi18nAttributes";
    pub const i18nStart = "ɵɵi18nStart";
    pub const i18nEnd = "ɵɵi18nEnd";
    pub const i18nApply = "ɵɵi18nApply";
    pub const incrementalHydration = "ɵɵincrementalHydration";
    pub const twoWayProperty = "ɵɵtwoWayProperty";
    pub const synHostListener = "ɵɵsyntheticHostListener";
    pub const synHostProperty = "ɵɵsyntheticHostProperty";
};

/// Generate an ɵɵelementStart(slot, "tag") instruction call.
pub fn elementStart(allocator: std.mem.Allocator, slot: u32, tag: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({d}, \"{s}\")", .{ Instruction.elementStart, slot, tag });
}

/// Generate an ɵɵelementEnd() instruction call.
pub fn elementEnd(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, Instruction.elementStart[0..Instruction.elementStart.len-5] ++ "End()");
}

/// Generate an ɵɵtext(slot) instruction call.
pub fn text(allocator: std.mem.Allocator, slot: u32) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({d})", .{ Instruction.text, slot });
}

/// Generate an ɵɵtextInterpolate(expr) instruction call.
pub fn textInterpolate(allocator: std.mem.Allocator, expr: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({s})", .{ Instruction.textInterpolate, expr });
}

/// Generate an ɵɵproperty(name, expr) instruction call.
pub fn property(allocator: std.mem.Allocator, name: []const u8, expr: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}(\"{s}\", {s})", .{ Instruction.property, name, expr });
}

/// Generate an ɵɵlistener(name, handler) instruction call.
pub fn listener(allocator: std.mem.Allocator, name: []const u8, handler: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}(\"{s}\", {s})", .{ Instruction.listener, name, handler });
}

/// Generate an ɵɵadvance(delta) instruction call.
pub fn advance(allocator: std.mem.Allocator, delta: u32) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({d})", .{ Instruction.advance, delta });
}

/// Generate an ɵɵpipe(slot, name) instruction call.
pub fn pipe(allocator: std.mem.Allocator, slot: u32, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({d}, \"{s}\")", .{ Instruction.pipe, slot, name });
}

/// Generate an ɵɵpipeBindN(pipeSlot, ctxSlot, ...args) instruction call.
pub fn pipeBind(allocator: std.mem.Allocator, n: u32, pipe_slot: u32, ctx_slot: u32, args: []const []const u8) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    const fn_name = switch (n) {
        0 => Instruction.pipeBind1,
        1 => Instruction.pipeBind1,
        2 => Instruction.pipeBind2,
        3 => Instruction.pipeBind3,
        else => Instruction.pipeBind4,
    };
    try buf.appendSlice(fn_name);
    try buf.append('(');
    try std.fmt.format(buf.writer(), "{d}, {d}", .{ pipe_slot, ctx_slot });
    for (args) |arg| {
        try buf.appendSlice(", ");
        try buf.appendSlice(arg);
    }
    try buf.append(')');
    return buf.toOwnedSlice();
}

/// Generate an ɵɵtemplate(slot, fn, deps, vars) instruction call.
pub fn template(allocator: std.mem.Allocator, slot: u32, fn_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({d}, {s})", .{ Instruction.template, slot, fn_name });
}

/// Generate an ɵɵconditionalCreate(slot, fn) instruction call.
pub fn conditionalCreate(allocator: std.mem.Allocator, slot: u32, fn_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({d}, {s})", .{ Instruction.conditionalCreate, slot, fn_name });
}

/// Generate an ɵɵrepeaterCreate(slot, fn, collection, track) instruction call.
pub fn repeaterCreate(allocator: std.mem.Allocator, slot: u32, fn_name: []const u8, collection: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({d}, {s}, {s})", .{ Instruction.repeaterCreate, slot, fn_name, collection });
}

/// Generate an ɵɵprojection(slot) instruction call.
pub fn projection(allocator: std.mem.Allocator, slot: u32) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({d})", .{ Instruction.projection, slot });
}

/// Generate an ɵɵprojectionDef(selectors) instruction call.
pub fn projectionDef(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, Instruction.projectionDef ++ "()");
}

/// Generate an ɵɵnamespaceDeclare(ns) instruction call.
pub fn namespaceDeclare(allocator: std.mem.Allocator, ns: u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({d})", .{ Instruction.namespaceDeclare, ns });
}

/// Generate an ɵɵclassProp(slot, name, expr) instruction call.
pub fn classProp(allocator: std.mem.Allocator, slot: u32, name: []const u8, expr: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({d}, \"{s}\", {s})", .{ Instruction.classProp, slot, name, expr });
}

/// Generate an ɵɵstyleProp(slot, name, expr, unit) instruction call.
pub fn styleProp(allocator: std.mem.Allocator, slot: u32, name: []const u8, expr: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({d}, \"{s}\", {s})", .{ Instruction.styleProp, slot, name, expr });
}

/// Generate an ɵɵstyleMap(slot, expr) instruction call.
pub fn styleMap(allocator: std.mem.Allocator, slot: u32, expr: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({d}, {s})", .{ Instruction.styleMap, slot, expr });
}

/// Generate an ɵɵclassMap(slot, expr) instruction call.
pub fn classMap(allocator: std.mem.Allocator, slot: u32, expr: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({d}, {s})", .{ Instruction.classMap, slot, expr });
}

/// Generate an ɵɵrestoreView(view) instruction call.
pub fn restoreView(allocator: std.mem.Allocator, view: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({s})", .{ Instruction.restoreView, view });
}

/// Generate an ɵɵnextContext(n) instruction call.
pub fn nextContext(allocator: std.mem.Allocator, n: u32) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({d})", .{ Instruction.nextContext, n });
}

/// Generate an ɵɵgetCurrentView() instruction call.
pub fn getCurrentView(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, Instruction.getCurrentView ++ "()");
}

/// Generate an ɵɵstoreLet(slot, name, expr) instruction call.
pub fn storeLet(allocator: std.mem.Allocator, slot: u32, name: []const u8, expr: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({d}, \"{s}\", {s})", .{ Instruction.storeLet, slot, name, expr });
}

/// Generate an ɵɵdefer(slot) instruction call.
/// Note: function name is `deferOp` because `defer` is a Zig keyword.
pub fn deferOp(allocator: std.mem.Allocator, slot: u32) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({d})", .{ Instruction.deferOp, slot });
}

/// Generate an ɵɵdeferOnIdle() instruction call.
pub fn deferOnIdle(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, Instruction.deferOnIdle ++ "()");
}

/// Generate an ɵɵdeferOnViewport() instruction call.
pub fn deferOnViewport(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, Instruction.deferOnViewport ++ "()");
}

/// Generate an ɵɵdeferOnInteraction() instruction call.
pub fn deferOnInteraction(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, Instruction.deferOnInteraction ++ "()");
}

/// Generate an ɵɵdeferOnHover() instruction call.
pub fn deferOnHover(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, Instruction.deferOnHover ++ "()");
}

/// Generate an ɵɵdeferOnTimer(ms) instruction call.
pub fn deferOnTimer(allocator: std.mem.Allocator, ms: u32) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({d})", .{ Instruction.deferOnTimer, ms });
}

/// Generate an ɵɵdeferWhen(expr) instruction call.
pub fn deferWhen(allocator: std.mem.Allocator, expr: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({s})", .{ Instruction.deferWhen, expr });
}

/// Generate an ɵɵi18n(msg) instruction call.
pub fn i18n(allocator: std.mem.Allocator, msg: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({s})", .{ Instruction.i18n, msg });
}

/// Generate an ɵɵi18nStart(slot, msg) instruction call.
pub fn i18nStart(allocator: std.mem.Allocator, slot: u32, msg: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({d}, {s})", .{ Instruction.i18nStart, slot, msg });
}

/// Generate an ɵɵi18nEnd() instruction call.
pub fn i18nEnd(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, Instruction.i18nEnd ++ "()");
}

/// Generate an ɵɵreference(slot) instruction call.
pub fn reference(allocator: std.mem.Allocator, slot: u32) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({d})", .{ Instruction.reference, slot });
}

/// Generate an ɵɵpureFunction0(slot, fn) instruction call.
pub fn pureFunction0(allocator: std.mem.Allocator, slot: u32, fn_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({d}, {s})", .{ Instruction.pureFunction0, slot, fn_name });
}

/// Generate an ɵɵpureFunction1(slot, fn, arg) instruction call.
pub fn pureFunction1(allocator: std.mem.Allocator, slot: u32, fn_name: []const u8, arg: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({d}, {s}, {s})", .{ Instruction.pureFunction1, slot, fn_name, arg });
}

/// Generate an ɵɵtwoWayProperty(name, expr) instruction call.
pub fn twoWayProperty(allocator: std.mem.Allocator, name: []const u8, expr: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}(\"{s}\", {s})", .{ Instruction.twoWayProperty, name, expr });
}

/// Generate an ɵɵtwoWayListener(name, handler) instruction call.
pub fn twoWayListener(allocator: std.mem.Allocator, name: []const u8, handler: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}(\"{s}\", {s})", .{ Instruction.twoWayListener, name, handler });
}

/// Generate an ɵɵdisableBindings() instruction call.
pub fn disableBindings(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, Instruction.disableBindings ++ "()");
}

/// Generate an ɵɵenableBindings() instruction call.
pub fn enableBindings(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, Instruction.enableBindings ++ "()");
}

/// Generate an ɵɵincrementalHydration(slot) instruction call.
pub fn incrementalHydration(allocator: std.mem.Allocator, slot: u32) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({d})", .{ Instruction.incrementalHydration, slot });
}

test "elementStart instruction" {
    const allocator = std.testing.allocator;
    const result = try elementStart(allocator, 0, "div");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("ɵɵelementStart(0, \"div\")", result);
}

test "advance instruction" {
    const allocator = std.testing.allocator;
    const result = try advance(allocator, 3);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("ɵɵadvance(3)", result);
}

// ─── Remaining instruction helpers (expanded from stubs) ─────

/// Generate an ɵɵforeignComponent(slot, ref, props) instruction call.
pub fn foreignComponent(allocator: std.mem.Allocator, slot: u32, ref: []const u8, props: ?[]const u8) ![]const u8 {
    if (props) |p| {
        return std.fmt.allocPrint(allocator, "{s}({d}, {s}, {s})", .{ Instruction.foreignComponent, slot, ref, p });
    }
    return std.fmt.allocPrint(allocator, "{s}({d}, {s})", .{ Instruction.foreignComponent, slot, ref });
}

/// Generate an ɵɵforeignContent(slot, index) instruction call.
pub fn foreignContent(allocator: std.mem.Allocator, slot: u32, index: u32) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({d}, {d})", .{ Instruction.foreignContent, slot, index });
}

/// Generate an ɵɵelementContainerStart(slot, tag) instruction call.
pub fn elementContainerStart(allocator: std.mem.Allocator, slot: u32, tag: ?[]const u8) ![]const u8 {
    if (tag) |t| {
        return std.fmt.allocPrint(allocator, "{s}({d}, \"{s}\")", .{ Instruction.containerStart, slot, t });
    }
    return std.fmt.allocPrint(allocator, "{s}({d})", .{ Instruction.containerStart, slot });
}

/// Generate an ɵɵelementContainer(slot, tag) instruction call.
pub fn elementContainer(allocator: std.mem.Allocator, slot: u32, tag: ?[]const u8) ![]const u8 {
    if (tag) |t| {
        return std.fmt.allocPrint(allocator, "{s}({d}, \"{s}\")", .{ Instruction.element, slot, t });
    }
    return std.fmt.allocPrint(allocator, "{s}({d})", .{ Instruction.element, slot });
}

/// Generate an ɵɵelementContainerEnd() instruction call.
pub fn elementContainerEnd(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, Instruction.containerEnd ++ "()");
}

/// Generate a two-way binding set expression: target = value.
pub fn twoWayBindingSet(allocator: std.mem.Allocator, target: []const u8, value: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s} = {s}", .{ target, value });
}

/// Generate an ɵɵnamespaceHTML() instruction call.
pub fn namespaceHTML(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, "ɵɵnamespaceHTML()");
}

/// Generate an ɵɵnamespaceSVG() instruction call.
pub fn namespaceSVG(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, "ɵɵnamespaceSVG()");
}

/// Generate an ɵɵnamespaceMath() instruction call.
pub fn namespaceMath(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, "ɵɵnamespaceMath()");
}

/// Generate an ɵɵresetView(value) instruction call.
pub fn resetView(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵresetView({s})", .{value});
}

/// Generate an ɵɵenableIncrementalHydrationRuntime() instruction call.
pub fn enableIncrementalHydrationRuntime(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, "ɵɵenableIncrementalHydrationRuntime()");
}

/// Generate an ɵɵconditionalBranchCreate(slot, fn) instruction call.
pub fn conditionalBranchCreate(allocator: std.mem.Allocator, slot: u32, fn_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵconditionalBranchCreate({d}, {s})", .{ slot, fn_name });
}

/// Generate an ɵɵdeclareLet(slot, name) instruction call.
pub fn declareLet(allocator: std.mem.Allocator, slot: u32, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵdeclareLet({d}, \"{s}\")", .{ slot, name });
}

/// Generate an ɵɵreadContextLet(slot) instruction call.
pub fn readContextLet(allocator: std.mem.Allocator, slot: u32) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵreadContextLet({d})", .{slot});
}

/// Generate an ɵɵariaProperty(slot, name, value) instruction call.
pub fn ariaProperty(allocator: std.mem.Allocator, slot: u32, name: []const u8, value: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵariaProperty({d}, \"{s}\", {s})", .{ slot, name, value });
}

/// Generate an ɵɵcontrol(slot) instruction call.
pub fn control(allocator: std.mem.Allocator, slot: u32) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵcontrol({d})", .{slot});
}

/// Generate an ɵɵcontrolCreate(sourceSpan) instruction call.
pub fn controlCreate(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, "ɵɵcontrolCreate()");
}

/// Generate a ɵɵdomElement(slot, tag) instruction call.
pub fn domElement(allocator: std.mem.Allocator, slot: u32, tag: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵdomElement({d}, \"{s}\")", .{ slot, tag });
}

/// Generate a ɵɵdomElementStart(slot, tag) instruction call.
pub fn domElementStart(allocator: std.mem.Allocator, slot: u32, tag: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵdomElementStart({d}, \"{s}\")", .{ slot, tag });
}

/// Generate a ɵɵdomElementEnd() instruction call.
pub fn domElementEnd(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, "ɵɵdomElementEnd()");
}

/// Generate a ɵɵdomElementContainerStart(slot, tag) instruction call.
pub fn domElementContainerStart(allocator: std.mem.Allocator, slot: u32, tag: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵdomElementContainerStart({d}, \"{s}\")", .{ slot, tag });
}

/// Generate a ɵɵdomElementContainer(slot, tag) instruction call.
pub fn domElementContainer(allocator: std.mem.Allocator, slot: u32, tag: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵdomElementContainer({d}, \"{s}\")", .{ slot, tag });
}

/// Generate a ɵɵdomElementContainerEnd() instruction call.
pub fn domElementContainerEnd(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, "ɵɵdomElementContainerEnd()");
}

/// Generate a ɵɵdomListener(name, handler) instruction call.
pub fn domListener(allocator: std.mem.Allocator, name: []const u8, handler: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵdomListener(\"{s}\", {s})", .{ name, handler });
}

/// Generate a ɵɵdomTemplate(slot, fn) instruction call.
pub fn domTemplate(allocator: std.mem.Allocator, slot: u32, fn_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵdomTemplate({d}, {s})", .{ slot, fn_name });
}

/// Generate an ɵɵi18nExp(expr) instruction call.
pub fn i18nExp(allocator: std.mem.Allocator, expr: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵi18nExp({s})", .{expr});
}

/// Generate an ɵɵi18nApply(slot) instruction call.
pub fn i18nApply(allocator: std.mem.Allocator, slot: u32) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵi18nApply({d})", .{slot});
}

/// Generate an ɵɵdomProperty(slot, name, value) instruction call.
pub fn domProperty(allocator: std.mem.Allocator, slot: u32, name: []const u8, value: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵdomProperty({d}, \"{s}\", {s})", .{ slot, name, value });
}

/// Generate an ɵɵanimation(name, slot, handler) instruction call.
pub fn animation(allocator: std.mem.Allocator, name: []const u8, slot: u32, handler: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵanimation(\"{s}\", {d}, {s})", .{ name, slot, handler });
}

/// Generate an ɵɵanimationString(name, slot, value) instruction call.
pub fn animationString(allocator: std.mem.Allocator, name: []const u8, slot: u32, value: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵanimationString(\"{s}\", {d}, {s})", .{ name, slot, value });
}

/// Generate an ɵɵanimationListener(name, handler, phase) instruction call.
pub fn animationListener(allocator: std.mem.Allocator, name: []const u8, handler: []const u8, phase: ?[]const u8) ![]const u8 {
    if (phase) |p| {
        return std.fmt.allocPrint(allocator, "ɵɵanimationListener(\"{s}\", {s}, \"{s}\")", .{ name, handler, p });
    }
    return std.fmt.allocPrint(allocator, "ɵɵanimationListener(\"{s}\", {s})", .{ name, handler });
}

/// Generate an ɵɵattachSourceLocation(slot, location) instruction call.
pub fn attachSourceLocation(allocator: std.mem.Allocator, slot: u32, location: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵattachSourceLocation({d}, {s})", .{ slot, location });
}

/// Generate an arrow function expression: (params) => body.
pub fn arrowFunction(allocator: std.mem.Allocator, params: []const []const u8, body: []const u8) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();
    try buf.append('(');
    for (params, 0..) |param, i| {
        if (i > 0) try buf.appendSlice(", ");
        try buf.appendSlice(param);
    }
    try buf.appendSlice(") => ");
    try buf.appendSlice(body);
    return buf.toOwnedSlice();
}

/// Generate a ɵɵconditional(slot, cases) instruction call.
pub fn conditional(allocator: std.mem.Allocator, slot: u32, cases: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵconditional({d}, {s})", .{ slot, cases });
}

/// Generate a ɵɵsyntheticHostProperty(name, value) instruction call.
pub fn syntheticHostProperty(allocator: std.mem.Allocator, name: []const u8, value: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵsyntheticHostProperty(\"{s}\", {s})", .{ name, value });
}

/// Generate a ɵɵpureFunction(slot, fn, args) instruction call.
pub fn pureFunction(allocator: std.mem.Allocator, slot: u32, fn_name: []const u8, args: []const []const u8) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();
    try buf.appendSlice("ɵɵpureFunction(");
    try std.fmt.format(buf.writer(), "{d}, {s}", .{ slot, fn_name });
    for (args) |arg| {
        try buf.appendSlice(", ");
        try buf.appendSlice(arg);
    }
    try buf.append(')');
    return buf.toOwnedSlice();
}

/// Generate an ɵɵattribute(slot, name, value) instruction call.
pub fn attribute(allocator: std.mem.Allocator, slot: u32, name: []const u8, value: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵattribute({d}, \"{s}\", {s})", .{ slot, name, value });
}

/// Generate a ɵɵpipeBindV(slot, offset, args) instruction call.
pub fn pipeBindV(allocator: std.mem.Allocator, slot: u32, offset: u32, args: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "ɵɵpipeBindV({d}, {d}, {s})", .{ slot, offset, args });
}

// ─── Additional tests ───────────────────────────────────────

test "foreignComponent instruction" {
    const allocator = std.testing.allocator;
    const result = try foreignComponent(allocator, 0, "Comp", null);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "ɵɵforeignComponent(0, Comp)") != null);
}

test "namespaceHTML instruction" {
    const allocator = std.testing.allocator;
    const result = try namespaceHTML(allocator);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("ɵɵnamespaceHTML()", result);
}

test "conditionalBranchCreate instruction" {
    const allocator = std.testing.allocator;
    const result = try conditionalBranchCreate(allocator, 1, "BranchFn");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("ɵɵconditionalBranchCreate(1, BranchFn)", result);
}

test "declareLet instruction" {
    const allocator = std.testing.allocator;
    const result = try declareLet(allocator, 0, "myLet");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("ɵɵdeclareLet(0, \"myLet\")", result);
}

test "arrowFunction instruction" {
    const allocator = std.testing.allocator;
    const params = [_][]const u8{ "$event", "ctx" };
    const result = try arrowFunction(allocator, &params, "return $event");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("($event, ctx) => return $event", result);
}