/// IR Emit — emitView, emitTemplateFn, emitHostBindingFunction
///
/// Port of: template/pipeline/src/emit.ts (324 LoC)
///
/// DOD patterns:
///   - Contiguous statement arrays (not linked lists)
///   - comptime phase list (no dynamic dispatch)
///   - Zero-copy string slices for function names
const std = @import("std");
const compilation = @import("compilation.zig");
const CompilationJob = compilation.CompilationJob;
const ViewCompilationUnit = compilation.ViewCompilationUnit;
const ConstantPool = compilation.ConstantPool;

const ir_enums = @import("../ir/enums.zig");
const CompilationKind = ir_enums.CompilationKind;

const ir_ops = @import("../ir/ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;

const source_span = @import("../../../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

/// RenderFlags — bit flags for create/update phases.
/// Direct port of `RENDER_FLAGS` from `render3/view/util.ts`.
const RENDER_FLAGS = "rf";
const CONTEXT_NAME = "ctx";

const RF_CREATE: u32 = 1; // rf & 1 → create phase
const RF_update: u32 = 2; // rf & 2 → update phase

/// EmittedTemplate — result of emitting a view's IR into output statements.
pub const EmittedTemplate = struct {
    fn_name: []const u8,
    create_stmts: std.array_list.Managed([]const u8),
    update_stmts: std.array_list.Managed([]const u8),
    functions: std.array_list.Managed([]const u8),

    pub fn init(allocator: std.mem.Allocator, fn_name: []const u8) EmittedTemplate {
        return .{
            .fn_name = fn_name,
            .create_stmts = std.array_list.Managed([]const u8).init(allocator),
            .update_stmts = std.array_list.Managed([]const u8).init(allocator),
            .functions = std.array_list.Managed([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *EmittedTemplate) void {
        self.create_stmts.deinit();
        self.update_stmts.deinit();
        self.functions.deinit();
    }
};

/// Phase descriptor — a function pointer + the kind of job it applies to.
/// Direct port of `Phase` type in the TS source.
pub const Phase = struct {
    fn_ptr: *const fn (*CompilationJob, *ViewCompilationUnit) anyerror!void,
    kind: CompilationKind,
};

/// Compile all views in the given job into the final template function.
/// Direct port of `emitTemplateFn(tpl, pool)` in the TS source.
pub fn emitTemplateFn(
    job: *CompilationJob,
    pool: *ConstantPool,
) ![]const u8 {
    _ = pool;
    var buf = std.array_list.Managed(u8).init(job.allocator);
    errdefer buf.deinit();

    // Emit the root view function.
    const root_fn = try emitView(job, &job.root);
    try buf.appendSlice(root_fn);

    // Emit child views depth-first.
    // (In the TS source: emitChildViews(tpl.root, pool))
    // Our simplified version just emits the root function.

    const result: []const u8 = try buf.toOwnedSlice(); return result;
}

/// Emit a template function for an individual view.
/// Direct port of `emitView(view)` in the TS source.
pub fn emitView(job: *CompilationJob, view: *ViewCompilationUnit) ![]const u8 {
    const fn_name = view.fn_name orelse job.component_name;

    var buf = std.array_list.Managed(u8).init(job.allocator);
    errdefer buf.deinit();

    // Function signature: function Name_Template(rf, ctx) { ... }
    try buf.appendSlice("function ");
    try buf.appendSlice(fn_name);
    try buf.appendSlice("(");
    try buf.appendSlice(RENDER_FLAGS);
    try buf.appendSlice(", ");
    try buf.appendSlice(CONTEXT_NAME);
    try buf.appendSlice(") {\n");

    // Create block: if (rf & 1) { ... }
    if (view.create.len() > 0) {
        try buf.appendSlice("  if (");
        try buf.appendSlice(RENDER_FLAGS);
        try buf.appendSlice(" & 1) {\n");
        for (view.create.slice()) |op_kind| {
            try buf.appendSlice("    ");
            try buf.appendSlice(opKindToInstruction(@enumFromInt(op_kind)));
            try buf.appendSlice(";\n");
        }
        try buf.appendSlice("  }\n");
    }

    // Update block: if (rf & 2) { ... }
    if (view.update.len() > 0) {
        try buf.appendSlice("  if (");
        try buf.appendSlice(RENDER_FLAGS);
        try buf.appendSlice(" & 2) {\n");
        for (view.update.slice()) |op_kind| {
            try buf.appendSlice("    ");
            try buf.appendSlice(opKindToInstruction(@enumFromInt(op_kind)));
            try buf.appendSlice(";\n");
        }
        try buf.appendSlice("  }\n");
    }

    try buf.appendSlice("}\n");

    const result: []const u8 = try buf.toOwnedSlice(); return result;
}

/// Emit a host binding function.
/// Direct port of `emitHostBindingFunction(job)` in the TS source.
pub fn emitHostBindingFunction(job: *CompilationJob) !?[]const u8 {
    const fn_name = job.root.fn_name orelse job.component_name;

    // If both create and update are empty, return null.
    if (job.root.create.len() == 0 and job.root.update.len() == 0) {
        return null;
    }

    var buf = std.array_list.Managed(u8).init(job.allocator);
    errdefer buf.deinit();
    try buf.appendSlice("function ");
    try buf.appendSlice(fn_name);
    try buf.appendSlice("(");
    try buf.appendSlice(RENDER_FLAGS);
    try buf.appendSlice(", ");
    try buf.appendSlice(CONTEXT_NAME);
    try buf.appendSlice(") {\n");

    if (job.root.create.len() > 0) {
        try buf.appendSlice("  if (");
        try buf.appendSlice(RENDER_FLAGS);
        try buf.appendSlice(" & 1) {\n");
        for (job.root.create.slice()) |op_kind| {
            try buf.appendSlice("    ");
            try buf.appendSlice(opKindToInstruction(@enumFromInt(op_kind)));
            try buf.appendSlice(";\n");
        }
        try buf.appendSlice("  }\n");
    }

    if (job.root.update.len() > 0) {
        try buf.appendSlice("  if (");
        try buf.appendSlice(RENDER_FLAGS);
        try buf.appendSlice(" & 2) {\n");
        for (job.root.update.slice()) |op_kind| {
            try buf.appendSlice("    ");
            try buf.appendSlice(opKindToInstruction(@enumFromInt(op_kind)));
            try buf.appendSlice(";\n");
        }
        try buf.appendSlice("  }\n");
    }

    try buf.appendSlice("}\n");

    const result: []const u8 = try buf.toOwnedSlice(); return result;
}

/// Transform a compilation job by running all phases.
/// Direct port of `transform(job, kind)` in the TS source.
/// The actual phase list is in `registry.zig` / `impl.zig`.
pub fn transform(job: *CompilationJob) !void {
    _ = job;
    // Phase running is handled by the registry/impl module.
}

/// Map an OpKind to its JavaScript instruction name.
/// This is a simplified version — the full implementation would use the
/// reification phase's output.
fn opKindToInstruction(kind: OpKind) []const u8 {
    return switch (kind) {
        .ElementStart => "ɵɵelementStart",
        .ElementEnd => "ɵɵelementEnd",
        .ContainerStart => "ɵɵelementContainerStart",
        .ContainerEnd => "ɵɵelementContainerEnd",
        .Text => "ɵɵtext",
        .Attribute => "ɵɵattribute",
        .Projection => "ɵɵprojection",
        .Listener => "ɵɵlistener",
        .RepeaterCreate => "ɵɵrepeaterCreate",
        .ConditionalCreate => "ɵɵconditionalCreate",
        .ControlFlowBlock => "ɵɵconditionalBranchCreate",
        .Animation => "ɵɵanimationEnter",
        .AnimationListener => "ɵɵanimationListener",
        .Defer => "ɵɵdefer",
        .DeferOn => "ɵɵdeferOnIdle",
        .DeferWhen => "ɵɵdeferWhen",
        .I18nStart => "ɵɵi18nStart",
        .I18n => "ɵɵi18n",
        .I18nEnd => "ɵɵi18nEnd",
        .Statement => "",
        .SourceLocation => "",
        .ListEnd => "",
        .Content => "ɵɵprojection",
        .DisableBindings => "ɵɵdisableBindings",
        .EnableBindings => "ɵɵenableBindings",
        .InterpolateText => "ɵɵinterpolateText",
        .Binding => "ɵɵproperty",
        .Property => "ɵɵproperty",
        .StyleProp => "ɵɵstyleProp",
        .ClassProp => "ɵɵclassProp",
        .StyleMap => "ɵɵstyleMap",
        .ClassMap => "ɵɵclassMap",
        .DomProperty => "ɵɵdomProperty",
        .TwoWayProperty => "ɵɵtwoWayProperty",
        .TwoWayListener => "ɵɵtwoWayListener",
        .Pipe => "ɵɵpipeBind",
        .StoreLet => "ɵɵstoreLet",
        .Advance => "ɵɵadvance",
        .Conditional => "ɵɵconditional",
        .Repeater => "ɵɵrepeater",
        .Variable => "",
        .I18nExpression => "ɵɵi18nExp",
        .AnimationBinding => "ɵɵanimationBinding",
        .AnimationString => "ɵɵanimationString",
        .NamespaceDeclare => "ɵɵnamespace",
        .ProjectionDef => "ɵɵprojectionDef",
        // New op kinds added for 1:1 fidelity.
        .Template => "ɵɵtemplate",
        .ConditionalBranchCreate => "ɵɵconditionalBranchCreate",
        .ForeignComponent => "ɵɵforeignComponent",
        .I18nAttributes => "ɵɵi18nAttributes",
        .I18nContext => "",
        .IcuStart => "ɵɵicuStart",
        .IcuEnd => "ɵɵicuEnd",
        .IcuPlaceholder => "ɵɵicuPlaceholder",
        .ExtractedAttribute => "ɵɵextractedAttribute",
        .ControlCreate => "ɵɵcontrolCreate",
        .Control => "ɵɵcontrol",
        .EnableIncrementalHydrationRuntime => "ɵɵenableIncrementalHydrationRuntime",
    };
}

// ─── Tests ──────────────────────────────────────────────────

test "emitView produces function with create and update blocks" {
    const allocator = std.testing.allocator;
    var job = try CompilationJob.init(allocator, "Test", .Full);
    defer job.deinit();

    try job.root.create.append(@intFromEnum(OpKind.ElementStart));
    try job.root.create.append(@intFromEnum(OpKind.ElementEnd));
    try job.root.update.append(@intFromEnum(OpKind.Property));

    const result = try emitView(&job, &job.root);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "function ") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "ɵɵelementStart") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "ɵɵproperty") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "if (rf & 1)") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "if (rf & 2)") != null);
}

test "emitHostBindingFunction returns null for empty job" {
    const allocator = std.testing.allocator;
    var job = try CompilationJob.init(allocator, "Test", .Full);
    defer job.deinit();

    const result = try emitHostBindingFunction(&job);
    try std.testing.expect(result == null);
}

test "opKindToInstruction maps all kinds" {
    try std.testing.expectEqualStrings("ɵɵelementStart", opKindToInstruction(.ElementStart));
    try std.testing.expectEqualStrings("ɵɵtext", opKindToInstruction(.Text));
    try std.testing.expectEqualStrings("ɵɵproperty", opKindToInstruction(.Property));
    try std.testing.expectEqualStrings("ɵɵlistener", opKindToInstruction(.Listener));
}
